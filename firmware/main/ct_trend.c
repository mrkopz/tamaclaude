#include "ct_trend.h"

#include <string.h>

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

uint16_t ct_trend_card_fill(int change, bool live)
{
    if (!live) return CT_COL_BG_SLOT;
    if (change > 0) return CT_COL_BG_CARD_UP;
    if (change < 0) return CT_COL_BG_CARD_DOWN;
    return CT_COL_BG_SLOT;
}

uint16_t ct_trend_card_edge(int change, bool connected)
{
    if (!connected) return CT_COL_GRAY;
    if (change > 0) return CT_COL_CARD_EDGE_UP;
    if (change < 0) return CT_COL_CARD_EDGE_DOWN;
    return CT_COL_GRAY;
}

// เว้นขอบตาราง unit ไว้ทุกด้าน กันปลายชนกล่องผืนวาด — ต้องตรงกับ _TRI_INSET ฝั่ง Python
#define CT_TREND_TRI_INSET 0.4f

void ct_trend_arrow(ct_trend_arrow_t *out, int change, bool connected)
{
    out->color = ct_trend_tone(change, connected);

    if (change == 0) {
        // นิ่งคือขีดเดียว ไม่ใช่ลูกศรแบนๆ — สามเหลี่ยมที่ชี้ไปไหนไม่ได้อ่านเป็นลูกศรเสีย
        out->tri = false;
        out->bar = (ct_rect_t){0.5f, 1.75f, 3.0f, 0.5f, out->color, 0.0f};
        return;
    }
    // ปลายอยู่กึ่งกลางแนวนอน ฐานกว้างเท่าความสูง — สามเหลี่ยมด้านเท่าโดยประมาณอ่านเป็น
    // "ลูกศร" ที่ 16px ได้เร็วกว่าทรงเรียวสูง ซึ่งที่ขนาดนี้เริ่มอ่านเป็นขีดเอียง
    float lo = CT_TREND_TRI_INSET, hi = 4.0f - CT_TREND_TRI_INSET;
    float apex_y = change > 0 ? lo : hi;
    float base_y = change > 0 ? hi : lo;
    out->tri = true;
    out->p[0] = (ct_pt_t){2.0f, apex_y};
    out->p[1] = (ct_pt_t){lo, base_y};
    out->p[2] = (ct_pt_t){hi, base_y};
}

int ct_trend_fold(const uint8_t *levels, int n, uint8_t *out, int cols)
{
    if (n <= cols || cols < 2) {
        for (int i = 0; i < n; i++) out[i] = levels[i];
        return n;
    }
    for (int i = 0; i < cols; i++) {
        // ปัดครึ่งขึ้นด้วยเลขจำนวนเต็ม — ต้องได้ดัชนีชุดเดียวกับ round() ฝั่ง Python
        // ทั้ง i=0 และ i=cols-1 ตกที่ปลายพอดี ซึ่งเป็นสิ่งที่กติกานี้มีไว้เพื่อการันตี
        out[i] = levels[(i * (n - 1) * 2 + (cols - 1)) / (2 * (cols - 1))];
    }
    return cols;
}

static int spark_y_of(int level, int h)
{
    if (level < 0) level = 0;
    if (level > CT_TREND_SPARK_MAX) level = CT_TREND_SPARK_MAX;
    int span = (CT_TREND_SPARK_MAX - level) * (h - 1);
    return (span + CT_TREND_SPARK_MAX / 2) / CT_TREND_SPARK_MAX;
}

void ct_trend_spark(ct_rects_t *out, const uint8_t *levels, int n, int w, int h, int cols,
                    int pitch, int bar, bool connected)
{
    ct_rects_reset(out);
    uint16_t base_col = connected ? CT_COL_TEXT_DIM : CT_COL_GRAY;

    uint8_t pts[CT_TREND_SPARK_COLS_MAX];
    if (cols > (int)(sizeof(pts) / sizeof(pts[0]))) cols = sizeof(pts) / sizeof(pts[0]);
    int count = n > 0 ? ct_trend_fold(levels, n, pts, cols) : 0;
    if (count == 0) {
        // ไม่มีประวัติ (บริการไม่ให้มา หรือถูกตัดทิ้งตอนบีบเฟรม) = เส้นฐานเปล่ากลางกล่อง
        // กล่องว่างอ่านเป็นที่ที่ยังโหลดไม่เสร็จ ส่วนเส้นเปล่าอ่านเป็น "รู้ว่าควรมีอะไรตรงนี้
        // แต่ไม่มี" ซึ่งเป็นความจริง
        ct_rects_add(out, 0.0f, (float)((h - 1) / 2), (float)w, 1.0f, base_col);
        return;
    }

    int base_y = spark_y_of(pts[0], h);
    ct_rects_add(out, 0.0f, (float)base_y, (float)w, 1.0f, base_col);
    for (int i = 0; i < count; i++) {
        int x = i * pitch;
        if (x + bar > w) break;
        int y = spark_y_of(pts[i], h);
        int delta = (int)pts[i] - (int)pts[0];
        // แท่งขึ้นจบก่อนเส้นฐานหนึ่งพิกเซล แท่งลงเริ่มหลังมันหนึ่งพิกเซล — เส้นฐานต้อง
        // มองเห็นตลอดแนว ไม่งั้นตัวอ้างอิงของทั้งรูปหายไปตรงที่มีข้อมูลหนาแน่นที่สุดพอดี
        int top = delta > 0 ? y : base_y + 1;
        int height = delta > 0 ? base_y - y : y - base_y;
        if (height <= 0) continue;  // แท่งยาวศูนย์ไม่วาด รวมถึงแท่งแรกซึ่งเป็นเส้นฐานเอง
        ct_rects_add(out, (float)x, (float)top, (float)bar, (float)height,
                     ct_trend_tone(delta, connected));
    }
}

void ct_trend_split_price(const char *price, int int_digits_max, char *head, size_t head_cap,
                          char *tail, size_t tail_cap)
{
    const char *dot = strchr(price, '.');
    // นับ *หลัก* ไม่ใช่ตัวอักษร — Mac เติมจุลภาคคั่นหลักพันมาแล้ว ("65,343.56") และ
    // เครื่องหมายลบก็ไม่ใช่หลัก · นับตัวอักษรแปลว่าราคาหกหลักถูกหั่นลงฟอนต์เล็กทั้งก้อน
    // ก่อนถึงเพดานจริง (ต้องตรงกับ split_price() ใน tools/gen/trend.py)
    size_t digits = 0;
    for (const char *p = price; dot && p < dot; p++) {
        if (*p >= '0' && *p <= '9') digits++;
    }
    if (!dot || (int)digits > int_digits_max) {
        head[0] = '\0';
        lv_strlcpy(tail, price, tail_cap);
        return;
    }
    size_t n = (size_t)(dot - price);
    if (n >= head_cap) n = head_cap - 1;
    memcpy(head, price, n);
    head[n] = '\0';
    lv_strlcpy(tail, dot, tail_cap);
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
