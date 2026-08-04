#include "ct_fonts.h"

#include "ct_font_thai.h"

static lv_font_t s_text_12;
static lv_font_t s_text_14;

// เส้นฐานของ fallback มาจากฟอนต์หลัก ไม่ใช่ของตัวเอง — `lv_draw_label.c:405` วาง glyph
// ด้วย `font->line_height - font->base_line` ของ dsc->font แล้วหนีบทุกอย่างที่พ้นกรอบ
// label ทิ้ง (`lv_label.c:818`) ปล่อยไว้ = ฟอนต์ไทยได้กรอบของ Montserrat (สูง 15/16)
// ทั้งที่แถบหมึกจริงของมันคือ 24/28 สระล่างใต้ ญ ฐ จึงหายทั้งตัวบนบอร์ด
//
// ค่าที่ก๊อปมาคือค่ารวมของสองฟอนต์ที่ export_thai_font.py วัดให้แล้ว — ที่นี่ไม่คำนวณเอง
// เพราะสำเนาที่สองจะต่างจากสำเนาแรกในวันที่ thai.toml เปลี่ยนระยะเลื่อน
static void adopt_thai_metrics(lv_font_t *dst, const lv_font_t *thai)
{
    dst->fallback = thai;
    dst->line_height = thai->line_height;
    dst->base_line = thai->base_line;
}

// ระยะที่กล่องบรรทัดสูงกว่าตัวละติน — ที่ว่างของวรรณยุกต์ไทย ตั้งตอน init เพราะ
// ascent ของ Montserrat ต้องอ่านจากตัวมันเอง ไม่ใช่จากเลขที่ก๊อปไว้อีกที่
static int s_rise_12;
static int s_rise_14;

static int rise_of(const lv_font_t *host, const lv_font_t *composite)
{
    return (composite->line_height - composite->base_line)
           - (host->line_height - host->base_line);
}

void ct_fonts_init(void)
{
    s_text_12 = lv_font_montserrat_12;
    adopt_thai_metrics(&s_text_12, &ct_font_thai_12);
    s_rise_12 = rise_of(&lv_font_montserrat_12, &s_text_12);
    s_text_14 = lv_font_montserrat_14;
    adopt_thai_metrics(&s_text_14, &ct_font_thai_14);
    s_rise_14 = rise_of(&lv_font_montserrat_14, &s_text_14);
}

int ct_font_rise(const lv_font_t *font)
{
    return font == &s_text_12 ? s_rise_12 : font == &s_text_14 ? s_rise_14 : 0;
}

void ct_label_set_pos(lv_obj_t *label, int x, int y)
{
    const lv_font_t *f = lv_obj_get_style_text_font(label, LV_PART_MAIN);
    lv_obj_set_pos(label, x, y - ct_font_rise(f));
}

const lv_font_t *ct_font_text_12(void) { return &s_text_12; }
const lv_font_t *ct_font_text_14(void) { return &s_text_14; }
