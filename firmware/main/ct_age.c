#include "ct_age.h"

#include <stdio.h>

#include "ct_color.h"
#include "ct_fonts.h"
#include "layout.h"

void ct_age_text(char *out, size_t cap, int secs)
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

bool ct_age_is_stale(int secs, int refresh_s) { return secs > refresh_s * CT_PAGE_STALE_FACTOR; }

lv_obj_t *ct_age_label(lv_obj_t *parent)
{
    lv_obj_t *l = lv_label_create(parent);
    lv_obj_set_style_text_font(l, ct_font_text_12(), 0);
    lv_obj_set_style_text_color(l, ct_color(CT_COL_TEXT_DIM), 0);
    lv_label_set_text(l, "");
    lv_obj_set_pos(l, CT_PAGE_AGE_X, CT_PAGE_AGE_Y);
    return l;
}

void ct_age_show(lv_obj_t *label, int secs, int refresh_s)
{
    char text[40];
    ct_age_text(text, sizeof(text), secs);
    bool stale = ct_age_is_stale(secs, refresh_s);
    if (stale) {
        // คำว่า stale เขียนตรงๆ ข้างเวลา ไม่ใช่แทนที่มัน — คนเหลือบจอเห็นคำ ส่วนคนที่
        // สงสัยว่าเก่าแค่ไหนยังอ่านตัวเลขได้
        char loud[56];
        snprintf(loud, sizeof(loud), "STALE - %s", text);
        lv_label_set_text(label, loud);
    } else {
        lv_label_set_text(label, text);
    }
    lv_obj_set_style_text_color(label, ct_color(stale ? CT_COL_ALERT : CT_COL_TEXT_DIM), 0);
}

void ct_age_show_frozen(lv_obj_t *label, int secs, const char *why)
{
    char text[40];
    ct_age_text(text, sizeof(text), secs);
    char line[80];
    snprintf(line, sizeof(line), "%s  -  %s", text, why);
    lv_label_set_text(label, line);
    lv_obj_set_style_text_color(label, ct_color(CT_COL_TEXT_DIM), 0);
}
