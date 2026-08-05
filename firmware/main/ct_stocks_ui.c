#include "ct_stocks_ui.h"

#include "ct_age.h"
#include "ct_color.h"
#include "ct_fonts.h"
#include "ct_logos.h"
#include "ct_mini.h"
#include "ct_paint.h"
#include "ct_rects.h"
#include "ct_trend.h"
#include "layout.h"

// เหตุผลที่ตัวเลขชุดนี้ค้าง — ต้องตรงกับ CLOSED ใน tools/gen/stocks.py
#define CT_STOCKS_CLOSED_TEXT "market closed"

// แถวเล็กที่อยู่ใต้การ์ด — หุ้นตัวแรกได้การ์ด ที่เหลือได้แถว
#define CT_STOCKS_LIST_ROWS (CT_STOCKS_ROWS - 1)

// หน้าต่างเวลาของเปอร์เซ็นต์บนการ์ด — ต้องตรงกับ WINDOW ใน gen/stocks.py
// **ไม่ใช่ "24h" เหมือนหน้าคริปโต** — `dp` ของ Finnhub เทียบราคาปิดครั้งก่อน ตัวเลขนี้
// จึงหยุดเดินตอนตลาดปิด และช่วงสุดสัปดาห์มันคือการเคลื่อนไหวของวันศุกร์
#define CT_STOCKS_WINDOW_TEXT "today"

// คำกำกับสองด้านของแถบช่วงราคา — ต้องตรงกับ HIGH/LOW ใน tools/gen/stocks.py
#define CT_STOCKS_RANGE_HIGH_TEXT "HIGH"
#define CT_STOCKS_RANGE_LOW_TEXT "LOW"

static const ct_stocks_t *s_frame;
static const bool *s_has_frame;
static bool s_connected;

typedef struct {
    lv_obj_t *icon;   // logo บริษัท — ตารางใบเดียวกับหน้าคริปโต (ct_logos.c)
    lv_obj_t *sym;
    lv_obj_t *price;
    lv_obj_t *arrow;  // ผืนวาดลูกศรขึ้น/ลง
    lv_obj_t *pct;
} ct_stocks_row_ui_t;

// การ์ดของหุ้นตัวแรก — ราคาแยกสองป้ายคนละขนาดที่นั่งเส้นฐานเดียวกัน เหมือนหน้าคริปโต
//
// **ช่องขวาล่างเป็นแถบช่วงราคาของวัน ไม่ใช่ผืนวาดรูป 24 ชั่วโมง** — Finnhub เหลือแต่
// /quote ที่ไม่มีประวัติจะพล็อต แต่มี h/l ของวันนี้มาในคำตอบเดิมทุกครั้ง แถบนี้จึงตอบ
// คำถามคนละข้อกับ sparkline: ราคาตอนนี้ยืนตรงไหนของสวิงวันนี้ ไม่ใช่มันเดินทางมายังไง
// · คอลัมน์ที่เหลือยังตรงกับหน้าคริปโตทุกพิกเซล คนที่ปัดสลับสองหน้าต้องเห็นของอยู่ที่เดิม
// (ดู [stocks] ใน layout.toml)
//
// วาดด้วย lv_obj สี่เหลี่ยมสองใบ ไม่ใช่ผืนวาดแบบลูกศร/sparkline — ที่นั่นต้องมีผืนเพราะ
// รูปทรงเปลี่ยนตามข้อมูล ส่วนที่นี่มีแค่สองกล่องที่ *ตำแหน่ง* เปลี่ยน ซึ่ง LVGL ย้ายให้เอง
typedef struct {
    lv_obj_t *card;
    lv_obj_t *icon;
    lv_obj_t *sym;
    lv_obj_t *price_int;
    lv_obj_t *price_frac;
    lv_obj_t *arrow;
    lv_obj_t *pct;
    lv_obj_t *win;  // แคปซูลบอกหน้าต่างเวลา เกาะซ้ายลูกศร
    lv_obj_t *hi_cap;
    lv_obj_t *hi_val;
    lv_obj_t *lo_cap;
    lv_obj_t *lo_val;
    lv_obj_t *rail;  // มาตราส่วนของช่วงราคา — ไม่มีทิศทาง จึงเทาเสมอ
    lv_obj_t *mark;  // ราคาปัจจุบันบนมาตราส่วนนั้น — สีทิศทางชุดเดียวกับลูกศร
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
// (montserrat 18/24/36) ไม่มี fallback ไทย และไม่ต้องมี — มันวาดแต่ตัวเลขที่ Mac จัดรูปมาแล้ว
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

// logo บริษัท — สำเนาของ logo_icon() ในหน้าคริปโตทุกบรรทัด และนั่นคือกติกาของสองหน้านี้
// (พิกัดคัดลอก โค้ดคัดลอก กติกาที่ใช้ร่วมอยู่ใน ct_trend.c) · ตัวรูปเองไม่ได้ถูกคัดลอก:
// ตารางมีใบเดียวทั้งโปรเจกต์ หย่อน AAPL.svg ลง tools/logos/ ข้าง BTC.svg แล้วจบ
static lv_obj_t *logo_icon(lv_obj_t *parent, int x, int y)
{
    lv_obj_t *o = lv_image_create(parent);
    lv_obj_set_pos(o, x, y);
    lv_obj_set_style_image_recolor(o, ct_color(CT_COL_GRAY), 0);
    return o;
}

// สี่เหลี่ยมทึบใบเดียว ไม่มีขอบไม่มีมุมมน — รางกับหมุดของแถบช่วงราคาเป็นรูปทรงแบบนี้ทั้งคู่
static lv_obj_t *bar(lv_obj_t *parent, int x, int y, int w, int h)
{
    lv_obj_t *o = lv_obj_create(parent);
    lv_obj_remove_style_all(o);
    lv_obj_set_size(o, w, h);
    lv_obj_set_pos(o, x, y);
    lv_obj_remove_flag(o, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_opa(o, LV_OPA_COVER, 0);
    return o;
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

    _Static_assert(CT_STOCKS_INT_FONT == 36, "layout.toml and the font here must agree");
    _Static_assert(CT_STOCKS_FRAC_FONT == 18, "layout.toml and the font here must agree");
    _Static_assert(CT_STOCKS_PCT_FONT == 24, "layout.toml and the font here must agree");
    _Static_assert(CT_STOCKS_SYM_FONT == 24, "layout.toml and the font here must agree");
    _Static_assert(CT_STOCKS_ROW_FONT == 14, "layout.toml and the font here must agree");
    // ช่องที่ layout.toml เว้นไว้ กับขนาดที่ export_logos.py raster มาจริง มาจากคนละไฟล์
    // ต้นทาง — ตัวเดียวในโปรเจกต์ที่ยังต้องตรงกันด้วยมือ ให้คอมไพเลอร์เป็นคนจับ
    _Static_assert(CT_STOCKS_ICON_PX == CT_LOGO_PX_CARD, "layout.toml and tools/logos disagree");
    _Static_assert(CT_STOCKS_ROW_ICON_PX == CT_LOGO_PX_ROW, "layout.toml and tools/logos disagree");

    // การ์ดต้องเกิดก่อนทุกอย่างที่วางทับมัน — LVGL วาดลูกตามลำดับที่ถูกสร้าง
    s_hero.card = lv_obj_create(parent);
    lv_obj_remove_style_all(s_hero.card);
    lv_obj_set_size(s_hero.card, CT_STOCKS_CARD_W, CT_STOCKS_CARD_H);
    lv_obj_set_pos(s_hero.card, CT_STOCKS_CARD_X, CT_STOCKS_CARD_Y);
    lv_obj_remove_flag(s_hero.card, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_opa(s_hero.card, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(s_hero.card, 1, 0);
    lv_obj_set_style_border_opa(s_hero.card, LV_OPA_COVER, 0);

    // ไม่ใช่ `ct_font_text_14()` เหมือนแถวเล็ก — 24px ไม่มีบิตแมปไทย และไม่ต้องมี
    // สัญลักษณ์เป็น ASCII ที่บริการเป็นคนบอก (ดู `sym_base_y` ใน layout.toml)
    // หลังการ์ด ก่อนตัวหนังสือ — LVGL วาดลูกตามลำดับที่สร้าง และ logo นั่งบนพื้นการ์ด
    s_hero.icon = logo_icon(parent, CT_STOCKS_ICON_X, CT_STOCKS_ICON_Y);

    s_hero.sym = baseline_label(parent, &lv_font_montserrat_24, CT_COL_TEXT, CT_STOCKS_SYM_X,
                                CT_STOCKS_SYM_BASE_Y);

    // ป้ายเดียวต่อก้อน ไม่ทำตัวหนาปลอม — เหตุผลเดียวกับหน้าคริปโต (ดู ct_crypto_ui.c):
    // ขอบเยื้อง 1px ที่ 36px อ่านเป็นเงาเหลื่อม ไม่ใช่น้ำหนัก
    s_hero.price_int = baseline_label(parent, &lv_font_montserrat_36, CT_COL_TEXT,
                                      CT_STOCKS_PRICE_X, CT_STOCKS_PRICE_BASE_Y);
    s_hero.price_frac = baseline_label(parent, &lv_font_montserrat_18, CT_COL_TEXT,
                                       CT_STOCKS_PRICE_X, CT_STOCKS_PRICE_BASE_Y);
    s_hero.pct = baseline_label(parent, &lv_font_montserrat_24, CT_COL_TEXT_DIM, 0,
                                CT_STOCKS_PCT_BASE_Y);
    s_hero.arrow =
        canvas(parent, 0, CT_STOCKS_ARROW_Y, CT_STOCKS_ARROW_GRID * CT_STOCKS_ARROW_PX,
               CT_STOCKS_ARROW_GRID * CT_STOCKS_ARROW_PX, arrow_draw_cb, 0);
    // แคปซูล: กล่องขอบ 1px รัศมีครึ่งความสูง พื้นโปร่ง + ป้ายจัดกลางข้างใน
    // สูงเท่าแถบที่หมึกของเปอร์เซ็นต์กินจริง (ดู `win_y`/`win_h` ใน layout.toml) ปลายบน
    // ล่างจึงเสมอกันกับตัวเลข ไม่ใช่จัดกลางโดยประมาณ · เลื่อนทั้งกล่องตามลูกศรตอนวาด
    s_hero.win = lv_obj_create(parent);
    lv_obj_remove_style_all(s_hero.win);
    lv_obj_set_size(s_hero.win, CT_STOCKS_WIN_W, CT_STOCKS_WIN_H);
    lv_obj_set_y(s_hero.win, CT_STOCKS_WIN_Y);
    lv_obj_remove_flag(s_hero.win, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_radius(s_hero.win, CT_STOCKS_WIN_R, 0);
    lv_obj_set_style_border_width(s_hero.win, 1, 0);
    lv_obj_set_style_border_opa(s_hero.win, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(s_hero.win, ct_color(CT_COL_TEXT_DIM), 0);
    lv_obj_t *win_text = lv_label_create(s_hero.win);
    lv_obj_set_style_text_font(win_text, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(win_text, ct_color(CT_COL_TEXT_DIM), 0);
    lv_label_set_text(win_text, CT_STOCKS_WINDOW_TEXT);
    lv_obj_center(win_text);

    // --- แถบช่วงราคาของวัน ---
    // คำกำกับถ่วงลง cap_dy เพราะฟอนต์เล็กกว่าตัวเลข 2px — ก้นตัวอักษรต้องเสมอกัน ไม่ใช่หัว
    // ตัวเลขได้ CT_COL_TEXT เต็ม ไม่ใช่ text_dim: มันคือราคาจริงเท่ากับที่แถวเล็กแสดง และ
    // ที่ฟอนต์ 14 ข้างราคา 36px ตัวหนา มันแย่งลำดับสายตาไปไม่ได้อยู่แล้ว
    _Static_assert(CT_STOCKS_RANGE_CAP_FONT == 12, "layout.toml and the font here must agree");
    _Static_assert(CT_STOCKS_RANGE_VAL_FONT == 14, "layout.toml and the font here must agree");
    s_hero.hi_cap = label(parent, ct_font_text_12(), CT_COL_TEXT_DIM, CT_STOCKS_RANGE_CAP_X,
                          CT_STOCKS_RANGE_HI_Y + CT_STOCKS_RANGE_CAP_DY);
    lv_label_set_text(s_hero.hi_cap, CT_STOCKS_RANGE_HIGH_TEXT);
    s_hero.lo_cap = label(parent, ct_font_text_12(), CT_COL_TEXT_DIM, CT_STOCKS_RANGE_CAP_X,
                          CT_STOCKS_RANGE_LO_Y + CT_STOCKS_RANGE_CAP_DY);
    lv_label_set_text(s_hero.lo_cap, CT_STOCKS_RANGE_LOW_TEXT);
    // กรอบเริ่มที่ขอบขวาของคำกำกับ ไม่ใช่ขอบซ้ายของบล็อก — ตัวเลขยาวผิดปกติต้องถูกกรอบตัด
    // ไม่ใช่วิ่งไปทับคำว่า HIGH
    int val_w = CT_STOCKS_RANGE_VAL_X - CT_STOCKS_RANGE_CAP_X -
                lv_text_get_width(CT_STOCKS_RANGE_HIGH_TEXT,
                                  lv_strlen(CT_STOCKS_RANGE_HIGH_TEXT), ct_font_text_12(), 0);
    s_hero.hi_val = right_label(parent, ct_font_text_14(), CT_COL_TEXT, CT_STOCKS_RANGE_VAL_X,
                                CT_STOCKS_RANGE_HI_Y, val_w);
    s_hero.lo_val = right_label(parent, ct_font_text_14(), CT_COL_TEXT, CT_STOCKS_RANGE_VAL_X,
                                CT_STOCKS_RANGE_LO_Y, val_w);
    s_hero.rail = bar(parent, CT_STOCKS_RANGE_X, CT_STOCKS_RANGE_RAIL_Y, CT_STOCKS_RANGE_W,
                      CT_STOCKS_RANGE_RAIL_H);
    s_hero.mark = bar(parent, CT_STOCKS_RANGE_X, CT_STOCKS_RANGE_MARK_Y, CT_STOCKS_RANGE_MARK_W,
                      CT_STOCKS_RANGE_MARK_H);

    for (int i = 0; i < CT_STOCKS_LIST_ROWS; i++) {
        int top = CT_STOCKS_ROW_Y + i * CT_STOCKS_ROW_H;
        int ty = top + CT_STOCKS_ROW_TEXT_DY;
        ct_stocks_row_ui_t *row = &s_rows[i];
        row->icon = logo_icon(parent, CT_STOCKS_ROW_ICON_X, top + CT_STOCKS_ROW_ICON_DY);
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
    // ไม่ใช่ SYM_X — สัญลักษณ์เยื้องไป 58 เพื่อจองช่อง logo ให้ตรงกับหน้าคริปโต แต่
    // หน้าจอตอนไม่มีข้อมูลไม่มีอะไรให้จอง (ดู CT_STOCKS_EMPTY_X ใน layout.toml)
    s_empty =
        label(parent, ct_font_text_14(), CT_COL_TEXT, CT_STOCKS_EMPTY_X, CT_STOCKS_EMPTY_Y);
    lv_label_set_text(s_empty, "No stocks yet");
    s_empty_sub = label(parent, ct_font_text_12(), CT_COL_TEXT_DIM, CT_STOCKS_EMPTY_X,
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

static void show_range(bool on)
{
    show(s_hero.hi_cap, on);
    show(s_hero.hi_val, on);
    show(s_hero.lo_cap, on);
    show(s_hero.lo_val, on);
    show(s_hero.rail, on);
    show(s_hero.mark, on);
}

// แถบช่วงราคาของวัน — พอร์ตคู่กับ `_range()` ใน tools/gen/stocks.py
//
// หมุดใช้สีทิศทางชุดเดียวกับลูกศรและเปอร์เซ็นต์ (`ct_trend_tone`) เพราะมันเป็นตัวแทนของ
// "ราคาตอนนี้" ตัวเดียวกับที่ตัวเลขใหญ่พูดถึง ไม่ใช่ของใหม่ที่ต้องเรียนรู้สี · รางเป็นเทาเสมอ
// มาตราส่วนไม่มีทิศทาง
static void draw_range(const ct_stocks_row_t *data)
{
    show_range(*s_has_frame && s_frame->has_range);
    if (!*s_has_frame || !s_frame->has_range) return;

    const ct_stocks_range_t *r = &s_frame->range;
    uint16_t cap = s_connected ? CT_COL_TEXT_DIM : CT_COL_GRAY;
    uint16_t val = s_connected ? CT_COL_TEXT : CT_COL_GRAY;
    lv_obj_set_style_text_color(s_hero.hi_cap, ct_color(cap), 0);
    lv_obj_set_style_text_color(s_hero.lo_cap, ct_color(cap), 0);
    lv_obj_set_style_text_color(s_hero.hi_val, ct_color(val), 0);
    lv_obj_set_style_text_color(s_hero.lo_val, ct_color(val), 0);
    lv_label_set_text(s_hero.hi_val, r->high);
    lv_label_set_text(s_hero.lo_val, r->low);

    lv_obj_set_style_bg_color(s_hero.rail,
                              ct_color(s_connected ? CT_COL_GRAY : CT_COL_GRAY_DARK), 0);
    // หมุดอยู่ใน *ราง* ทั้งตัวเสมอ ไม่ใช่จัดกึ่งกลางที่ตำแหน่งแล้วล้นออกไปครึ่งตัวที่ปลาย —
    // ปลายรางคือค่าที่มีความหมาย (ต่ำสุด/สูงสุดของวัน) หมุดที่ล้นอ่านว่าทะลุช่วงไปแล้ว
    // ปัดครึ่งขึ้นด้วย +50 ก่อนหาร เหมือน `_range()` ฝั่ง Python (round() ของมันปัดไปเลขคู่
    // จึงห้ามใช้ — ดู `trend.fold` ที่เจอปัญหาเดียวกันมาก่อน)
    lv_obj_set_x(s_hero.mark,
                 CT_STOCKS_RANGE_X +
                     (r->pos * (CT_STOCKS_RANGE_W - CT_STOCKS_RANGE_MARK_W) + 50) / 100);
    lv_obj_set_style_bg_color(
        s_hero.mark,
        ct_color(ct_trend_tone(data->has_change ? data->change : 0, s_connected)), 0);
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

    // หุ้นที่ยังไม่มี SVG ได้จานเปล่า ไม่ใช่ช่องว่าง — `ct_logo_card` ไม่เคยคืน NULL
    lv_image_set_src(s_hero.icon, ct_logo_card(data->sym));
    lv_obj_set_style_image_recolor_opa(s_hero.icon, s_connected ? LV_OPA_TRANSP :
                                                                  CT_LOGO_DIM_OPA, 0);

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

    // ช่วงราคาไม่ได้ผูกกับเปอร์เซ็นต์ แม้ตอนบีบเฟรม Mac จะทิ้งช่วงราคาไปก่อนก็ตาม —
    // การผูกสองอย่างนี้ในตัววาดคือการเดาลำดับการบีบของอีกฝั่ง ซึ่งเป็นสิ่งที่เปลี่ยนได้
    draw_range(data);

    show(s_hero.pct, data->has_change);
    show(s_hero.arrow, data->has_change);
    show(s_hero.win, data->has_change);
    if (!data->has_change) return;

    char pct[16];
    ct_trend_pct_text(pct, sizeof(pct), data->change);
    lv_label_set_text(s_hero.pct, pct);
    lv_obj_set_style_text_color(s_hero.pct, ct_color(ct_trend_tone(data->change, s_connected)),
                                0);
    // ลูกศรเกาะตัวเลข: วัดความกว้างจริงก่อนแล้วค่อยวาง ไม่ใช่ตั้งพิกัดตายตัวไว้ทางซ้าย
    int32_t pw = text_w(s_hero.pct, pct);
    lv_obj_set_x(s_hero.pct, CT_STOCKS_PCT_X - pw);
    int32_t ax = CT_STOCKS_PCT_X - pw - CT_STOCKS_ARROW_GAP -
                 CT_STOCKS_ARROW_GRID * CT_STOCKS_ARROW_PX;
    lv_obj_set_x(s_hero.arrow, ax);
    // ขอบขวาของป้ายอยู่ที่ ax - win_gap · กรอบชิดขวา ตำแหน่งจึงเป็นขอบขวาลบความกว้างกรอบ
    lv_obj_set_x(s_hero.win, ax - CT_STOCKS_WIN_GAP - CT_STOCKS_WIN_W);
    lv_obj_invalidate(s_hero.arrow);
}

static void draw_row(ct_stocks_row_ui_t *row, const ct_stocks_row_t *data)
{
    uint16_t text = s_connected ? CT_COL_TEXT : CT_COL_GRAY;
    lv_image_set_src(row->icon, ct_logo_row(data->sym));
    lv_obj_set_style_image_recolor_opa(row->icon, s_connected ? LV_OPA_TRANSP :
                                                                CT_LOGO_DIM_OPA, 0);
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
    show(s_hero.icon, count > 0);
    show(s_hero.sym, count > 0);
    show(s_hero.price_frac, count > 0);
    if (count > 0) {
        draw_hero(&s_frame->rows[0], live);
    } else {
        show(s_hero.price_int, false);
        show(s_hero.pct, false);
        show(s_hero.arrow, false);
        show(s_hero.win, false);
        show_range(false);
    }

    for (int i = 0; i < CT_STOCKS_LIST_ROWS; i++) {
        ct_stocks_row_ui_t *row = &s_rows[i];
        // แถวที่ไม่มีหุ้นคือแถวที่ไม่มีอยู่ ไม่ใช่แถวที่มีขีดคั่น — watchlist สามตัวต้องดู
        // เหมือน watchlist สามตัว ไม่ใช่ห้าตัวที่หายไปสอง
        bool on = i + 1 < count;
        show(row->icon, on);
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
