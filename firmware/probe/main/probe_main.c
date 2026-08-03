// ตรวจว่าบอร์ด CYD ตัวนี้มีจอสัมผัส XPT2046 จริงไหม และค่าดิบที่อ่านได้เป็นเท่าไร
//
// รอบก่อนของ probe ตัวนี้ใช้หา MADCTL กับลำดับสี — ผลจดไว้ใน DESIGN.md แล้ว โค้ดรอบนั้น
// อยู่ในประวัติ git ไม่ต้องเก็บไว้ที่นี่ รอบนี้เปลี่ยนคำถาม: XPT2046 อยู่คนละบัส SPI กับจอ
// ถ้าชิปไม่มีจริงหรือสายไม่ตรง MISO จะลอย และค่าที่อ่านได้จะนิ่งที่ 0 หรือ 4095 ตลอด
// แม้ตอนแตะ — นั่นก็เป็นคำตอบที่สมบูรณ์ของงานนี้
//
// จอถูกวาดไปด้วยระหว่าง polling touch เพื่อพิสูจน์ว่าสองบัสไม่กวนกัน: ถ้าสี่เหลี่ยม
// หัวใจกลางจอยังกะพริบสม่ำเสมอขณะแตะ แปลว่าแยกกันจริง
#include "driver/gpio.h"
#include "driver/spi_master.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "probe";

// จอ — ยืนยันแล้วจากรอบก่อน
#define PIN_MOSI 13
#define PIN_MISO 12
#define PIN_SCLK 14
#define PIN_CS 15
#define PIN_DC 2
#define PIN_BL 21
#define MADCTL_LANDSCAPE 0x28

// จอสัมผัส — ตามเอกสารชุมชน ยังไม่เคยตรวจกับบอร์ดตัวนี้ นี่คือสิ่งที่กำลังตรวจ
#define PIN_T_SCLK 25
#define PIN_T_MOSI 32
#define PIN_T_MISO 39
#define PIN_T_CS 33
#define PIN_T_IRQ 36

#define LCD_W 320
#define LCD_H 240

static spi_device_handle_t s_lcd;
static spi_device_handle_t s_touch;

// ---------------------------------------------------------------- จอ

static void cs(int level) { gpio_set_level(PIN_CS, level); }
static void dc(int level) { gpio_set_level(PIN_DC, level); }

static void lcd_tx(const uint8_t *data, size_t len)
{
    spi_transaction_t t = {.length = len * 8, .tx_buffer = data};
    ESP_ERROR_CHECK(spi_device_polling_transmit(s_lcd, &t));
}

static void lcd_cmd(uint8_t c)
{
    cs(0);
    dc(0);
    lcd_tx(&c, 1);
    cs(1);
}

static void lcd_cmd_data(uint8_t c, const uint8_t *d, size_t n)
{
    cs(0);
    dc(0);
    lcd_tx(&c, 1);
    if (n) {
        dc(1);
        lcd_tx(d, n);
    }
    cs(1);
}

static void set_window(int x0, int y0, int x1, int y1)
{
    uint8_t ca[4] = {(uint8_t)(x0 >> 8), (uint8_t)x0, (uint8_t)(x1 >> 8), (uint8_t)x1};
    uint8_t ra[4] = {(uint8_t)(y0 >> 8), (uint8_t)y0, (uint8_t)(y1 >> 8), (uint8_t)y1};
    lcd_cmd_data(0x2A, ca, 4);
    lcd_cmd_data(0x2B, ra, 4);
}

static void fill_rect(int x, int y, int w, int h, uint16_t color)
{
    static uint8_t line[LCD_W * 2];
    for (int i = 0; i < w; i++) {
        line[i * 2] = (uint8_t)(color >> 8);
        line[i * 2 + 1] = (uint8_t)color;
    }
    set_window(x, y, x + w - 1, y + h - 1);
    cs(0);
    dc(0);
    uint8_t wr = 0x2C;
    lcd_tx(&wr, 1);
    dc(1);
    for (int row = 0; row < h; row++) {
        lcd_tx(line, (size_t)w * 2);
    }
    cs(1);
}

static void lcd_init(void)
{
    lcd_cmd(0x01);  // SWRESET
    vTaskDelay(pdMS_TO_TICKS(150));
    lcd_cmd(0x11);  // SLPOUT
    vTaskDelay(pdMS_TO_TICKS(150));

    uint8_t colmod = 0x55;  // 16 bit/pixel
    lcd_cmd_data(0x3A, &colmod, 1);
    uint8_t madctl = MADCTL_LANDSCAPE;
    lcd_cmd_data(0x36, &madctl, 1);
    lcd_cmd(0x20);  // INVOFF — แผงนี้ต้องปิด
    lcd_cmd(0x13);  // NORON
    vTaskDelay(pdMS_TO_TICKS(10));
    lcd_cmd(0x29);  // DISPON
    vTaskDelay(pdMS_TO_TICKS(120));
}

// เป้าเล็กและวัดทีละมุม — รอบแรกใช้เป้ากว้าง 48px แล้วแตะได้ทั้งกล่อง ค่าที่มุมเดียวกัน
// จึงกินช่วงกว้างจนบอกไม่ได้ว่าความต่างมาจากตำแหน่งนิ้วหรือจากตัวแผง เป้า 16px แคบพอ
// ที่นิ้วจะลงตรงกลางได้จริง
#define TARGET 16
#define INSET 20  // ระยะจากขอบถึงกึ่งกลางเป้า

typedef struct {
    const char *name;
    int cx, cy;
} corner_t;

static const corner_t CORNERS[4] = {
    {"TL", INSET, INSET},
    {"TR", LCD_W - INSET, INSET},
    {"BL", INSET, LCD_H - INSET},
    {"BR", LCD_W - INSET, LCD_H - INSET},
};

static void draw_target(const corner_t *c, uint16_t color)
{
    fill_rect(c->cx - TARGET / 2, c->cy - TARGET / 2, TARGET, TARGET, color);
}

// เป้าทั้งสี่เป็นเทาเข้ม มุมที่กำลังวัดถูกทับด้วยสีสดทีหลัง — เรียกครั้งเดียวต่อมุม
// ไม่ใช่ทุกเฟรมที่กะพริบ เพราะการถมทั้งจอกินเวลานานกว่าคาบกะพริบเสียอีก
static void draw_stage(void)
{
    fill_rect(0, 0, LCD_W, LCD_H, 0x0000);
    for (int i = 0; i < 4; i++) {
        draw_target(&CORNERS[i], 0x2104);
    }
}

// ------------------------------------------------------------ จอสัมผัส

// control byte ของ XPT2046: S A2 A1 A0 MODE SER/DFR PD1 PD0
// MODE=0 คือผล 12 บิต · SER/DFR=0 คือวัดแบบ differential (นิ่งกว่า) · PD=00 ให้ IRQ ทำงานต่อ
#define T_CMD_X 0xD0   // A=101
#define T_CMD_Y 0x90   // A=001
#define T_CMD_Z1 0xB0  // A=011
#define T_CMD_Z2 0xC0  // A=100

// ส่งคำสั่ง 1 ไบต์แล้วรับ 2 ไบต์ ผล 12 บิตวางชิดซ้ายอยู่ในสองไบต์นั้น
static uint16_t touch_read(uint8_t cmd)
{
    uint8_t tx[3] = {cmd, 0x00, 0x00};
    uint8_t rx[3] = {0};
    spi_transaction_t t = {
        .length = 24,
        .rxlength = 24,
        .tx_buffer = tx,
        .rx_buffer = rx,
    };
    ESP_ERROR_CHECK(spi_device_polling_transmit(s_touch, &t));
    return (uint16_t)((((uint16_t)rx[1] << 8) | rx[2]) >> 3);
}

static uint16_t median_u16(uint16_t *v, int n)
{
    for (int i = 1; i < n; i++) {
        uint16_t k = v[i];
        int j = i - 1;
        while (j >= 0 && v[j] > k) {
            v[j + 1] = v[j];
            j--;
        }
        v[j + 1] = k;
    }
    return v[n / 2];
}

// ค่าเดี่ยวจาก ADC สัมผัสกระโดดเสมอ — เอามัธยฐานของห้าครั้ง
static uint16_t touch_read_median(uint8_t cmd)
{
    uint16_t v[5];
    for (int i = 0; i < 5; i++) {
        v[i] = touch_read(cmd);
    }
    return median_u16(v, 5);
}

// z1 ต่ำแปลว่าไม่ได้แตะ ยิ่งกดแรง z1 ยิ่งสูง เกณฑ์ตั้งหลวมไว้ เพราะเป้าหมายคือ
// "เห็นค่า" ไม่ใช่ "กรองค่า"
#define Z_TOUCH 200
#define SAMPLES 32

// แกนหนึ่งของมุมหนึ่ง: มัธยฐาน กับช่วงที่มันแกว่งตอนนิ้ววางนิ่ง — ช่วงนี้คือ noise
// ของชิป ไม่ใช่การขยับนิ้ว จึงต้องเก็บคู่กับมัธยฐานเสมอ ไม่งั้นอ่านค่าเดี่ยวแล้วเชื่อเกินจริง
typedef struct {
    uint16_t med, lo, hi;
} axis_t;

typedef struct {
    axis_t x, y;
    uint16_t z1;
} corner_result_t;

static axis_t reduce(uint16_t *v, int n)
{
    axis_t a = {.lo = 0xFFFF, .hi = 0};
    for (int i = 0; i < n; i++) {
        if (v[i] < a.lo) a.lo = v[i];
        if (v[i] > a.hi) a.hi = v[i];
    }
    a.med = median_u16(v, n);  // median_u16 เรียงอาเรย์ทิ้ง จึงต้องหา lo/hi ให้เสร็จก่อน
    return a;
}

// รอให้แตะ เก็บ SAMPLES ตัวอย่างติดกัน แล้วรอให้ยกนิ้วก่อนไปมุมถัดไป —
// ถ้าไม่รอยกนิ้ว มุมถัดไปจะกินค่าจากนิ้วที่ยังค้างอยู่ที่มุมเดิม
static void measure_corner(const corner_t *c, corner_result_t *out)
{
    ESP_LOGI(TAG, ">>> แตะเป้าที่กะพริบ มุม %s (จอ %d,%d)", c->name, c->cx, c->cy);
    draw_stage();

    uint16_t xs[SAMPLES], ys[SAMPLES], zs[SAMPLES];
    int n = 0;
    while (n < SAMPLES) {
        // ยังไม่แตะ (หรือยกนิ้วกลางคัน): กะพริบเป้าแล้วเริ่มนับใหม่ตั้งแต่ศูนย์
        int blink = 0;
        while (touch_read(T_CMD_Z1) <= Z_TOUCH) {
            if (n) {
                ESP_LOGW(TAG, "    ยกนิ้วเร็วไป (ได้ %d/%d) เริ่มมุม %s ใหม่", n, SAMPLES, c->name);
                n = 0;
            }
            draw_target(c, (blink++ / 3) % 2 ? 0xFFFF : 0x2104);
            vTaskDelay(pdMS_TO_TICKS(80));
        }
        if (n == 0) {
            draw_target(c, 0x07E0);  // เขียว = กำลังเก็บค่า อย่าเพิ่งยกนิ้ว
        }
        xs[n] = touch_read(T_CMD_X);
        ys[n] = touch_read(T_CMD_Y);
        zs[n] = touch_read(T_CMD_Z1);
        n++;
        vTaskDelay(pdMS_TO_TICKS(20));
    }

    out->x = reduce(xs, SAMPLES);
    out->y = reduce(ys, SAMPLES);
    out->z1 = reduce(zs, SAMPLES).med;

    ESP_LOGI(TAG, "    เก็บครบ ยกนิ้วได้");
    draw_target(c, 0x2104);
    while (touch_read(T_CMD_Z1) > Z_TOUCH) {
        vTaskDelay(pdMS_TO_TICKS(50));
    }
}

void app_main(void)
{
    gpio_config_t io = {
        .pin_bit_mask = (1ULL << PIN_CS) | (1ULL << PIN_DC) | (1ULL << PIN_BL),
        .mode = GPIO_MODE_OUTPUT,
    };
    ESP_ERROR_CHECK(gpio_config(&io));
    cs(1);
    dc(1);
    gpio_set_level(PIN_BL, 1);

    spi_bus_config_t bus = {
        .mosi_io_num = PIN_MOSI,
        .miso_io_num = PIN_MISO,
        .sclk_io_num = PIN_SCLK,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = LCD_W * 2 + 16,
    };
    ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &bus, SPI_DMA_CH_AUTO));

    // CS คุมเองเหมือนรอบก่อน เพราะต้องค้าง low คร่อมทั้งช่วงคำสั่งและช่วงข้อมูล
    spi_device_interface_config_t dev = {
        .clock_speed_hz = 10 * 1000 * 1000,
        .mode = 0,
        .spics_io_num = -1,
        .queue_size = 1,
    };
    ESP_ERROR_CHECK(spi_bus_add_device(SPI2_HOST, &dev, &s_lcd));

    lcd_init();
    fill_rect(0, 0, LCD_W, LCD_H, 0x0000);

    // บัสที่สอง คนละ host กับจอ — ส่วนที่ต้องพิสูจน์ว่าไม่กวนกัน
    spi_bus_config_t tbus = {
        .mosi_io_num = PIN_T_MOSI,
        .miso_io_num = PIN_T_MISO,
        .sclk_io_num = PIN_T_SCLK,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = 32,
    };
    ESP_ERROR_CHECK(spi_bus_initialize(SPI3_HOST, &tbus, SPI_DMA_DISABLED));

    // XPT2046 รับได้ราว 2 MHz ตอนวัด 12 บิต เอา 1 MHz ไว้ก่อน
    // CS ปล่อยให้ไดรเวอร์คุมได้ เพราะทุกธุรกรรมจบในก้อนเดียว
    spi_device_interface_config_t tdev = {
        .clock_speed_hz = 1 * 1000 * 1000,
        .mode = 0,
        .spics_io_num = PIN_T_CS,
        .queue_size = 1,
    };
    ESP_ERROR_CHECK(spi_bus_add_device(SPI3_HOST, &tdev, &s_touch));

    // IRQ ของ XPT2046 เป็น open-drain ต้องมี pull-up ถึงจะอ่านเป็นระดับได้ แต่ GPIO 36
    // เป็นขาอินพุตอย่างเดียวและไม่มี pull-up ภายใน ถ้าบอร์ดไม่มีตัวต้านทานภายนอกค่าจะลอย
    // — IRQ จึงเป็นแค่ข้อมูลประกอบ การชี้ขาดว่ามีชิปไหมดูจากค่า ADC เท่านั้น
    gpio_config_t irq = {
        .pin_bit_mask = 1ULL << PIN_T_IRQ,
        .mode = GPIO_MODE_INPUT,
    };
    ESP_ERROR_CHECK(gpio_config(&irq));

    ESP_LOGI(TAG, "=== ตรวจ XPT2046 (SPI3: CLK %d MOSI %d MISO %d CS %d IRQ %d) ===",
             PIN_T_SCLK, PIN_T_MOSI, PIN_T_MISO, PIN_T_CS, PIN_T_IRQ);
    ESP_LOGI(TAG, "แตะเป้าที่กะพริบทีละมุม ค้างไว้จนเป้าเปลี่ยนเป็นเทา (เก็บครบ) แล้วยกนิ้ว");
    ESP_LOGI(TAG, "ถ้า x/y นิ่งที่ 0 หรือ 4095 ตลอดแม้ตอนแตะ = ไม่มีชิปหรือขาไม่ตรง");

    // ค่าตอนไม่แตะ ใช้เป็นเส้นฐาน ก่อนจะเชื่ออะไรก็ตามที่โผล่มาตอนแตะ
    ESP_LOGI(TAG, "--- idle baseline ---");
    for (int i = 0; i < 5; i++) {
        uint16_t x = touch_read(T_CMD_X);
        uint16_t y = touch_read(T_CMD_Y);
        uint16_t z1 = touch_read(T_CMD_Z1);
        uint16_t z2 = touch_read(T_CMD_Z2);
        ESP_LOGI(TAG, "idle  x=%4u y=%4u z1=%4u z2=%4u irq=%d", x, y, z1, z2,
                 gpio_get_level(PIN_T_IRQ));
        vTaskDelay(pdMS_TO_TICKS(200));
    }

    // วัดทีละมุม จอเป็นตัวบอกว่าตอนนี้ต้องแตะมุมไหน แล้วผลออกมาติดป้ายมุมมาด้วย —
    // รอบแรกปล่อยให้แตะอิสระแล้วต้องเดาจาก timestamp ว่าค่าไหนคือมุมไหน ซึ่งเดาผิดได้จริง
    corner_result_t result[4];
    for (int i = 0; i < 4; i++) {
        measure_corner(&CORNERS[i], &result[i]);
    }

    ESP_LOGW(TAG, "=== สรุป (มัธยฐาน [ต่ำสุด-สูงสุด] ต่อมุม) ===");
    for (int i = 0; i < 4; i++) {
        const corner_result_t *r = &result[i];
        ESP_LOGW(TAG, "%s  จอ(%3d,%3d)  x=%4u [%4u-%4u]  y=%4u [%4u-%4u]  z1=%4u",
                 CORNERS[i].name, CORNERS[i].cx, CORNERS[i].cy, r->x.med, r->x.lo, r->x.hi,
                 r->y.med, r->y.lo, r->y.hi, r->z1);
    }

    // เทียบคู่ที่ต่างกันแค่แกนเดียว แล้วพิมพ์ทั้งสองค่า ADC ของคู่นั้น — จะได้เห็นเองว่า
    // แกนไหนของชิปตรงกับแกนไหนของจอ ไม่ใช่สมมติว่า x ของชิปคือ x ของจอ
    // (ชิปสัมผัสไม่รู้จัก MADCTL แกนมันจึงเป็นแกนของแผงตอนตั้ง ไม่ใช่ตอนหมุนแล้ว)
    ESP_LOGW(TAG, "ซ้าย->ขวา (%d px): ADC x %+d · ADC y %+d", LCD_W - 2 * INSET,
             (int)result[1].x.med - (int)result[0].x.med,
             (int)result[1].y.med - (int)result[0].y.med);
    ESP_LOGW(TAG, "บน->ล่าง (%d px): ADC x %+d · ADC y %+d", LCD_H - 2 * INSET,
             (int)result[2].x.med - (int)result[0].x.med,
             (int)result[2].y.med - (int)result[0].y.med);

    // วาดต่อไปเรื่อยๆ พร้อม polling สัมผัส: ถ้าสี่เหลี่ยมกลางจอกะพริบสม่ำเสมอขณะแตะ
    // แปลว่าสองบัสไม่กวนกัน
    fill_rect(0, 0, LCD_W, LCD_H, 0x0000);
    ESP_LOGI(TAG, "--- วัดครบแล้ว แตะต่อได้ตามใจ (ดูว่าสี่เหลี่ยมกลางจอสะดุดไหม) ---");
    for (int tick = 0;; tick++) {
        uint16_t z1 = touch_read(T_CMD_Z1);
        if (z1 > Z_TOUCH) {
            ESP_LOGW(TAG, "TOUCH x=%4u y=%4u z1=%4u irq=%d", touch_read_median(T_CMD_X),
                     touch_read_median(T_CMD_Y), z1, gpio_get_level(PIN_T_IRQ));
        }
        fill_rect(LCD_W / 2 - 8, LCD_H / 2 - 8, 16, 16, (tick / 5) % 2 ? 0xFFFF : 0x0000);
        vTaskDelay(pdMS_TO_TICKS(50));
    }
}
