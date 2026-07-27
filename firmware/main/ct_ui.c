#include "ct_ui.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

#include "ct_lcd.h"
#include "ct_mascot.h"
#include "ct_rects.h"
#include "layout.h"
#include "lvgl.h"

// ความสูง/ระยะของการ์ด — ตรงกับ tools/gen/screen.py
#define CARD_H 36
#define CARD_GAP 4

// หนึ่งลูปอนิเมชันยาวเท่าไร (ms) — ตรงกับสมมติฐาน "ลูปหนึ่งราว 1 วินาที" ของ mascot.c
#define LOOP_MS 1000
#define FRAME_MS 60

// ความสว่างตอนจอว่าง (DESIGN.md) กับตอนมีอะไรให้ดู
#define BL_IDLE 15
#define BL_ACTIVE 100

typedef struct {
    lv_obj_t *canvas;  // ตัววาดมาสคอต (วาดเองใน LV_EVENT_DRAW_MAIN)
    lv_obj_t *label;   // ป้ายชื่อโปรเจกต์
    int index;
} slot_t;

typedef struct {
    lv_obj_t *box;
    lv_obj_t *accent;
    lv_obj_t *title;
    lv_obj_t *body;
} card_t;

typedef struct {
    lv_obj_t *percent;  // ตัวเลขใหญ่ — สิ่งเดียวที่ต้องอ่านออกจากอีกฝั่งห้อง
    lv_obj_t *pill;     // ป้ายบอกว่าเป็นหน้าต่างไหน สีคงที่ ไม่ตามระดับ
    lv_obj_t *pill_text;
    lv_obj_t *track;  // รางแถบ
    lv_obj_t *fill;   // เนื้อแถบ
    lv_obj_t *pace;   // ขีดบอกว่า "ควรใช้ถึงไหนแล้ว" ตามเวลาที่ผ่านไปในหน้าต่าง
    lv_obj_t *reset;  // countdown
} usage_row_t;

static ct_snapshot_t s_snap;
static bool s_connected = false;

// แถบโควตาย่อบน topbar — ตรงกับ tools/gen/screen.py:_topbar
#define USAGE_TOP_W 34
#define USAGE_TOP_H 6

static lv_obj_t *s_dot, *s_link, *s_clock_small, *s_overflow, *s_usage_top;
static lv_obj_t *s_usage_track, *s_usage_fill;
static lv_obj_t *s_clock_big, *s_date;
static slot_t s_slots[CT_SLOTS_COUNT];
static card_t s_cards[CT_MAX_CARDS];
static usage_row_t s_usage[CT_USAGE_ROWS];

static float s_phase = 0.0f;
static int s_cycle = 0;

// RGB565 -> สีของ LVGL (ขยายกลับเป็น 8 บิตต่อช่องแบบเดียวกับ quantize565 ฝั่ง Python)
static lv_color_t ct_color(uint16_t c)
{
    uint8_t r5 = (c >> 11) & 0x1F, g6 = (c >> 5) & 0x3F, b5 = c & 0x1F;
    return lv_color_make((r5 * 255 + 15) / 31, (g6 * 255 + 31) / 63, (b5 * 255 + 15) / 31);
}

// ขอบซ้ายของ slot ที่ i เมื่อกำลังแสดง session อยู่ n ตัว
// ระยะห่างคงที่ 80px เสมอ แต่ยกทั้งกลุ่มมาไว้กึ่งกลางจอ — สิ่งที่ต้องนิ่งคือ *ลำดับ*
static int slot_x(int i, int n)
{
    return (int)lroundf((CT_SCREEN_WIDTH - n * CT_SLOTS_WIDTH) / 2.0f) + i * CT_SLOTS_WIDTH;
}

// --- การวาดมาสคอต ------------------------------------------------------------
static void slot_draw_cb(lv_event_t *e)
{
    lv_obj_t *obj = lv_event_get_target_obj(e);
    slot_t *slot = (slot_t *)lv_obj_get_user_data(obj);
    if (!slot || slot->index >= s_snap.session_count) return;

    lv_layer_t *layer = lv_event_get_layer(e);
    lv_area_t coords;
    lv_obj_get_coords(obj, &coords);

    const float px = CT_SLOTS_UNIT_PX;
    // ฝ่าเท้าอยู่เหนือขอบล่างของ slot เท่ากับ baseline_pad เสมอ ไม่ว่าท่าไหน
    float foot = coords.y1 + CT_SLOTS_HEIGHT - CT_SLOTS_BASELINE_PAD;
    float oy = foot - CT_BOX_Y1 * px;
    float ox = coords.x1 + CT_SLOTS_WIDTH / 2.0f - (CT_BOX_X0 + CT_BOX_X1) / 2.0f * px;

    // แต่ละตัวเดินคนละจังหวะเล็กน้อย ไม่งั้นดูเป็นหุ่นยนต์ชุดเดียวกัน
    float phase = fmodf(s_phase + slot->index * 0.17f, 1.0f);

    ct_rects_t rects;
    ct_mascot_build_centered(&rects, s_snap.sessions[slot->index].state, phase, s_connected,
                             s_cycle + slot->index);

    lv_draw_rect_dsc_t dsc;
    lv_draw_rect_dsc_init(&dsc);
    dsc.bg_opa = LV_OPA_COVER;
    dsc.border_width = 0;
    dsc.radius = 0;

    for (int i = 0; i < rects.count; i++) {
        const ct_rect_t *r = &rects.items[i];
        int x0 = (int)lroundf(ox + r->x * px);
        int y0 = (int)lroundf(oy + r->y * px);
        int x1 = (int)lroundf(ox + (r->x + r->w) * px);
        int y1 = (int)lroundf(oy + (r->y + r->h) * px);
        if (x1 <= x0 || y1 <= y0) continue;  // ชิ้นที่บางกว่าหนึ่งพิกเซลหายไปเลย
        dsc.bg_color = ct_color(r->color);
        lv_area_t a = {.x1 = x0, .y1 = y0, .x2 = x1 - 1, .y2 = y1 - 1};
        lv_draw_rect(layer, &dsc, &a);
    }
}

// --- ตัวช่วยสร้าง widget ------------------------------------------------------
static lv_obj_t *plain_obj(lv_obj_t *parent, int w, int h)
{
    lv_obj_t *o = lv_obj_create(parent);
    lv_obj_remove_style_all(o);
    lv_obj_set_size(o, w, h);
    lv_obj_remove_flag(o, LV_OBJ_FLAG_SCROLLABLE);
    return o;
}

static lv_obj_t *plain_label(lv_obj_t *parent, const lv_font_t *font, uint16_t color)
{
    lv_obj_t *l = lv_label_create(parent);
    lv_obj_set_style_text_font(l, font, 0);
    lv_obj_set_style_text_color(l, ct_color(color), 0);
    lv_label_set_text(l, "");
    return l;
}

static void build_topbar(lv_obj_t *scr)
{
    lv_obj_t *bar = plain_obj(scr, CT_SCREEN_WIDTH, CT_TOPBAR_HEIGHT);
    lv_obj_set_pos(bar, 0, 0);
    lv_obj_set_style_bg_color(bar, ct_color(CT_COL_BG_SLOT), 0);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, 0);

    s_dot = plain_obj(bar, 6, 6);
    lv_obj_set_pos(s_dot, 6, CT_TOPBAR_HEIGHT / 2 - 3);
    lv_obj_set_style_bg_opa(s_dot, LV_OPA_COVER, 0);

    s_link = plain_label(bar, &lv_font_montserrat_12, CT_COL_TEXT);
    lv_obj_align(s_link, LV_ALIGN_LEFT_MID, 17, 0);

    s_clock_small = plain_label(bar, &lv_font_montserrat_12, CT_COL_TEXT);
    lv_obj_align(s_clock_small, LV_ALIGN_RIGHT_MID, -6, 0);

    s_overflow = plain_label(bar, &lv_font_montserrat_12, CT_COL_ACCENT);
    lv_obj_align(s_overflow, LV_ALIGN_RIGHT_MID, -44, 0);

    // โควตาย่อบนแถบ — โผล่เฉพาะตอนการ์ดยึดพื้นที่ล่างไป
    // ไม่มีป้ายกำกับ ("5h") เพราะบนแถบมีค่าเดียว ไม่ต้องบอกว่าตัวไหน
    // เอาพื้นที่นั้นไปทำแถบสั้นแทน ซึ่งเหลือบแล้วรู้ทันทีโดยไม่ต้องอ่านตัวเลข
    s_usage_top = plain_label(bar, &lv_font_montserrat_12, CT_COL_GOOD);
    lv_obj_add_flag(s_usage_top, LV_OBJ_FLAG_HIDDEN);

    s_usage_track = plain_obj(bar, USAGE_TOP_W, USAGE_TOP_H);
    lv_obj_set_style_bg_color(s_usage_track, ct_color(CT_COL_BG), 0);
    lv_obj_set_style_bg_opa(s_usage_track, LV_OPA_COVER, 0);
    lv_obj_add_flag(s_usage_track, LV_OBJ_FLAG_HIDDEN);

    s_usage_fill = plain_obj(s_usage_track, USAGE_TOP_W, USAGE_TOP_H);
    lv_obj_set_style_bg_opa(s_usage_fill, LV_OPA_COVER, 0);
    lv_obj_set_pos(s_usage_fill, 0, 0);
}

static void build_slots(lv_obj_t *scr)
{
    for (int i = 0; i < CT_SLOTS_COUNT; i++) {
        s_slots[i].index = i;
        lv_obj_t *o = plain_obj(scr, CT_SLOTS_WIDTH, CT_SLOTS_HEIGHT);
        lv_obj_set_pos(o, slot_x(i, CT_SLOTS_COUNT), CT_SLOTS_TOP);
        lv_obj_set_user_data(o, &s_slots[i]);
        lv_obj_add_event_cb(o, slot_draw_cb, LV_EVENT_DRAW_MAIN, NULL);
        s_slots[i].canvas = o;

        lv_obj_t *l = plain_label(scr, &lv_font_montserrat_12, CT_COL_TEXT);
        lv_obj_set_width(l, CT_SLOTS_WIDTH - 4);
        lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_CENTER, 0);
        lv_label_set_long_mode(l, LV_LABEL_LONG_DOT);
        s_slots[i].label = l;
    }
}

static void build_cards(lv_obj_t *scr)
{
    int w = CT_SCREEN_WIDTH - CT_CARD_PAD * 2;
    for (int i = 0; i < CT_MAX_CARDS; i++) {
        lv_obj_t *box = plain_obj(scr, w, CARD_H);
        lv_obj_set_pos(box, CT_CARD_PAD, CT_CARD_TOP + CT_CARD_PAD + i * (CARD_H + CARD_GAP));
        lv_obj_set_style_bg_color(box, ct_color(CT_COL_BG_SLOT), 0);
        lv_obj_set_style_bg_opa(box, LV_OPA_COVER, 0);

        lv_obj_t *accent = plain_obj(box, 3, CARD_H);
        lv_obj_set_pos(accent, 0, 0);
        lv_obj_set_style_bg_opa(accent, LV_OPA_COVER, 0);

        lv_obj_t *title = plain_label(box, &lv_font_montserrat_14, CT_COL_TEXT);
        lv_obj_set_width(title, w - 18);
        lv_label_set_long_mode(title, LV_LABEL_LONG_DOT);
        lv_obj_set_pos(title, 9, 4);

        lv_obj_t *body = plain_label(box, &lv_font_montserrat_12, CT_COL_TEXT_DIM);
        lv_obj_set_width(body, w - 18);
        lv_label_set_long_mode(body, LV_LABEL_LONG_DOT);
        lv_obj_set_pos(body, 9, 20);

        s_cards[i] = (card_t){box, accent, title, body};
        lv_obj_add_flag(box, LV_OBJ_FLAG_HIDDEN);
    }
}

// ขอบซ้าย/ขวาของเนื้อหาในแถว usage — ตรงกับ tools/gen/screen.py:_usage_row
#define USAGE_X0 (CT_CARD_PAD + 8)
#define USAGE_X1 (CT_SCREEN_WIDTH - CT_CARD_PAD - 8)
#define USAGE_W (USAGE_X1 - USAGE_X0)

static const char *const USAGE_LABELS[CT_USAGE_ROWS] = {"Current", "Weekly"};
static const int USAGE_WINDOWS[CT_USAGE_ROWS] = {CT_USAGE_SESSION_WINDOW,
                                                 CT_USAGE_WEEKLY_WINDOW};

static void build_usage(lv_obj_t *scr)
{
    for (int i = 0; i < CT_USAGE_ROWS; i++) {
        int y = CT_CARD_TOP + CT_CARD_PAD + i * (CT_USAGE_ROW_H + CT_USAGE_GAP);
        usage_row_t *u = &s_usage[i];

        u->percent = plain_label(scr, &lv_font_montserrat_28, CT_COL_GOOD);
        lv_obj_set_pos(u->percent, USAGE_X0, y);

        // pill วาดด้วย obj โค้งมุม ไม่ใช่ label ที่มีพื้นหลัง เพราะต้องกำหนดความกว้าง
        // จากความยาวข้อความเองตอน build (ข้อความคงที่ ไม่เปลี่ยนตามข้อมูล)
        u->pill = plain_obj(scr, 62, 18);
        lv_obj_set_style_bg_color(u->pill, ct_color(CT_COL_GRAY_DARK), 0);
        lv_obj_set_style_bg_opa(u->pill, LV_OPA_COVER, 0);
        lv_obj_set_style_radius(u->pill, 9, 0);
        lv_obj_set_pos(u->pill, USAGE_X1 - 62, y + 5);

        u->pill_text = plain_label(u->pill, &lv_font_montserrat_12, CT_COL_TEXT);
        lv_label_set_text(u->pill_text, USAGE_LABELS[i]);
        lv_obj_center(u->pill_text);

        u->track = plain_obj(scr, USAGE_W, CT_USAGE_BAR_H);
        lv_obj_set_style_bg_color(u->track, ct_color(CT_COL_BG_SLOT), 0);
        lv_obj_set_style_bg_opa(u->track, LV_OPA_COVER, 0);
        lv_obj_set_pos(u->track, USAGE_X0, y + 30);

        u->fill = plain_obj(u->track, USAGE_W, CT_USAGE_BAR_H);
        lv_obj_set_style_bg_opa(u->fill, LV_OPA_COVER, 0);
        lv_obj_set_pos(u->fill, 0, 0);

        u->pace = plain_obj(scr, 1, CT_USAGE_BAR_H + 4);
        lv_obj_set_style_bg_color(u->pace, ct_color(CT_COL_OUTLINE), 0);
        lv_obj_set_style_bg_opa(u->pace, LV_OPA_COVER, 0);
        lv_obj_set_pos(u->pace, USAGE_X0, y + 28);

        u->reset = plain_label(scr, &lv_font_montserrat_12, CT_COL_TEXT_DIM);
        lv_obj_set_pos(u->reset, USAGE_X0, y + 41);

        lv_obj_add_flag(u->percent, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(u->pill, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(u->track, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(u->pace, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(u->reset, LV_OBJ_FLAG_HIDDEN);
    }
}

static void build_idle_clock(lv_obj_t *scr)
{
    // ไม่มีอะไรต้องเตือน = ให้พื้นที่นี้ทำหน้าที่นาฬิกาตั้งโต๊ะแทน
    // นี่คือสภาพที่จอเป็นอยู่เกือบตลอดเวลา ปล่อยว่างแล้วดูเหมือนอุปกรณ์พัง
    int cy = CT_CARD_TOP + CT_CARD_HEIGHT / 2;
    s_clock_big = plain_label(scr, &lv_font_montserrat_48, CT_COL_TEXT);
    lv_obj_align(s_clock_big, LV_ALIGN_TOP_MID, 0, cy - 8 - 24);
    s_date = plain_label(scr, &lv_font_montserrat_12, CT_COL_TEXT_DIM);
    lv_obj_align(s_date, LV_ALIGN_TOP_MID, 0, cy + 26 - 8);
}

void ct_ui_init(void)
{
    ct_model_clear(&s_snap);

    lv_obj_t *scr = lv_screen_active();
    lv_obj_remove_style_all(scr);
    lv_obj_set_style_bg_color(scr, ct_color(CT_COL_BG), 0);
    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);
    lv_obj_remove_flag(scr, LV_OBJ_FLAG_SCROLLABLE);

    build_topbar(scr);
    build_slots(scr);
    build_cards(scr);
    build_usage(scr);
    build_idle_clock(scr);
    ct_ui_set_snapshot(&s_snap);
}

// --- ปรับหน้าจอตาม snapshot ---------------------------------------------------
static void layout_slots(void)
{
    int n = s_snap.session_count;
    for (int i = 0; i < CT_SLOTS_COUNT; i++) {
        slot_t *s = &s_slots[i];
        if (i >= n) {
            lv_obj_add_flag(s->canvas, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(s->label, LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        int x = slot_x(i, n);
        lv_obj_remove_flag(s->canvas, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s->label, LV_OBJ_FLAG_HIDDEN);
        lv_obj_set_pos(s->canvas, x, CT_SLOTS_TOP);

        lv_label_set_text(s->label, s_snap.sessions[i].project);
        lv_obj_set_style_text_color(
            s->label, ct_color(s_connected ? CT_COL_TEXT : CT_COL_TEXT_DIM), 0);
        int foot = CT_SLOTS_TOP + CT_SLOTS_HEIGHT - CT_SLOTS_BASELINE_PAD;
        lv_obj_set_pos(s->label, x + 2, foot + 4);
    }
}

static uint16_t card_accent(ct_card_kind_t kind)
{
    switch (kind) {
        case CT_CARD_ALERT: return CT_COL_ALERT;
        case CT_CARD_DONE: return CT_COL_GOOD;
        default: return CT_COL_ACCENT;
    }
}

static void layout_cards(void)
{
    for (int i = 0; i < CT_MAX_CARDS; i++) {
        if (i >= s_snap.card_count) {
            lv_obj_add_flag(s_cards[i].box, LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        const ct_card_t *c = &s_snap.cards[i];
        lv_obj_remove_flag(s_cards[i].box, LV_OBJ_FLAG_HIDDEN);
        lv_obj_set_style_bg_color(s_cards[i].accent, ct_color(card_accent(c->kind)), 0);
        lv_label_set_text(s_cards[i].title, c->title);
        lv_label_set_text(s_cards[i].body, c->body);
    }

    // พื้นที่ล่างมีผู้ยึดสองราย (การ์ด, โควตา) — ถ้ามีรายใดรายหนึ่ง นาฬิกาใหญ่ต้องหลบ
    // ขึ้นไปอยู่บนแถบ ไม่งั้นนาฬิกาหายจากจอทั้งใบ หรือโผล่ซ้ำสองที่
    bool taken = s_snap.card_count > 0 || s_snap.has_usage;
    if (taken) {
        lv_obj_add_flag(s_clock_big, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_date, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s_clock_small, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_remove_flag(s_clock_big, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s_date, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_clock_small, LV_OBJ_FLAG_HIDDEN);
    }
}

static uint16_t usage_color(int percent)
{
    if (percent < 0) return CT_COL_TEXT_DIM;
    if (percent >= CT_USAGE_CRIT_PCT) return CT_COL_ALERT;
    if (percent >= CT_USAGE_WARN_PCT) return CT_COL_ACCENT;
    return CT_COL_GOOD;
}

// วินาทีที่เหลือ -> ข้อความสั้นที่สุดที่ยังบอกได้ว่าควรรีบไหม
// ต้องตรงกับ fmt_remaining ใน tools/gen/screen.py
static void usage_reset_text(const ct_usage_t *u, char *out, size_t cap)
{
    if (u->remaining < 0) {
        snprintf(out, cap, "no data");
    } else if (u->remaining == 0) {
        snprintf(out, cap, "resetting");
    } else {
        int d = u->remaining / 86400;
        int h = (u->remaining % 86400) / 3600;
        int m = (u->remaining % 3600) / 60;
        if (d) {
            snprintf(out, cap, "Resets in %dd %dh", d, h);
        } else if (h) {
            snprintf(out, cap, "Resets in %dh %02dm", h, m);
        } else {
            snprintf(out, cap, "Resets in %dm", m);
        }
    }
}

// โควตาย่อบนแถบตอนการ์ดยึดพื้นที่ล่าง — แสดงเฉพาะหน้าต่าง 5 ชม. ซึ่งเป็นตัวที่ขยับ
// เร็วพอจะเปลี่ยนการตัดสินใจภายในวันเดียว ส่วน weekly รอดูตอนการ์ดหายไปได้
static void layout_usage_topbar(void)
{
    bool show = s_snap.has_usage && s_snap.card_count > 0;
    if (!show) {
        lv_obj_add_flag(s_usage_top, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_usage_track, LV_OBJ_FLAG_HIDDEN);
        return;
    }
    const ct_usage_t *u = &s_snap.usage[0];
    uint16_t col = usage_color(u->percent);

    if (u->percent < 0) {
        lv_label_set_text(s_usage_top, "--%");
    } else {
        lv_label_set_text_fmt(s_usage_top, "%d%%", u->percent);
    }
    lv_obj_set_style_text_color(s_usage_top, ct_color(col), 0);

    // หลบ "+N" เมื่อมันโผล่ ไม่งั้นทับกัน
    int right = s_snap.overflow > 0 ? -70 : -44;
    lv_obj_align(s_usage_top, LV_ALIGN_RIGHT_MID, right, 0);
    // align จัดที่ *ขอบขวา* ของ track ให้เอง — ไม่ต้องหักความกว้างแถบออกอีก
    // (ฝั่ง Pillow ต้องหักเองเพราะวาดจากมุมซ้ายบน) ตรงกับ tools/gen/screen.py:_topbar
    lv_obj_align(s_usage_track, LV_ALIGN_RIGHT_MID, right - 30, 0);

    if (u->percent < 0) {
        lv_obj_add_flag(s_usage_fill, LV_OBJ_FLAG_HIDDEN);
    } else {
        int pct = u->percent > 100 ? 100 : (u->percent < 0 ? 0 : u->percent);
        int w = (USAGE_TOP_W * pct + 50) / 100;
        if (w <= 0) {
            lv_obj_add_flag(s_usage_fill, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_remove_flag(s_usage_fill, LV_OBJ_FLAG_HIDDEN);
            lv_obj_set_width(s_usage_fill, w);
            lv_obj_set_style_bg_color(s_usage_fill, ct_color(col), 0);
        }
    }
    lv_obj_remove_flag(s_usage_top, LV_OBJ_FLAG_HIDDEN);
    lv_obj_remove_flag(s_usage_track, LV_OBJ_FLAG_HIDDEN);
}

static void layout_usage(void)
{
    // การ์ดชนะโควตาเสมอ — การ์ดคือสิ่งที่ต้องการการกระทำจากผู้ใช้
    bool show = s_snap.has_usage && s_snap.card_count == 0;
    for (int i = 0; i < CT_USAGE_ROWS; i++) {
        usage_row_t *row = &s_usage[i];
        if (!show) {
            lv_obj_add_flag(row->percent, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(row->pill, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(row->track, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(row->pace, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(row->reset, LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        const ct_usage_t *u = &s_snap.usage[i];
        uint16_t col = usage_color(u->percent);

        lv_obj_remove_flag(row->percent, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(row->pill, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(row->track, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(row->reset, LV_OBJ_FLAG_HIDDEN);

        if (u->percent < 0) {
            lv_label_set_text(row->percent, "--%");
        } else {
            lv_label_set_text_fmt(row->percent, "%d%%", u->percent);
        }
        lv_obj_set_style_text_color(row->percent, ct_color(col), 0);

        // เปอร์เซ็นต์ที่ไม่รู้ = แถบว่าง ไม่ใช่แถบศูนย์ที่ดูเหมือนข้อมูลจริง
        int pct = u->percent;
        if (pct < 0) pct = 0;
        if (pct > 100) pct = 100;
        int w = (USAGE_W * pct + 50) / 100;
        if (u->percent < 0 || w <= 0) {
            lv_obj_add_flag(row->fill, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_remove_flag(row->fill, LV_OBJ_FLAG_HIDDEN);
            lv_obj_set_width(row->fill, w);
            lv_obj_set_style_bg_color(row->fill, ct_color(col), 0);
        }

        // ขีด pace หาได้จากเวลาที่เหลือล้วนๆ — ความยาวหน้าต่างเป็นค่าคงที่
        // ไม่ต้องส่งอะไรเพิ่มบนสาย และเดินต่อได้เองตอน BLE หลุด
        if (u->remaining > 0) {
            int elapsed = USAGE_WINDOWS[i] - u->remaining;
            if (elapsed < 0) elapsed = 0;
            if (elapsed > USAGE_WINDOWS[i]) elapsed = USAGE_WINDOWS[i];
            int y = CT_CARD_TOP + CT_CARD_PAD + i * (CT_USAGE_ROW_H + CT_USAGE_GAP) + 28;
            lv_obj_set_pos(row->pace,
                           USAGE_X0 + (int)((int64_t)USAGE_W * elapsed / USAGE_WINDOWS[i]), y);
            lv_obj_remove_flag(row->pace, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_add_flag(row->pace, LV_OBJ_FLAG_HIDDEN);
        }

        char text[24];
        usage_reset_text(u, text, sizeof(text));
        lv_label_set_text(row->reset, text);
    }
}

static bool everything_quiet(void)
{
    if (s_snap.card_count > 0) return false;
    for (int i = 0; i < s_snap.session_count; i++) {
        ct_state_t st = s_snap.sessions[i].state;
        if (st != CT_STATE_SLEEPING && st != CT_STATE_IDLE) return false;
    }
    return true;
}

void ct_ui_set_snapshot(const ct_snapshot_t *snap)
{
    s_snap = *snap;

    lv_label_set_text(s_clock_big, s_snap.clock);
    lv_label_set_text(s_clock_small, s_snap.clock);
    lv_label_set_text(s_date, s_snap.date);
    lv_obj_align(s_clock_big, LV_ALIGN_TOP_MID, 0, CT_CARD_TOP + CT_CARD_HEIGHT / 2 - 32);
    lv_obj_align(s_date, LV_ALIGN_TOP_MID, 0, CT_CARD_TOP + CT_CARD_HEIGHT / 2 + 18);

    if (s_snap.overflow > 0) {
        lv_label_set_text_fmt(s_overflow, "+%d", s_snap.overflow);
        lv_obj_remove_flag(s_overflow, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(s_overflow, LV_OBJ_FLAG_HIDDEN);
    }

    layout_slots();
    layout_cards();
    layout_usage();
    layout_usage_topbar();
    ct_lcd_set_backlight(everything_quiet() ? BL_IDLE : BL_ACTIVE);
}

void ct_ui_set_connected(bool connected)
{
    if (connected == s_connected) return;
    s_connected = connected;
    lv_obj_set_style_bg_color(s_dot, ct_color(connected ? CT_COL_GOOD : CT_COL_GRAY), 0);
    lv_label_set_text(s_link, connected ? "claude" : "no link");
    lv_obj_set_style_text_color(s_link,
                                ct_color(connected ? CT_COL_TEXT : CT_COL_TEXT_DIM), 0);
    layout_slots();
    for (int i = 0; i < CT_SLOTS_COUNT; i++) lv_obj_invalidate(s_slots[i].canvas);
}

void ct_ui_tick(void)
{
    s_phase += (float)FRAME_MS / (float)LOOP_MS;
    bool second_passed = false;
    while (s_phase >= 1.0f) {
        s_phase -= 1.0f;
        s_cycle++;
        second_passed = true;
    }
    for (int i = 0; i < s_snap.session_count; i++) {
        lv_obj_invalidate(s_slots[i].canvas);
    }

    // countdown เดินด้วยนาฬิกาของบอร์ดเอง ไม่ใช่ snapshot — เวลารีเซ็ตเป็นค่าสัมบูรณ์
    // BLE หลุดแล้วตัวเลขนี้ยังจริง ส่วนเปอร์เซ็นต์หยุดนิ่ง (ซึ่งถูก มันหยุดจริง)
    //
    // วาดใหม่เฉพาะตอนวินาทีเดิน และเฉพาะตอนแผงโผล่อยู่ — LVGL วาดเฉพาะสิ่งที่
    // invalidate เท่านั้น การเรียก layout_usage ทุกเฟรมจะกินเวลาไปเปล่าๆ
    if (second_passed && s_snap.has_usage) {
        ct_model_tick_usage(&s_snap, 1);
        if (s_snap.card_count == 0) {
            layout_usage();
        } else {
            layout_usage_topbar();
        }
    }
}
