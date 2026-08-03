#include "ct_weather_ui.h"

#include <stdio.h>

#include "ct_color.h"
#include "ct_fonts.h"
#include "ct_mascot.h"
#include "ct_paint.h"
#include "ct_rects.h"
#include "layout.h"

// หนึ่งลูปอนิเมชันยาวเท่าไร (ms) — ค่าเดียวกับหน้ามาสคอต
#define LOOP_MS 1000

static const ct_weather_t *s_frame;
static const bool *s_has_frame;
static const ct_snapshot_t *s_mascot;
static bool s_connected;

static lv_obj_t *s_place;
static lv_obj_t *s_temp;
static lv_obj_t *s_hilo;
static lv_obj_t *s_age;
static lv_obj_t *s_empty;      // บรรทัดของสภาพ "ยังไม่เคยได้ข้อมูล"
static lv_obj_t *s_empty_sub;
static lv_obj_t *s_icon;   // ผืนวาดสัญลักษณ์อากาศ
static lv_obj_t *s_mini;   // ผืนวาดมาสคอตจิ๋ว

static float s_phase;
static int s_cycle;

static void paint_connected(void);

// --- สัญลักษณ์อากาศ ------------------------------------------------------------
// รหัส WMO มีหลายสิบค่า แต่จอ 2.8 นิ้วที่มองจากอีกฝั่งห้องแยกได้จริงราวหกกลุ่ม
// การวาดหมอกกับหมอกน้ำแข็งคนละรูปคือรายละเอียดที่ไม่มีใครอ่านออก
// ต้องตรงกับ bucket() ใน tools/gen/weather.py
typedef enum {
    ICON_CLEAR = 0,
    ICON_CLOUD,
    ICON_FOG,
    ICON_RAIN,
    ICON_SNOW,
    ICON_STORM,
} icon_kind_t;

static icon_kind_t bucket(int code)
{
    if (code >= 95) return ICON_STORM;
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) return ICON_SNOW;
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return ICON_RAIN;
    if (code == 45 || code == 48) return ICON_FOG;
    if (code >= 2) return ICON_CLOUD;
    return ICON_CLEAR;  // 0, 1 = โล่ง/เกือบโล่ง
}

// ก้อนเมฆ — สามชิ้นซ้อนกันในตาราง 10x10 unit ใช้ร่วมกันสี่กลุ่ม
static void add_cloud(ct_rects_t *out, uint16_t color)
{
    ct_rects_add_round(out, 1.0f, 3.6f, 8.0f, 2.8f, color, 1.4f);
    ct_rects_add_round(out, 2.4f, 2.0f, 3.4f, 3.0f, color, 1.5f);
    ct_rects_add_round(out, 5.0f, 2.6f, 3.0f, 2.6f, color, 1.3f);
}

// สัญลักษณ์หนึ่งชุดในตาราง 10x10 unit — พิกัด unit เหมือน asset อื่นทั้งโปรเจกต์
// ต้องตรงกับ icon() ใน tools/gen/weather.py
static void build_icon(ct_rects_t *out, int code, bool connected)
{
    ct_rects_reset(out);
    // หลุดลิงก์แล้วสัญลักษณ์เป็นเทา เหมือนมาสคอตที่หลุด — ตัวเลขที่ค้างอยู่ยังอ่านได้
    // แต่ต้องไม่อ่านว่าเป็นตอนนี้
    uint16_t cloud = connected ? CT_COL_CLOUD_DAY : CT_COL_GRAY;
    uint16_t sun = connected ? CT_COL_SUN : CT_COL_GRAY;
    uint16_t wet = connected ? CT_COL_STEEL : CT_COL_GRAY_DARK;
    uint16_t bolt = connected ? CT_COL_ACCENT : CT_COL_GRAY_DARK;

    switch (bucket(code)) {
        case ICON_CLEAR:
            // ดวงกลมกับรังสีสี่ทิศ — ไม่ใช่แปดทิศ เพราะที่ 50px รังสีทแยงกลืนกับดวง
            ct_rects_add_round(out, 2.5f, 2.5f, 5.0f, 5.0f, sun, 2.5f);
            ct_rects_add(out, 4.6f, 0.2f, 0.8f, 1.6f, sun);
            ct_rects_add(out, 4.6f, 8.2f, 0.8f, 1.6f, sun);
            ct_rects_add(out, 0.2f, 4.6f, 1.6f, 0.8f, sun);
            ct_rects_add(out, 8.2f, 4.6f, 1.6f, 0.8f, sun);
            break;
        case ICON_CLOUD:
            // เมฆบังดวงบางส่วน — เมฆล้วนแยกไม่ออกจากหมอกที่ระยะโต๊ะ
            ct_rects_add_round(out, 5.6f, 0.2f, 3.6f, 3.6f, sun, 1.8f);
            add_cloud(out, cloud);
            break;
        case ICON_FOG:
            // สามขีดนอน ไม่มีเมฆ — หมอกคือสิ่งที่ *ไม่* มีรูปร่าง
            for (int i = 0; i < 3; i++) {
                ct_rects_add_round(out, 1.0f + (i % 2) * 0.8f, 2.6f + i * 2.2f, 7.4f, 1.0f,
                                   cloud, 0.5f);
            }
            break;
        case ICON_RAIN:
            add_cloud(out, cloud);
            for (int i = 0; i < 3; i++) {
                ct_rects_add_round(out, 2.2f + i * 2.4f, 7.0f, 0.9f, 2.4f, wet, 0.45f);
            }
            break;
        case ICON_SNOW:
            add_cloud(out, cloud);
            for (int i = 0; i < 3; i++) {
                ct_rects_add_round(out, 2.2f + i * 2.4f, 7.4f, 1.4f, 1.4f,
                                   connected ? CT_COL_TEXT : CT_COL_GRAY_DARK, 0.7f);
            }
            break;
        case ICON_STORM:
            add_cloud(out, cloud);
            // สายฟ้าเป็นสองชิ้นเยื้องกัน — ชิ้นเดียวอ่านเป็นเสาไฟ
            ct_rects_add(out, 4.6f, 6.8f, 1.6f, 1.8f, bolt);
            ct_rects_add(out, 3.8f, 8.0f, 1.6f, 1.8f, bolt);
            break;
    }
}

static void icon_draw_cb(lv_event_t *e)
{
    lv_obj_t *obj = lv_event_get_target_obj(e);
    lv_layer_t *layer = lv_event_get_layer(e);
    lv_area_t coords;
    lv_obj_get_coords(obj, &coords);

    ct_rects_t rects;
    // ยังไม่เคยได้ข้อมูล = เมฆเทาก้อนเดียว ไม่ใช่ผืนว่าง — หน้าเปล่าอ่านเป็นอุปกรณ์พัง
    build_icon(&rects, *s_has_frame ? s_frame->code : 3, *s_has_frame && s_connected);
    ct_paint_rects(layer, &rects, coords.x1, coords.y1, CT_WEATHER_ICON_PX);
}

// --- มาสคอตจิ๋ว ----------------------------------------------------------------
// rect list ชุดเดิมที่ย่อลงผ่าน ct_rects_scale_from() ไม่มีอาร์ตใหม่ ไม่มีท้องฟ้า
// ไม่มี prop ที่ต้องเว้นที่ให้
//
// ท่าของแต่ละ session ถูกหน่วงด้วย Timings.minPose ที่ daemon มาแล้ว ที่นี่จึงไม่หน่วงซ้ำ
// สิ่งที่กระโดดได้ทันทีคือตอน session *คนละตัว* ขึ้นมาเป็นตัวนำ ซึ่งเป็นข้อยกเว้นเดียวกับ
// ที่ daemon มีอยู่แล้ว (priority สูงกว่าแทรกได้ทันที) — การรออนุญาตที่รอห้าวินาทีก่อน
// จะขึ้นจอคือการเตือนที่มาช้าโดยไม่มีเหตุผล
static void mini_draw_cb(lv_event_t *e)
{
    // ไม่มี Mac = ไม่มีมาสคอต ซึ่งต่างจากมาสคอตที่หลับ (= ไม่มี session)
    // สองสถานะนี้ต้องแยกออกจากกัน ไม่งั้นจอเงียบสองแบบดูเหมือนกัน
    if (!s_connected) return;

    lv_obj_t *obj = lv_event_get_target_obj(e);
    lv_layer_t *layer = lv_event_get_layer(e);
    lv_area_t coords;
    lv_obj_get_coords(obj, &coords);

    ct_rects_t rects;
    ct_mascot_build_centered(&rects, ct_model_lead_state(s_mascot), s_phase, true, s_cycle);
    const float scale = CT_WEATHER_MINI_UNIT_PX / CT_SLOTS_UNIT_PX;
    ct_rects_scale_from(&rects, 0, scale, scale, 0.0f, 0.0f);

    // ฝ่าเท้าเกาะขอบล่างของผืน ไม่ใช่ขอบบน — ตัวที่กระโดดต้องกระโดดขึ้น
    float px = CT_SLOTS_UNIT_PX;
    float oy = coords.y2 + 1 - CT_BOX_Y1 * scale * px;
    float ox = coords.x1 - CT_BOX_X0 * scale * px;
    ct_paint_rects(layer, &rects, ox, oy, px);
}

// --- ตัวช่วยสร้าง widget --------------------------------------------------------
static lv_obj_t *label(lv_obj_t *parent, const lv_font_t *font, uint16_t color, int x, int y)
{
    lv_obj_t *l = lv_label_create(parent);
    lv_obj_set_style_text_font(l, font, 0);
    lv_obj_set_style_text_color(l, ct_color(color), 0);
    lv_label_set_text(l, "");
    lv_obj_set_pos(l, x, y);
    return l;
}

void ct_weather_ui_init(lv_obj_t *parent, const ct_weather_t *frame, const bool *has_frame,
                        const ct_snapshot_t *mascot)
{
    s_frame = frame;
    s_has_frame = has_frame;
    s_mascot = mascot;

    s_place = label(parent, ct_font_text_14(), CT_COL_TEXT, CT_WEATHER_PLACE_X,
                    CT_WEATHER_PLACE_Y);
    // ชื่อเมืองยาวเท่าไรก็ได้ (บริการภายนอกเป็นคนตั้ง) แต่พื้นที่มีเท่าเดิม — ตัดด้วยจุด
    // ไม่ใช่ปล่อยให้ล้นไปทับสัญลักษณ์
    lv_obj_set_width(s_place, CT_WEATHER_ICON_X - CT_WEATHER_PLACE_X - 8);
    lv_label_set_long_mode(s_place, LV_LABEL_LONG_DOT);

    s_temp = label(parent, &lv_font_montserrat_48, CT_COL_TEXT, CT_WEATHER_TEMP_X,
                   CT_WEATHER_TEMP_Y);
    _Static_assert(CT_WEATHER_TEMP_FONT == 48, "layout.toml and the font here must agree");
    s_hilo = label(parent, ct_font_text_14(), CT_COL_TEXT_DIM, CT_WEATHER_HILO_X,
                   CT_WEATHER_HILO_Y);
    s_age = label(parent, ct_font_text_12(), CT_COL_TEXT_DIM, CT_WEATHER_AGE_X,
                  CT_WEATHER_AGE_Y);

    s_empty = label(parent, ct_font_text_14(), CT_COL_TEXT, CT_WEATHER_TEMP_X,
                    CT_WEATHER_EMPTY_Y);
    lv_label_set_text(s_empty, "No weather yet");
    s_empty_sub = label(parent, ct_font_text_12(), CT_COL_TEXT_DIM, CT_WEATHER_TEMP_X,
                        CT_WEATHER_EMPTY_SUB_Y);
    lv_label_set_text(s_empty_sub, "the mac has not sent this page");

    s_icon = lv_obj_create(parent);
    lv_obj_remove_style_all(s_icon);
    lv_obj_set_size(s_icon, CT_WEATHER_ICON_GRID * CT_WEATHER_ICON_PX,
                    CT_WEATHER_ICON_GRID * CT_WEATHER_ICON_PX);
    lv_obj_set_pos(s_icon, CT_WEATHER_ICON_X, CT_WEATHER_ICON_Y);
    lv_obj_remove_flag(s_icon, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(s_icon, icon_draw_cb, LV_EVENT_DRAW_MAIN, NULL);

    int mini_w = (int)((CT_BOX_X1 - CT_BOX_X0) * CT_WEATHER_MINI_UNIT_PX) + 1;
    int mini_h = (int)((CT_BOX_Y1 - CT_BOX_Y0) * CT_WEATHER_MINI_UNIT_PX) + 1;
    s_mini = lv_obj_create(parent);
    lv_obj_remove_style_all(s_mini);
    lv_obj_set_size(s_mini, mini_w, mini_h);
    lv_obj_set_pos(s_mini, CT_SCREEN_WIDTH - CT_WEATHER_MINI_RIGHT - mini_w,
                   CT_WEATHER_MINI_BOTTOM_Y - mini_h);
    lv_obj_remove_flag(s_mini, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(s_mini, mini_draw_cb, LV_EVENT_DRAW_MAIN, NULL);

    paint_connected();
    ct_weather_ui_redraw();
}

// อายุข้อมูล -> ข้อความสั้นที่สุดที่ยังบอกได้ว่าควรเชื่อแค่ไหน
// ต้องตรงกับ age_text() ใน tools/gen/weather.py
static void age_text(char *out, size_t cap, int secs)
{
    if (secs < 60) {
        snprintf(out, cap, "updated just now");
    } else if (secs < 3600) {
        snprintf(out, cap, "updated %dm ago", secs / 60);
    } else if (secs < 86400) {
        snprintf(out, cap, "updated %dh %02dm ago", secs / 3600, (secs % 3600) / 60);
    } else {
        snprintf(out, cap, "updated %dd ago", secs / 86400);
    }
}

void ct_weather_ui_redraw(void)
{
    bool have = *s_has_frame;
    // สองสภาพนี้ไม่เคยอยู่ด้วยกัน — หน้าที่ยังไม่เคยได้ข้อมูลไม่มีตัวเลขให้แสดงสักตัว
    if (have) {
        lv_obj_remove_flag(s_temp, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s_hilo, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s_place, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_empty, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_empty_sub, LV_OBJ_FLAG_HIDDEN);

        lv_label_set_text(s_place, s_frame->place);
        // ไม่มีสัญลักษณ์องศาในฟอนต์บนบอร์ด และการประดิษฐ์วงแหวนจาก rect ขึ้นมาเอง
        // เพื่อสิ่งที่ไม่มีใครอ่านผิดคือค่าใช้จ่ายที่ไม่คุ้ม — "31C" อ่านออกทันที
        lv_label_set_text_fmt(s_temp, "%d%c", s_frame->temp, s_frame->unit);
        lv_label_set_text_fmt(s_hilo, "H %d   L %d", s_frame->high, s_frame->low);
    } else {
        lv_obj_add_flag(s_temp, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_hilo, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_place, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s_empty, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s_empty_sub, LV_OBJ_FLAG_HIDDEN);
    }
    lv_obj_invalidate(s_icon);
    ct_weather_ui_redraw_age();
}

void ct_weather_ui_redraw_age(void)
{
    if (!*s_has_frame) {
        lv_obj_add_flag(s_age, LV_OBJ_FLAG_HIDDEN);
        return;
    }
    lv_obj_remove_flag(s_age, LV_OBJ_FLAG_HIDDEN);
    char text[40];
    age_text(text, sizeof(text), s_frame->age);
    bool stale = ct_weather_is_stale(s_frame);
    if (stale) {
        // คำว่า stale เขียนตรงๆ ข้างเวลา ไม่ใช่แทนที่มัน — คนเหลือบจอเห็นคำ ส่วนคนที่
        // สงสัยว่าเก่าแค่ไหนยังอ่านตัวเลขได้
        char loud[56];
        snprintf(loud, sizeof(loud), "STALE - %s", text);
        lv_label_set_text(s_age, loud);
    } else {
        lv_label_set_text(s_age, text);
    }
    lv_obj_set_style_text_color(s_age, ct_color(stale ? CT_COL_ALERT : CT_COL_TEXT_DIM), 0);
}

// สีของเลขอุณหภูมิถูก *ผลัก* ลงป้าย ไม่ได้ถูกอ่านตอนวาดเหมือนสีในหน้ามาสคอต การตั้งค่า
// ตั้งต้นจึงต้องเกิดที่นี่ด้วย ไม่ใช่แค่ตอนสถานะเปลี่ยน — บอร์ดที่บูตขึ้นมาโดยยังไม่เจอ Mac
// เลยจะไม่มีการ "เปลี่ยน" ให้จับ แล้วตัวเลขที่ไม่มีใครรับรองจะขึ้นด้วยสีของข้อมูลสด
static void paint_connected(void)
{
    lv_obj_set_style_text_color(s_temp, ct_color(s_connected ? CT_COL_TEXT : CT_COL_GRAY), 0);
}

void ct_weather_ui_set_connected(bool connected)
{
    if (connected == s_connected) return;
    s_connected = connected;
    paint_connected();
    lv_obj_invalidate(s_icon);
    lv_obj_invalidate(s_mini);
}

void ct_weather_ui_tick(int elapsed_ms)
{
    s_phase += (float)elapsed_ms / (float)LOOP_MS;
    while (s_phase >= 1.0f) {
        s_phase -= 1.0f;
        s_cycle++;
    }
    lv_obj_invalidate(s_mini);
}
