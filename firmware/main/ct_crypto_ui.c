#include "ct_crypto_ui.h"

#include "ct_age.h"
#include "ct_color.h"
#include "ct_fonts.h"
#include "ct_paint.h"
#include "ct_rects.h"
#include "layout.h"

static const ct_crypto_t *s_frame;
static const bool *s_has_frame;
static bool s_connected;

typedef struct {
    lv_obj_t *sym;
    lv_obj_t *price;
    lv_obj_t *pct;
    lv_obj_t *arrow;  // ผืนวาดลูกศรขึ้น/ลง
} ct_crypto_row_ui_t;

static ct_crypto_row_ui_t s_rows[CT_CRYPTO_ROWS];
static lv_obj_t *s_age;
static lv_obj_t *s_empty;
static lv_obj_t *s_empty_sub;

// --- ขึ้นกับลง -----------------------------------------------------------------
// สีอย่างเดียวไม่พอ: ตาบอดสีแดง-เขียวคือคนกลุ่มใหญ่ที่สุดที่ *ต้อง* แยกกำไรกับขาดทุนออก
// โดยไม่อ่านตัวเลข รูปทรงจึงเป็นตัวบอกหลัก ส่วนสีเป็นตัวช่วยที่สอง
// ต้องตรงกับ tone() และ arrow() ใน tools/gen/crypto.py

// สีของแถวหนึ่ง — ทั้งลูกศรและตัวเลขเปอร์เซ็นต์อ่านจากที่เดียวกัน ไม่งั้นสองอย่างที่อยู่
// ติดกันจะเถียงกันเองได้เมื่อมีใครแก้ทางใดทางหนึ่ง
static uint16_t tone(int change, bool connected)
{
    if (!connected) return CT_COL_GRAY;
    if (change > 0) return CT_COL_GOOD;
    if (change < 0) return CT_COL_ALERT;
    return CT_COL_TEXT_DIM;
}

static void build_arrow(ct_rects_t *out, int change, bool connected)
{
    ct_rects_reset(out);
    uint16_t color = tone(change, connected);

    if (change == 0) {
        // นิ่งคือขีดเดียว ไม่ใช่ลูกศรแบนๆ — สามเหลี่ยมที่ชี้ไปไหนไม่ได้อ่านเป็นลูกศรเสีย
        ct_rects_add(out, 0.5f, 1.75f, 3.0f, 0.5f, color);
        return;
    }
    // สามขั้น กว้างขึ้นไปทางฐาน — ที่ 16px ขั้นละ 4px ยังอ่านเป็นสามเหลี่ยม
    for (int i = 0; i < 3; i++) {
        float w = 1.0f + i * 1.0f;
        float x = 2.0f - w / 2.0f;
        float y = change > 0 ? 0.5f + i * 1.0f : 3.5f - i * 1.0f - 1.0f;
        ct_rects_add(out, x, y, w, 1.0f, color);
    }
}

static void arrow_draw_cb(lv_event_t *e)
{
    lv_obj_t *obj = lv_event_get_target_obj(e);
    int index = (int)(intptr_t)lv_event_get_user_data(e);
    if (!*s_has_frame || index >= s_frame->count) return;

    lv_layer_t *layer = lv_event_get_layer(e);
    lv_area_t coords;
    lv_obj_get_coords(obj, &coords);

    ct_rects_t rects;
    build_arrow(&rects, s_frame->rows[index].change, s_connected);
    ct_paint_rects(layer, &rects, coords.x1, coords.y1, CT_CRYPTO_ARROW_PX);
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

// ป้ายที่ชิดขวาในกรอบกว้างคงที่ — หลักหน่วยของทุกแถวจึงเรียงตรงกัน และเทียบข้ามแถว
// ได้ด้วยการกวาดตาลงมา ไม่ใช่การอ่านทีละตัว (ราคาคริปโตยาวไม่เท่ากันโดยธรรมชาติ)
static lv_obj_t *right_label(lv_obj_t *parent, const lv_font_t *font, uint16_t color, int x,
                             int y, int w)
{
    lv_obj_t *l = label(parent, font, color, x, y);
    lv_obj_set_width(l, w);
    lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_RIGHT, 0);
    return l;
}

void ct_crypto_ui_init(lv_obj_t *parent, const ct_crypto_t *frame, const bool *has_frame)
{
    s_frame = frame;
    s_has_frame = has_frame;

    _Static_assert(CT_CRYPTO_PRICE_FONT == 24, "layout.toml and the font here must agree");

    for (int i = 0; i < CT_CRYPTO_ROWS; i++) {
        int top = CT_CRYPTO_ROW_Y + i * CT_CRYPTO_ROW_H;
        ct_crypto_row_ui_t *row = &s_rows[i];
        row->sym = label(parent, ct_font_text_14(), CT_COL_TEXT, CT_CRYPTO_SYM_X,
                         top + CT_CRYPTO_SYM_DY);
        lv_obj_set_width(row->sym, CT_CRYPTO_SYM_W);
        lv_label_set_long_mode(row->sym, LV_LABEL_LONG_DOT);

        row->price = right_label(parent, &lv_font_montserrat_24, CT_COL_TEXT, CT_CRYPTO_PRICE_X,
                                 top + CT_CRYPTO_PRICE_DY, CT_CRYPTO_PRICE_W);
        row->pct = right_label(parent, ct_font_text_14(), CT_COL_TEXT_DIM, CT_CRYPTO_PCT_X,
                               top + CT_CRYPTO_PCT_DY, CT_CRYPTO_PCT_W);

        row->arrow = lv_obj_create(parent);
        lv_obj_remove_style_all(row->arrow);
        lv_obj_set_size(row->arrow, CT_CRYPTO_ARROW_GRID * CT_CRYPTO_ARROW_PX,
                        CT_CRYPTO_ARROW_GRID * CT_CRYPTO_ARROW_PX);
        lv_obj_set_pos(row->arrow, CT_CRYPTO_ARROW_X, top + CT_CRYPTO_ARROW_DY);
        lv_obj_remove_flag(row->arrow, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_add_event_cb(row->arrow, arrow_draw_cb, LV_EVENT_DRAW_MAIN,
                            (void *)(intptr_t)i);
    }

    s_age = ct_age_label(parent);
    s_empty = label(parent, ct_font_text_14(), CT_COL_TEXT, CT_CRYPTO_SYM_X, CT_CRYPTO_EMPTY_Y);
    lv_label_set_text(s_empty, "No coins yet");
    s_empty_sub = label(parent, ct_font_text_12(), CT_COL_TEXT_DIM, CT_CRYPTO_SYM_X,
                        CT_CRYPTO_EMPTY_SUB_Y);
    lv_label_set_text(s_empty_sub, "add coins in the mac app");

    ct_crypto_ui_redraw();
}

// เปอร์เซ็นต์คูณสิบ -> ข้อความที่มีเครื่องหมายเสมอ — "+1.1%" กับ "1.1%" ต่างกันตรงที่
// อันหลังต้องอ่านสีหรือลูกศรก่อนถึงจะรู้ว่าขึ้นหรือลง
static void pct_text(char *out, size_t cap, int change)
{
    int whole = change / 10;
    int tenth = change % 10;
    if (tenth < 0) tenth = -tenth;
    const char *sign = change > 0 ? "+" : (change < 0 ? "-" : "");
    if (whole < 0) whole = -whole;
    lv_snprintf(out, cap, "%s%d.%d%%", sign, whole, tenth);
}

void ct_crypto_ui_redraw(void)
{
    bool have = *s_has_frame;
    int count = have ? s_frame->count : 0;

    for (int i = 0; i < CT_CRYPTO_ROWS; i++) {
        ct_crypto_row_ui_t *row = &s_rows[i];
        // แถวที่ไม่มีเหรียญคือแถวที่ไม่มีอยู่ ไม่ใช่แถวที่มีขีดคั่น — watchlist สามตัว
        // ต้องดูเหมือน watchlist สามตัว ไม่ใช่ห้าตัวที่หายไปสอง
        if (i >= count) {
            lv_obj_add_flag(row->sym, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(row->price, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(row->pct, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(row->arrow, LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        lv_obj_remove_flag(row->sym, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(row->price, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(row->pct, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(row->arrow, LV_OBJ_FLAG_HIDDEN);

        const ct_crypto_row_t *data = &s_frame->rows[i];
        lv_label_set_text(row->sym, data->sym);
        lv_label_set_text(row->price, data->price);
        char text[16];
        pct_text(text, sizeof(text), data->change);
        lv_label_set_text(row->pct, text);

        lv_obj_set_style_text_color(row->pct, ct_color(tone(data->change, s_connected)), 0);
        // ราคาที่ไม่มีใครรับรองแล้วเป็นเทา เหมือนอุณหภูมิบนหน้าอากาศ — ตัวเลขยังอ่านได้
        // แต่ต้องไม่อ่านว่าเป็นตอนนี้
        lv_obj_set_style_text_color(row->price,
                                    ct_color(s_connected ? CT_COL_TEXT : CT_COL_GRAY), 0);
        lv_obj_set_style_text_color(row->sym,
                                    ct_color(s_connected ? CT_COL_TEXT : CT_COL_GRAY), 0);
        lv_obj_invalidate(row->arrow);
    }

    if (count > 0) {
        lv_obj_add_flag(s_empty, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_empty_sub, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_remove_flag(s_empty, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s_empty_sub, LV_OBJ_FLAG_HIDDEN);
    }
    ct_crypto_ui_redraw_age();
}

void ct_crypto_ui_redraw_age(void)
{
    if (!*s_has_frame) {
        lv_obj_add_flag(s_age, LV_OBJ_FLAG_HIDDEN);
        return;
    }
    lv_obj_remove_flag(s_age, LV_OBJ_FLAG_HIDDEN);
    ct_age_show(s_age, s_frame->age, CT_CRYPTO_REFRESH_S);
}

void ct_crypto_ui_set_connected(bool connected)
{
    if (connected == s_connected) return;
    s_connected = connected;
    // สีของทุกแถวถูก *ผลัก* ลงป้าย ไม่ได้ถูกอ่านตอนวาด — วาดใหม่ทั้งใบคือทางเดียวที่
    // ทำให้ทุกแถวเปลี่ยนพร้อมกัน (กติกาเดียวกับ paint_connected ของหน้าอากาศ)
    ct_crypto_ui_redraw();
}
