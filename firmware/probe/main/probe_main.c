// ตรวจว่าจอบนบอร์ด CYD ตัวนี้เป็น ILI9341 หรือ ST7789
//
// สองวิธีที่ไม่ขึ้นต่อกัน เผื่อวิธีหนึ่งใช้ไม่ได้:
//   1. อ่าน ID register ผ่าน MISO  — เชื่อถือได้ แต่ CYD บางล็อตไม่ต่อขา MISO ของจอ
//   2. ถมจอด้วยสีแดงล้วน          — ST7789 ต้องเปิด inversion ถึงจะสีถูก
//                                    ถ้าเห็นฟ้าอมเขียวแทนแดง = ST7789
#include <string.h>

#include "driver/gpio.h"
#include "driver/spi_master.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "probe";

// ขาตามเอกสารชุมชนของ ESP32-2432S028R — ส่วนหนึ่งของสิ่งที่กำลังตรวจสอบ
#define PIN_MOSI 13
#define PIN_MISO 12
#define PIN_SCLK 14
#define PIN_CS 15
#define PIN_DC 2
#define PIN_BL 21

#define LCD_W 240
#define LCD_H 320

static spi_device_handle_t s_spi;

static void cs(int level) { gpio_set_level(PIN_CS, level); }
static void dc(int level) { gpio_set_level(PIN_DC, level); }

static void spi_tx(const uint8_t *data, size_t len)
{
    spi_transaction_t t = {.length = len * 8, .tx_buffer = data};
    ESP_ERROR_CHECK(spi_device_polling_transmit(s_spi, &t));
}

static void spi_rx(uint8_t *data, size_t len)
{
    memset(data, 0, len);
    spi_transaction_t t = {.length = len * 8, .rxlength = len * 8, .rx_buffer = data};
    ESP_ERROR_CHECK(spi_device_polling_transmit(s_spi, &t));
}

static void lcd_cmd(uint8_t c)
{
    cs(0);
    dc(0);
    spi_tx(&c, 1);
    cs(1);
}

static void lcd_cmd_data(uint8_t c, const uint8_t *d, size_t n)
{
    cs(0);
    dc(0);
    spi_tx(&c, 1);
    if (n) {
        dc(1);
        spi_tx(d, n);
    }
    cs(1);
}

// อ่าน n ไบต์กลับมาจากคำสั่ง c โดย CS ค้าง low ตลอด
static void lcd_read(uint8_t c, uint8_t *buf, size_t n)
{
    cs(0);
    dc(0);
    spi_tx(&c, 1);
    dc(1);
    spi_rx(buf, n);
    cs(1);
}

// ตัวควบคุมพวกนี้ทวนหนึ่ง dummy clock ก่อนข้อมูลจริง ผลคือค่าที่อ่านได้
// เลื่อนไปหนึ่งบิต — พิมพ์ทั้งแบบดิบและแบบเลื่อนแล้ว จะได้ไม่ต้องเดา
static void shift_left_1(const uint8_t *in, uint8_t *out, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        uint8_t next = (i + 1 < n) ? in[i + 1] : 0;
        out[i] = (uint8_t)((in[i] << 1) | (next >> 7));
    }
}

static void dump(const char *name, uint8_t reg, size_t n)
{
    uint8_t raw[8] = {0}, sh[8] = {0};
    lcd_read(reg, raw, n);
    shift_left_1(raw, sh, n);
    char a[40] = {0}, b[40] = {0};
    for (size_t i = 0; i < n; i++) {
        sprintf(a + i * 3, "%02X ", raw[i]);
        sprintf(b + i * 3, "%02X ", sh[i]);
    }
    ESP_LOGI(TAG, "%-8s (0x%02X)  raw: %s |  shifted: %s", name, reg, a, b);
}

// init ชุดกลางที่ตัวควบคุมทั้งสองตัวรับได้ ตั้งใจไม่เปิด inversion
// เพื่อให้ความต่างเรื่องสีเป็นตัวชี้ว่าเป็นชิปไหน
static void lcd_init_common(void)
{
    lcd_cmd(0x01);  // SWRESET
    vTaskDelay(pdMS_TO_TICKS(150));
    lcd_cmd(0x11);  // SLPOUT
    vTaskDelay(pdMS_TO_TICKS(150));

    uint8_t colmod = 0x55;  // 16 bit/pixel
    lcd_cmd_data(0x3A, &colmod, 1);
    uint8_t madctl = 0x00;
    lcd_cmd_data(0x36, &madctl, 1);
    lcd_cmd(0x20);  // INVOFF
    lcd_cmd(0x13);  // NORON
    vTaskDelay(pdMS_TO_TICKS(10));
    lcd_cmd(0x29);  // DISPON
    vTaskDelay(pdMS_TO_TICKS(120));
}

static void set_window(int w, int h)
{
    uint8_t ca[4] = {0, 0, (uint8_t)((w - 1) >> 8), (uint8_t)((w - 1) & 0xFF)};
    uint8_t ra[4] = {0, 0, (uint8_t)((h - 1) >> 8), (uint8_t)((h - 1) & 0xFF)};
    lcd_cmd_data(0x2A, ca, 4);
    lcd_cmd_data(0x2B, ra, 4);
}

static void fill(uint16_t color)
{
    set_window(LCD_W, LCD_H);
    static uint8_t line[LCD_W * 2];
    for (int i = 0; i < LCD_W; i++) {
        line[i * 2] = (uint8_t)(color >> 8);
        line[i * 2 + 1] = (uint8_t)(color & 0xFF);
    }
    cs(0);
    dc(0);
    uint8_t wr = 0x2C;
    spi_tx(&wr, 1);
    dc(1);
    for (int y = 0; y < LCD_H; y++) {
        spi_tx(line, sizeof(line));
    }
    cs(1);
}

// ลายทดสอบแนวนอน 320x240 — บอกได้ทั้งการหมุนและลำดับสีในภาพเดียว
// แถบเรียงซ้ายไปขวา: แดง เขียว น้ำเงิน ขาว
// สี่เหลี่ยมขาวเล็กอยู่มุมบนซ้ายเท่านั้น ใช้ชี้ว่า origin อยู่มุมไหนจริง
#define LAND_W 320
#define LAND_H 240

static void landscape_test(void)
{
    set_window(LAND_W, LAND_H);
    static uint8_t line[LAND_W * 2];
    const uint16_t bars[4] = {0xF800, 0x07E0, 0x001F, 0xFFFF};

    cs(0);
    dc(0);
    uint8_t wr = 0x2C;
    spi_tx(&wr, 1);
    dc(1);
    for (int y = 0; y < LAND_H; y++) {
        for (int x = 0; x < LAND_W; x++) {
            uint16_t c = bars[x / (LAND_W / 4)];
            if (x < 40 && y < 24) {
                c = 0xFFFF;  // เครื่องหมายมุมบนซ้าย
            } else if (x < 44 && y < 28) {
                c = 0x0000;  // ขอบดำรอบเครื่องหมาย ให้เห็นชัดบนแถบแดง
            }
            line[x * 2] = (uint8_t)(c >> 8);
            line[x * 2 + 1] = (uint8_t)(c & 0xFF);
        }
        spi_tx(line, sizeof(line));
    }
    cs(1);
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

    // 1 MHz — การอ่าน register ต้องช้า ส่วน CS คุมเองเพราะต้องค้าง low
    // ตลอดทั้งช่วงส่งคำสั่งและช่วงอ่านข้อมูล
    spi_device_interface_config_t dev = {
        .clock_speed_hz = 1 * 1000 * 1000,
        .mode = 0,
        .spics_io_num = -1,
        .queue_size = 1,
    };
    ESP_ERROR_CHECK(spi_bus_add_device(SPI2_HOST, &dev, &s_spi));

    lcd_cmd(0x01);
    vTaskDelay(pdMS_TO_TICKS(150));
    lcd_cmd(0x11);
    vTaskDelay(pdMS_TO_TICKS(150));

    // การอ่านหลายไบต์ (0x04, 0xD3) คืนศูนย์บนจอตัวนี้ แต่การอ่านไบต์เดียวใช้ได้
    // โชคดีที่ ID ของทั้งสองชิปอ่านทีละไบต์ได้ผ่าน 0xDA/0xDB/0xDC
    ESP_LOGI(TAG, "=== อ่าน ID ทีละไบต์ ===");
    ESP_LOGI(TAG, "ILI9341 -> 00 93 41   |   ST7789 -> 85 85 52");
    dump("ID1", 0xDA, 2);
    dump("ID2", 0xDB, 2);
    dump("ID3", 0xDC, 2);
    dump("RDDPM", 0x0A, 2);

    uint8_t id[3] = {0};
    for (int i = 0; i < 3; i++) {
        uint8_t b[2] = {0};
        lcd_read((uint8_t)(0xDA + i), b, 2);
        id[i] = b[0];
    }
    if (id[1] == 0x93 && id[2] == 0x41) {
        ESP_LOGW(TAG, ">>> ILI9341 <<<");
    } else if (id[0] == 0x85 && id[1] == 0x85 && id[2] == 0x52) {
        ESP_LOGW(TAG, ">>> ST7789 <<<");
    } else {
        ESP_LOGW(TAG, ">>> อ่าน ID ไม่ได้ (%02X %02X %02X) ใช้ผลจากสายตาแทน <<<",
                 id[0], id[1], id[2]);
    }

    // ยืนยันแล้วจากรอบก่อน: แผงเป็น BGR และ inversion ต้องปิด
    // รอบนี้หาค่า MADCTL ที่ให้แนวนอน 320x240 โดยหมุนไปเรื่อยๆ ทุก 6 วินาที
    lcd_init_common();
    static const uint8_t rot[4] = {
        0x68,  // MV | MX | BGR
        0xA8,  // MV | MY | BGR
        0x28,  // MV | BGR
        0xE8,  // MV | MX | MY | BGR
    };
    ESP_LOGI(TAG, "=== หาค่า MADCTL สำหรับแนวนอน 320x240 ===");
    ESP_LOGI(TAG, "แถบซ้าย->ขวา ต้องเป็น แดง เขียว น้ำเงิน ขาว");
    ESP_LOGI(TAG, "และสี่เหลี่ยมขาวขอบดำต้องอยู่ 'มุมบนซ้าย' เมื่อวางจอแนวนอน");
    for (int i = 0;; i = (i + 1) % 4) {
        lcd_cmd_data(0x36, &rot[i], 1);
        landscape_test();
        ESP_LOGW(TAG, "MADCTL = 0x%02X  (แบบที่ %d จาก 4)", rot[i], i + 1);
        vTaskDelay(pdMS_TO_TICKS(6000));
    }

    while (1) {
        vTaskDelay(pdMS_TO_TICKS(5000));
    }
}
