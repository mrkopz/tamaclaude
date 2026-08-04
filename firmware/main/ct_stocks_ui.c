#include "ct_stocks_ui.h"

#include "ct_age.h"
#include "ct_color.h"
#include "ct_fonts.h"
#include "ct_paint.h"
#include "ct_rects.h"
#include "ct_trend.h"
#include "layout.h"

// เหตุผลที่ตัวเลขชุดนี้ค้าง — ต้องตรงกับ CLOSED ใน tools/gen/stocks.py
#define CT_STOCKS_CLOSED_TEXT "market closed"

static const ct_stocks_t *s_frame;
static const bool *s_has_frame;
static bool s_connected;

typedef struct {
    lv_obj_t *sym;
    lv_obj_t *price;
    lv_obj_t *pct;
    lv_obj_t *arrow;  // ผืนวาดลูกศรขึ้น/ลง
} ct_stocks_row_ui_t;

static ct_stocks_row_ui_t s_rows[CT_STOCKS_ROWS];
static lv_obj_t *s_age;
static lv_obj_t *s_empty;
static lv_obj_t *s_empty_sub;

static void arrow_draw_cb(lv_event_t *e)
{
    lv_obj_t *obj = lv_event_get_target_obj(e);
    int index = (int)(intptr_t)lv_event_get_user_data(e);
    if (!*s_has_frame || index >= s_frame->count) return;
    if (!s_frame->rows[index].has_change) return;

    lv_layer_t *layer = lv_event_get_layer(e);
    lv_area_t coords;
    lv_obj_get_coords(obj, &coords);

    ct_rects_t rects;
    ct_trend_arrow(&rects, s_frame->rows[index].change, s_connected);
    ct_paint_rects(layer, &rects, coords.x1, coords.y1, CT_STOCKS_ARROW_PX);
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
// ได้ด้วยการกวาดตาลงมา ไม่ใช่การอ่านทีละตัว
static lv_obj_t *right_label(lv_obj_t *parent, const lv_font_t *font, uint16_t color, int x,
                             int y, int w)
{
    lv_obj_t *l = label(parent, font, color, x, y);
    lv_obj_set_width(l, w);
    lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_RIGHT, 0);
    return l;
}

void ct_stocks_ui_init(lv_obj_t *parent, const ct_stocks_t *frame, const bool *has_frame)
{
    s_frame = frame;
    s_has_frame = has_frame;

    _Static_assert(CT_STOCKS_PRICE_FONT == 24, "layout.toml and the font here must agree");

    for (int i = 0; i < CT_STOCKS_ROWS; i++) {
        int top = CT_STOCKS_ROW_Y + i * CT_STOCKS_ROW_H;
        ct_stocks_row_ui_t *row = &s_rows[i];
        row->sym = label(parent, ct_font_text_14(), CT_COL_TEXT, CT_STOCKS_SYM_X,
                         top + CT_STOCKS_SYM_DY);
        lv_obj_set_width(row->sym, CT_STOCKS_SYM_W);
        lv_label_set_long_mode(row->sym, LV_LABEL_LONG_DOT);

        row->price = right_label(parent, &lv_font_montserrat_24, CT_COL_TEXT, CT_STOCKS_PRICE_X,
                                 top + CT_STOCKS_PRICE_DY, CT_STOCKS_PRICE_W);
        row->pct = right_label(parent, ct_font_text_14(), CT_COL_TEXT_DIM, CT_STOCKS_PCT_X,
                               top + CT_STOCKS_PCT_DY, CT_STOCKS_PCT_W);

        row->arrow = lv_obj_create(parent);
        lv_obj_remove_style_all(row->arrow);
        lv_obj_set_size(row->arrow, CT_STOCKS_ARROW_GRID * CT_STOCKS_ARROW_PX,
                        CT_STOCKS_ARROW_GRID * CT_STOCKS_ARROW_PX);
        lv_obj_set_pos(row->arrow, CT_STOCKS_ARROW_X, top + CT_STOCKS_ARROW_DY);
        lv_obj_remove_flag(row->arrow, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_add_event_cb(row->arrow, arrow_draw_cb, LV_EVENT_DRAW_MAIN,
                            (void *)(intptr_t)i);
    }

    s_age = ct_age_label(parent);
    s_empty = label(parent, ct_font_text_14(), CT_COL_TEXT, CT_STOCKS_SYM_X, CT_STOCKS_EMPTY_Y);
    lv_label_set_text(s_empty, "No stocks yet");
    s_empty_sub = label(parent, ct_font_text_12(), CT_COL_TEXT_DIM, CT_STOCKS_SYM_X,
                        CT_STOCKS_EMPTY_SUB_Y);
    lv_label_set_text(s_empty_sub, "add symbols in the mac app");

    ct_stocks_ui_redraw();
}

void ct_stocks_ui_redraw(void)
{
    bool have = *s_has_frame;
    int count = have ? s_frame->count : 0;

    for (int i = 0; i < CT_STOCKS_ROWS; i++) {
        ct_stocks_row_ui_t *row = &s_rows[i];
        // แถวที่ไม่มีหุ้นคือแถวที่ไม่มีอยู่ ไม่ใช่แถวที่มีขีดคั่น — watchlist สามตัวต้องดู
        // เหมือน watchlist สามตัว ไม่ใช่ห้าตัวที่หายไปสอง
        if (i >= count) {
            lv_obj_add_flag(row->sym, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(row->price, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(row->pct, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(row->arrow, LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        lv_obj_remove_flag(row->sym, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(row->price, LV_OBJ_FLAG_HIDDEN);

        const ct_stocks_row_t *data = &s_frame->rows[i];
        lv_label_set_text(row->sym, data->sym);
        lv_label_set_text(row->price, data->price);

        // เฟรมที่ถูกบีบจนต้องทิ้งคอลัมน์เปอร์เซ็นต์: ช่องว่าง ไม่ใช่ขีดหรือ 0.0% —
        // ทั้งสองอย่างนั้นอ่านว่า "ราคานิ่ง" ซึ่งเป็นข้อมูลที่เฟรมนี้ไม่ได้พกมา
        if (!data->has_change) {
            lv_obj_add_flag(row->pct, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(row->arrow, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_remove_flag(row->pct, LV_OBJ_FLAG_HIDDEN);
            lv_obj_remove_flag(row->arrow, LV_OBJ_FLAG_HIDDEN);
            char text[16];
            ct_trend_pct_text(text, sizeof(text), data->change);
            lv_label_set_text(row->pct, text);
            lv_obj_set_style_text_color(
                row->pct, ct_color(ct_trend_tone(data->change, s_connected)), 0);
            lv_obj_invalidate(row->arrow);
        }

        // ราคาที่ไม่มีใครรับรองแล้วเป็นเทา เหมือนราคาบนหน้าคริปโต — ตัวเลขยังอ่านได้
        // แต่ต้องไม่อ่านว่าเป็นตอนนี้
        lv_obj_set_style_text_color(row->price,
                                    ct_color(s_connected ? CT_COL_TEXT : CT_COL_GRAY), 0);
        lv_obj_set_style_text_color(row->sym,
                                    ct_color(s_connected ? CT_COL_TEXT : CT_COL_GRAY), 0);
    }

    if (count > 0) {
        lv_obj_add_flag(s_empty, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_empty_sub, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_remove_flag(s_empty, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s_empty_sub, LV_OBJ_FLAG_HIDDEN);
    }
    ct_stocks_ui_redraw_age();
}

void ct_stocks_ui_redraw_age(void)
{
    if (!*s_has_frame) {
        lv_obj_add_flag(s_age, LV_OBJ_FLAG_HIDDEN);
        return;
    }
    lv_obj_remove_flag(s_age, LV_OBJ_FLAG_HIDDEN);
    // ตลาดปิด = ราคาที่ค้างข้ามคืนเป็นเรื่องปกติ ไม่ใช่ท่อพัง คำว่า stale ต้องเก็บไว้ใช้กับ
    // อย่างหลังเท่านั้น ไม่งั้นมันจะกลายเป็นคำที่ผู้ใช้เรียนรู้ที่จะมองข้าม
    if (s_frame->market_closed) {
        ct_age_show_frozen(s_age, s_frame->age, CT_STOCKS_CLOSED_TEXT);
    } else {
        ct_age_show(s_age, s_frame->age, CT_STOCKS_REFRESH_S);
    }
}

void ct_stocks_ui_set_connected(bool connected)
{
    if (connected == s_connected) return;
    s_connected = connected;
    // สีของทุกแถวถูก *ผลัก* ลงป้าย ไม่ได้ถูกอ่านตอนวาด — วาดใหม่ทั้งใบคือทางเดียวที่
    // ทำให้ทุกแถวเปลี่ยนพร้อมกัน
    ct_stocks_ui_redraw();
}
