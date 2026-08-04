#include "ct_trend.h"

#include "ct_color.h"
#include "layout.h"
#include "lvgl.h"

uint16_t ct_trend_tone(int change, bool connected)
{
    if (!connected) return CT_COL_GRAY;
    if (change > 0) return CT_COL_GOOD;
    if (change < 0) return CT_COL_ALERT;
    return CT_COL_TEXT_DIM;
}

void ct_trend_arrow(ct_rects_t *out, int change, bool connected)
{
    ct_rects_reset(out);
    uint16_t color = ct_trend_tone(change, connected);

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

void ct_trend_pct_text(char *out, size_t cap, int change)
{
    int whole = change / 10;
    int tenth = change % 10;
    if (tenth < 0) tenth = -tenth;
    const char *sign = change > 0 ? "+" : (change < 0 ? "-" : "");
    if (whole < 0) whole = -whole;
    lv_snprintf(out, cap, "%s%d.%d%%", sign, whole, tenth);
}
