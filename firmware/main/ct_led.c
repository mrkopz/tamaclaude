#include "ct_led.h"

#include "driver/gpio.h"

// ขาตามเอกสารชุมชน ยังไม่ได้วัดจากบอร์ดจริง (docs/hardware.md)
#define PIN_R 4
#define PIN_G 16
#define PIN_B 17

#define FLASH_STEP_MS 120
#define FLASH_STEPS 6

static int s_step = FLASH_STEPS;  // เริ่มที่จบแล้ว = ไฟดับ
static int s_elapsed;

// active low: 0 = ติด
static void set_rgb(bool r, bool g, bool b)
{
    gpio_set_level(PIN_R, r ? 0 : 1);
    gpio_set_level(PIN_G, g ? 0 : 1);
    gpio_set_level(PIN_B, b ? 0 : 1);
}

void ct_led_init(void)
{
    gpio_config_t io = {
        .pin_bit_mask = (1ULL << PIN_R) | (1ULL << PIN_G) | (1ULL << PIN_B),
        .mode = GPIO_MODE_OUTPUT,
    };
    gpio_config(&io);
    set_rgb(false, false, false);
}

void ct_led_flash(void)
{
    s_step = 0;
    s_elapsed = 0;
}

void ct_led_tick(int elapsed_ms)
{
    if (s_step >= FLASH_STEPS) return;
    s_elapsed += elapsed_ms;
    while (s_elapsed >= FLASH_STEP_MS && s_step < FLASH_STEPS) {
        s_elapsed -= FLASH_STEP_MS;
        s_step++;
    }
    if (s_step >= FLASH_STEPS) {
        set_rgb(false, false, false);
        return;
    }
    // ไล่สีไปเรื่อยๆ แทนการกะพริบสีเดียว — สังเกตเห็นจากหางตาง่ายกว่า
    switch (s_step % 3) {
        case 0: set_rgb(true, false, false); break;
        case 1: set_rgb(false, false, true); break;
        default: set_rgb(true, true, false); break;
    }
}
