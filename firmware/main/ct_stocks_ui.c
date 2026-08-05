#include "ct_stocks_ui.h"

#include "ct_age.h"
#include "ct_color.h"
#include "ct_fonts.h"
#include "ct_mini.h"
#include "ct_paint.h"
#include "ct_rects.h"
#include "ct_trend.h"
#include "layout.h"

// เหตุผลที่ตัวเลขชุดนี้ค้าง — ต้องตรงกับ CLOSED ใน tools/gen/stocks.py
#define CT_STOCKS_CLOSED_TEXT "market closed"

// แถวเล็กที่อยู่ใต้การ์ด — หุ้นตัวแรกได้การ์ด ที่เหลือได้แถว
#define CT_STOCKS_LIST_ROWS (CT_STOCKS_ROWS - 1)

static const ct_stocks_t *s_frame;
static const bool *s_has_frame;
static bool s_connected;

typedef struct {
    lv_obj_t *sym;
    lv_obj_t *price;
    lv_obj_t *arrow;  // ผืนวาดลูกศรขึ้น/ลง
    lv_obj_t *pct;
} ct_stocks_row_ui_t;

// การ์ดของหุ้นตัวแรก — ราคาแยกสองป้ายคนละขนาดที่นั่งเส้นฐานเดียวกัน เหมือนหน้าคริปโต
//
// **ไม่มีผืนวาดรูป 24 ชั่วโมง และนั่นคือความต่างข้อเดียวของเลย์เอาต์สองหน้า** — Finnhub
// เหลือแต่ /quote ที่ให้ราคาปัจจุบัน ไม่มีประวัติจะวาด กล่องรูปที่เป็นเส้นเปล่าถาวรบอกว่า
// มีอะไรพัง ทั้งที่ไม่มีอะไรพัง · คอลัมน์ที่เหลือยังตรงกับหน้าคริปโตทุกพิกเซล คนที่ปัดสลับ
// สองหน้าต้องเห็นของอยู่ที่เดิม (ดู [stocks] ใน layout.toml)
typedef struct {
    lv_obj_t *card;
    lv_obj_t *sym;
    lv_obj_t *price_int;
    lv_obj_t *price_frac;
    lv_obj_t *arrow;
    lv_obj_t *pct;
} ct_stocks_hero_ui_t;

static ct_stocks_hero_ui_t s_hero;
static ct_stocks_row_ui_t s_rows[CT_STOCKS_LIST_ROWS];
static lv_obj_t *s_hint;
static lv_obj_t *s_age;
static lv_obj_t *s_empty;
static lv_obj_t *s_empty_sub;

// --- ขึ้นกับลง -----------------------------------------------------------------
// กติกาทั้งชุด (สี ลูกศร สีการ์ด การหั่นราคา ข้อความเปอร์เซ็นต์) อยู่ที่ `ct_trend` ที่เดียว
// เพราะหน้าคริปโตเล่าเรื่องเดียวกันด้วยกติกาเดียวกันเป๊ะ · ส่วน *วิธีวาง* เป็นสำเนาที่ตั้งใจ
// ให้แยกกัน (ct_crypto_ui.c) — หน้านี้ต้องไม่พังเพราะมีคนแก้หน้าคริปโต

// ดัชนี 0 คือการ์ด ที่เหลือคือแถวเล็กเรียงลงมา
static const ct_stocks_row_t *row_for(int index)
{
    if (!*s_has_frame || index >= s_frame->count) return NULL;
    return &s_frame->rows[index];
}

static void arrow_draw_cb(lv_event_t *e)
{
    lv_obj_t *obj = lv_event_get_target_obj(e);
    int index = (int)(intptr_t)lv_event_get_user_data(e);
    const ct_stocks_row_t *data = row_for(index);
    if (!data || !data->has_change) return;

    lv_area_t coords;
    lv_obj_get_coords(obj, &coords);
    ct_rects_t rects;
    ct_trend_arrow(&rects, data->change, s_connected);
    ct_paint_rects(lv_event_get_layer(e), &rects, coords.x1, coords.y1,
                   index == 0 ? CT_STOCKS_ARROW_PX : CT_STOCKS_ROW_ARROW_PX);
}

// --- ตัวช่วยสร้าง widget --------------------------------------------------------
static lv_obj_t *label(lv_obj_t *parent, const lv_font_t *font, uint16_t color, int x, int y)
{
    lv_obj_t *l = lv_label_create(parent);
    lv_obj_set_style_text_font(l, font, 0);
    lv_obj_set_style_text_color(l, ct_color(color), 0);
    lv_label_set_text(l, "");
    ct_label_set_pos(l, x, y);
    return l;
}

// ป้ายที่ชิดขวาในกรอบกว้างคงที่ — `right` คือขอบขวาของกรอบ ไม่ใช่ขอบซ้าย เพราะสิ่งที่
// เลย์เอาต์สัญญาไว้คือ "หลักหน่วยของทุกแถวเรียงตรงกัน" ซึ่งเป็นข้อเท็จจริงของขอบขวา
static lv_obj_t *right_label(lv_obj_t *parent, const lv_font_t *font, uint16_t color, int right,
                             int y, int w)
{
    lv_obj_t *l = label(parent, font, color, right - w, y);
    lv_obj_set_width(l, w);
    lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_RIGHT, 0);
    return l;
}

// ป้ายที่วางด้วย **เส้นฐาน** ไม่ใช่ขอบบน — สองป้ายที่ฟอนต์คนละขนาดจะเรียงเป็นตัวเลข
// ก้อนเดียวกันได้ก็ต่อเมื่อเส้นฐานตรงกัน · ไม่ผ่าน `ct_label_set_pos` เพราะฟอนต์พวกนี้
// (montserrat 24/48) ไม่มี fallback ไทย และไม่ต้องมี — มันวาดแต่ตัวเลขที่ Mac จัดรูปมาแล้ว
static lv_obj_t *baseline_label(lv_obj_t *parent, const lv_font_t *font, uint16_t color, int x,
                                int baseline)
{
    lv_obj_t *l = lv_label_create(parent);
    lv_obj_set_style_text_font(l, font, 0);
    lv_obj_set_style_text_color(l, ct_color(color), 0);
    lv_label_set_text(l, "");
    lv_obj_set_pos(l, x, baseline - (font->line_height - font->base_line));
    return l;
}

static lv_obj_t *canvas(lv_obj_t *parent, int x, int y, int w, int h, lv_event_cb_t cb,
                        int index)
{
    lv_obj_t *o = lv_obj_create(parent);
    lv_obj_remove_style_all(o);
    lv_obj_set_size(o, w, h);
    lv_obj_set_pos(o, x, y);
    lv_obj_remove_flag(o, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(o, cb, LV_EVENT_DRAW_MAIN, (void *)(intptr_t)index);
    return o;
}

void ct_stocks_ui_init(lv_obj_t *parent, const ct_stocks_t *frame, const bool *has_frame)
{
    s_frame = frame;
    s_has_frame = has_frame;

    _Static_assert(CT_STOCKS_INT_FONT == 48, "layout.toml and the font here must agree");
    _Static_assert(CT_STOCKS_FRAC_FONT == 24, "layout.toml and the font here must agree");
    _Static_assert(CT_STOCKS_PCT_FONT == 24, "layout.toml and the font here must agree");
    _Static_assert(CT_STOCKS_SYM_FONT == 14, "layout.toml and the font here must agree");
    _Static_assert(CT_STOCKS_ROW_FONT == 14, "layout.toml and the font here must agree");

    // การ์ดต้องเกิดก่อนทุกอย่างที่วางทับมัน — LVGL วาดลูกตามลำดับที่ถูกสร้าง
    s_hero.card = lv_obj_create(parent);
    lv_obj_remove_style_all(s_hero.card);
    lv_obj_set_size(s_hero.card, CT_STOCKS_CARD_W, CT_STOCKS_CARD_H);
    lv_obj_set_pos(s_hero.card, CT_STOCKS_CARD_X, CT_STOCKS_CARD_Y);
    lv_obj_remove_flag(s_hero.card, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_opa(s_hero.card, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(s_hero.card, 1, 0);
    lv_obj_set_style_border_opa(s_hero.card, LV_OPA_COVER, 0);

    s_hero.sym = label(parent, ct_font_text_14(), CT_COL_TEXT, CT_STOCKS_SYM_X, CT_STOCKS_SYM_Y);
    lv_obj_set_width(s_hero.sym, CT_STOCKS_SYM_W);
    lv_label_set_long_mode(s_hero.sym, LV_LABEL_LONG_DOT);

    s_hero.price_int = baseline_label(parent, &lv_font_montserrat_48, CT_COL_TEXT,
                                      CT_STOCKS_PRICE_X, CT_STOCKS_PRICE_BASE_Y);
    s_hero.price_frac = baseline_label(parent, &lv_font_montserrat_24, CT_COL_TEXT,
                                       CT_STOCKS_PRICE_X, CT_STOCKS_PRICE_BASE_Y);
    s_hero.pct = baseline_label(parent, &lv_font_montserrat_24, CT_COL_TEXT_DIM, 0,
                                CT_STOCKS_PCT_BASE_Y);
    s_hero.arrow =
        canvas(parent, 0, CT_STOCKS_ARROW_Y, CT_STOCKS_ARROW_GRID * CT_STOCKS_ARROW_PX,
               CT_STOCKS_ARROW_GRID * CT_STOCKS_ARROW_PX, arrow_draw_cb, 0);

    for (int i = 0; i < CT_STOCKS_LIST_ROWS; i++) {
        int top = CT_STOCKS_ROW_Y + i * CT_STOCKS_ROW_H;
        int ty = top + CT_STOCKS_ROW_TEXT_DY;
        ct_stocks_row_ui_t *row = &s_rows[i];
        row->sym = label(parent, ct_font_text_14(), CT_COL_TEXT, CT_STOCKS_ROW_SYM_X, ty);
        lv_obj_set_width(row->sym, CT_STOCKS_ROW_SYM_W);
        lv_label_set_long_mode(row->sym, LV_LABEL_LONG_DOT);

        // กรอบราคาเริ่มที่ขอบขวาของสัญลักษณ์ ไม่ใช่ขอบซ้ายของแถว — ราคายาวผิดปกติต้อง
        // ถูกกรอบตัด ไม่ใช่วิ่งไปทับชื่อหุ้น
        row->price =
            right_label(parent, ct_font_text_14(), CT_COL_TEXT, CT_STOCKS_ROW_PRICE_X, ty,
                        CT_STOCKS_ROW_PRICE_X - CT_STOCKS_ROW_SYM_X - CT_STOCKS_ROW_SYM_W);
        row->arrow = canvas(parent, 0, top + CT_STOCKS_ROW_ARROW_DY,
                            CT_STOCKS_ROW_ARROW_GRID * CT_STOCKS_ROW_ARROW_PX,
                            CT_STOCKS_ROW_ARROW_GRID * CT_STOCKS_ROW_ARROW_PX, arrow_draw_cb,
                            i + 1);
        row->pct = right_label(parent, ct_font_text_14(), CT_COL_TEXT_DIM, CT_STOCKS_ROW_PCT_X,
                               ty, CT_STOCKS_ROW_PCT_X - CT_STOCKS_ROW_PRICE_X);
    }

    // คำใบ้ที่ขึ้นเฉพาะตอนไม่มีแถวเล็กเลย (หุ้นตัวเดียว) — watchlist สามตัวคือ watchlist
    // ที่ครบแล้ว การเตือนให้เพิ่มของตลอดกาลขัดกับ "ตั้งครั้งเดียวแล้วลืมมันไป"
    s_hint = label(parent, ct_font_text_12(), CT_COL_TEXT_DIM, CT_STOCKS_HINT_X,
                   CT_STOCKS_HINT_Y);
    lv_label_set_text(s_hint, "add more in the mac app");

    ct_mini_attach(parent);

    s_age = ct_age_label(parent);
    s_empty = label(parent, ct_font_text_14(), CT_COL_TEXT, CT_STOCKS_SYM_X, CT_STOCKS_EMPTY_Y);
    lv_label_set_text(s_empty, "No stocks yet");
    s_empty_sub = label(parent, ct_font_text_12(), CT_COL_TEXT_DIM, CT_STOCKS_SYM_X,
                        CT_STOCKS_EMPTY_SUB_Y);
    lv_label_set_text(s_empty_sub, "add symbols in the mac app");

    ct_stocks_ui_redraw();
}

static void show(lv_obj_t *obj, bool on)
{
    if (on) lv_obj_remove_flag(obj, LV_OBJ_FLAG_HIDDEN);
    else lv_obj_add_flag(obj, LV_OBJ_FLAG_HIDDEN);
}

// ความกว้างของ *ตัวหนังสือ* ไม่ใช่ของกรอบ — ป้ายชิดขวาที่กรอบกว้างคงที่จะรายงานความกว้าง
// ของกรอบ ซึ่งวางลูกศรให้เกาะตัวเลขไม่ได้
static int32_t text_w(lv_obj_t *l, const char *s)
{
    return lv_text_get_width(s, lv_strlen(s), lv_obj_get_style_text_font(l, LV_PART_MAIN), 0);
}

static void draw_hero(const ct_stocks_row_t *data, bool live)
{
    uint16_t text = s_connected ? CT_COL_TEXT : CT_COL_GRAY;
    // เฟรมที่ถูกบีบจนไม่มีเปอร์เซ็นต์ไม่มีทิศทางให้ใช้เลย ทั้งพื้น ขอบ ลูกศร และตัวเลข —
    // ศูนย์กับขีดอ่านว่า "ราคานิ่ง" ซึ่งเป็นข้อมูลที่เฟรมนี้ไม่ได้พกมา
    int known = data->has_change ? data->change : 0;
    lv_obj_set_style_bg_color(
        s_hero.card, ct_color(ct_trend_card_fill(known, live && data->has_change)), 0);
    lv_obj_set_style_border_color(s_hero.card, ct_color(ct_trend_card_edge(known, s_connected)),
                                  0);

    lv_label_set_text(s_hero.sym, data->sym);
    lv_obj_set_style_text_color(s_hero.sym, ct_color(text), 0);

    char head[CT_STOCKS_PRICE_LEN], tail[CT_STOCKS_PRICE_LEN];
    ct_trend_split_price(data->price, CT_STOCKS_INT_DIGITS_MAX, head, sizeof(head), tail,
                         sizeof(tail));
    lv_label_set_text(s_hero.price_int, head);
    lv_label_set_text(s_hero.price_frac, tail);
    lv_obj_set_style_text_color(s_hero.price_int, ct_color(text), 0);
    lv_obj_set_style_text_color(s_hero.price_frac, ct_color(text), 0);
    show(s_hero.price_int, head[0] != '\0');
    // ก้อนเล็กเริ่มตรงที่ก้อนใหญ่จบ ไม่ใช่ที่พิกัดคงที่ — ความกว้างของจำนวนเต็มเปลี่ยนตามราคา
    lv_obj_set_x(s_hero.price_frac,
                 CT_STOCKS_PRICE_X + (head[0] ? text_w(s_hero.price_int, head) : 0));

    show(s_hero.pct, data->has_change);
    show(s_hero.arrow, data->has_change);
    if (!data->has_change) return;

    char pct[16];
    ct_trend_pct_text(pct, sizeof(pct), data->change);
    lv_label_set_text(s_hero.pct, pct);
    lv_obj_set_style_text_color(s_hero.pct, ct_color(ct_trend_tone(data->change, s_connected)),
                                0);
    // ลูกศรเกาะตัวเลข: วัดความกว้างจริงก่อนแล้วค่อยวาง ไม่ใช่ตั้งพิกัดตายตัวไว้ทางซ้าย
    int32_t pw = text_w(s_hero.pct, pct);
    lv_obj_set_x(s_hero.pct, CT_STOCKS_PCT_X - pw);
    lv_obj_set_x(s_hero.arrow, CT_STOCKS_PCT_X - pw - CT_STOCKS_ARROW_GAP -
                                   CT_STOCKS_ARROW_GRID * CT_STOCKS_ARROW_PX);
    lv_obj_invalidate(s_hero.arrow);
}

static void draw_row(ct_stocks_row_ui_t *row, const ct_stocks_row_t *data)
{
    uint16_t text = s_connected ? CT_COL_TEXT : CT_COL_GRAY;
    lv_label_set_text(row->sym, data->sym);
    lv_label_set_text(row->price, data->price);
    lv_obj_set_style_text_color(row->sym, ct_color(text), 0);
    // ราคาที่ไม่มีใครรับรองแล้วเป็นเทา เหมือนราคาบนหน้าคริปโต — ตัวเลขยังอ่านได้ แต่ต้อง
    // ไม่อ่านว่าเป็นตอนนี้
    lv_obj_set_style_text_color(row->price, ct_color(text), 0);

    show(row->pct, data->has_change);
    show(row->arrow, data->has_change);
    if (!data->has_change) return;

    char pct[16];
    ct_trend_pct_text(pct, sizeof(pct), data->change);
    lv_label_set_text(row->pct, pct);
    lv_obj_set_style_text_color(row->pct, ct_color(ct_trend_tone(data->change, s_connected)),
                                0);
    lv_obj_set_x(row->arrow, CT_STOCKS_ROW_PCT_X - text_w(row->pct, pct) -
                                 CT_STOCKS_ROW_ARROW_GAP -
                                 CT_STOCKS_ROW_ARROW_GRID * CT_STOCKS_ROW_ARROW_PX);
    lv_obj_invalidate(row->arrow);
}

void ct_stocks_ui_redraw(void)
{
    bool have = *s_has_frame;
    int count = have ? s_frame->count : 0;
    // ตลาดปิด = ตัวเลขหยุดเดินโดยชอบธรรม ทั้งที่ลิงก์ยังอยู่ · การ์ดสีเขียวค้างทั้งคืนจะ
    // อ่านว่าหุ้นกำลังขึ้นอยู่ตอนตีสอง ซึ่งไม่จริง (หลัก "ไม่แกล้งทำเป็นสด")
    bool live = have && s_connected && !s_frame->market_closed;

    show(s_hero.card, count > 0);
    show(s_hero.sym, count > 0);
    show(s_hero.price_frac, count > 0);
    if (count > 0) {
        draw_hero(&s_frame->rows[0], live);
    } else {
        show(s_hero.price_int, false);
        show(s_hero.pct, false);
        show(s_hero.arrow, false);
    }

    for (int i = 0; i < CT_STOCKS_LIST_ROWS; i++) {
        ct_stocks_row_ui_t *row = &s_rows[i];
        // แถวที่ไม่มีหุ้นคือแถวที่ไม่มีอยู่ ไม่ใช่แถวที่มีขีดคั่น — watchlist สามตัวต้องดู
        // เหมือน watchlist สามตัว ไม่ใช่ห้าตัวที่หายไปสอง
        bool on = i + 1 < count;
        show(row->sym, on);
        show(row->price, on);
        if (on) {
            draw_row(row, &s_frame->rows[i + 1]);
        } else {
            show(row->pct, false);
            show(row->arrow, false);
        }
    }

    show(s_hint, count == 1);
    show(s_empty, count == 0);
    show(s_empty_sub, count == 0);
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
    // ทำให้ทุกแถวเปลี่ยนพร้อมกัน (กติกาเดียวกับ paint_connected ของหน้าอากาศ)
    ct_stocks_ui_redraw();
}
