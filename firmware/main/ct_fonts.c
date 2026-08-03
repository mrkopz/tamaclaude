#include "ct_fonts.h"

#include "ct_font_thai.h"

static lv_font_t s_text_12;
static lv_font_t s_text_14;

void ct_fonts_init(void)
{
    s_text_12 = lv_font_montserrat_12;
    s_text_12.fallback = &ct_font_thai_12;
    s_text_14 = lv_font_montserrat_14;
    s_text_14.fallback = &ct_font_thai_14;
}

const lv_font_t *ct_font_text_12(void) { return &s_text_12; }
const lv_font_t *ct_font_text_14(void) { return &s_text_14; }
