// tamaclaude — จอแสดงสถานะ Claude Code บนบอร์ด CYD
//
// เส้นทางข้อมูล: BLE write -> staging (mutex) -> ลูปหลัก -> LVGL -> SPI -> จอ
// LVGL ไม่ปลอดภัยกับหลายเธรด ทุกการแตะ UI จึงเกิดในลูปหลักที่เดียว
#include <string.h>

#include "ct_ble.h"
#include "ct_lcd.h"
#include "ct_led.h"
#include "ct_mascot.h"
#include "ct_model.h"
#include "ct_ui.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "layout.h"
#include "lvgl.h"
#include "nvs_flash.h"

static const char *TAG = "main";

// บัฟเฟอร์วาดของ LVGL: 1/10 ของจอสองก้อน (~15KB) ไม่ใช่ framebuffer เต็ม 150KB
// บอร์ดนี้ไม่มี PSRAM จึงไม่มีทางเลือกอื่นอยู่แล้ว
#define DRAW_LINES 24
#define DRAW_BUF_PX (CT_SCREEN_WIDTH * DRAW_LINES)

static lv_color_t *s_buf1, *s_buf2;
static SemaphoreHandle_t s_lock;

// ของที่ BLE ฝากไว้ให้ลูปหลักหยิบไปใช้
static ct_snapshot_t s_pending;
static bool s_has_pending;
static bool s_link;
static bool s_link_changed = true;
static int s_pending_backlight = -1;

static uint32_t millis_cb(void) { return (uint32_t)(esp_timer_get_time() / 1000); }

static void flush_cb(lv_display_t *disp, const lv_area_t *area, uint8_t *px_map)
{
    size_t px = (size_t)(area->x2 - area->x1 + 1) * (area->y2 - area->y1 + 1);
    // LVGL เก็บ RGB565 แบบ little-endian ส่วนจอกินแบบ big-endian
    lv_draw_sw_rgb565_swap(px_map, px);
    ct_lcd_blit(area->x1, area->y1, area->x2, area->y2, px_map, px * 2);
    lv_display_flush_ready(disp);
}

// --- callback จาก NimBLE (คนละเธรดกับ LVGL) ---------------------------------
static void on_state(const char *json, int len)
{
    ct_snapshot_t parsed;
    if (!ct_model_parse(json, len, &parsed)) {
        ESP_LOGW(TAG, "snapshot was not valid json");
        return;
    }
    ESP_LOGI(TAG, "snapshot %s: %d sessions, %d cards", parsed.clock, parsed.session_count,
             parsed.card_count);
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_pending = parsed;
    s_has_pending = true;
    xSemaphoreGive(s_lock);
}

static void on_config(const char *json, int len)
{
    // คอนฟิกมีค่าเดียวใน v1: {"b":0..100}
    const char *p = strstr(json, "\"b\"");
    if (!p) return;
    p = strchr(p, ':');
    if (!p) return;
    int value = atoi(p + 1);
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_pending_backlight = value;
    xSemaphoreGive(s_lock);
}

static void on_link(bool connected)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_link = connected;
    s_link_changed = true;
    xSemaphoreGive(s_lock);
}

// --- ลูปหลัก -----------------------------------------------------------------
static bool has_alert(const ct_snapshot_t *s)
{
    for (int i = 0; i < s->card_count; i++) {
        if (s->cards[i].kind == CT_CARD_ALERT) return true;
    }
    return false;
}

static void apply_pending(void)
{
    ct_snapshot_t snap;
    bool got_snapshot = false, link = false, link_changed = false;
    int backlight = -1;

    xSemaphoreTake(s_lock, portMAX_DELAY);
    if (s_has_pending) {
        snap = s_pending;
        s_has_pending = false;
        got_snapshot = true;
    }
    link = s_link;
    link_changed = s_link_changed;
    s_link_changed = false;
    backlight = s_pending_backlight;
    s_pending_backlight = -1;
    xSemaphoreGive(s_lock);

    if (link_changed) ct_ui_set_connected(link);
    if (got_snapshot) {
        static bool had_alert = false;
        bool alert = has_alert(&snap);
        // กะพริบเฉพาะตอนการเตือน *เกิดใหม่* ไม่ใช่ทุก snapshot ที่ยังมีการเตือนค้างอยู่
        if (alert && !had_alert) ct_led_flash();
        had_alert = alert;
        ct_ui_set_snapshot(&snap);
    }
    if (backlight >= 0) ct_lcd_set_backlight(backlight);
}

void app_main(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    s_lock = xSemaphoreCreateMutex();
    ct_mascot_init();
    ct_lcd_init();
    ct_led_init();

    lv_init();
    lv_tick_set_cb(millis_cb);

    s_buf1 = heap_caps_malloc(DRAW_BUF_PX * sizeof(lv_color_t), MALLOC_CAP_DMA);
    s_buf2 = heap_caps_malloc(DRAW_BUF_PX * sizeof(lv_color_t), MALLOC_CAP_DMA);
    assert(s_buf1 && s_buf2);

    lv_display_t *disp = lv_display_create(CT_SCREEN_WIDTH, CT_SCREEN_HEIGHT);
    lv_display_set_color_format(disp, LV_COLOR_FORMAT_RGB565);
    lv_display_set_flush_cb(disp, flush_cb);
    lv_display_set_buffers(disp, s_buf1, s_buf2, DRAW_BUF_PX * sizeof(lv_color_t),
                           LV_DISPLAY_RENDER_MODE_PARTIAL);

    ct_ui_init();
    ct_ui_set_connected(false);

    ct_ble_cbs_t cbs = {
        .on_state = on_state,
        .on_config = on_config,
        .on_link = on_link,
    };
    ct_ble_init(&cbs);
    ESP_LOGI(TAG, "ready");

    const int step_ms = 10;
    int since_frame = 0;
    while (1) {
        apply_pending();
        since_frame += step_ms;
        if (since_frame >= 60) {  // ~16 เฟรมต่อวินาที พอสำหรับอนิเมชันบล็อกสี่เหลี่ยม
            ct_ui_tick();
            ct_led_tick(since_frame);
            since_frame = 0;
        }
        lv_timer_handler();
        vTaskDelay(pdMS_TO_TICKS(step_ms));
    }
}
