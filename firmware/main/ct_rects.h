// Rect list — รูปแบบ asset เดียวของโปรเจกต์ (ตรงกับ tools/gen/rects.py)
//
// มาสคอตและ prop ทุกชิ้นคือรายการสี่เหลี่ยมในพิกัด "unit" ไม่ใช่พิกเซล
// การแปลงเป็นพิกเซลเกิดตอนวาดเท่านั้น จึงย่อขยายได้โดยไม่ต้องแก้ asset
#pragma once

#include <stdbool.h>
#include <stdint.h>

#define CT_RECTS_MAX 72  // ท่าที่หนักที่สุด (ซิลลูเอ็ต + ขอบ + ตา + prop) ใช้ราว 40

typedef struct {
    float x, y, w, h;
    uint16_t color;  // RGB565 ตามที่แผงจอกินจริง
} ct_rect_t;

typedef struct {
    ct_rect_t items[CT_RECTS_MAX];
    int count;
} ct_rects_t;

static inline void ct_rects_reset(ct_rects_t *rs) { rs->count = 0; }

// เกิน CT_RECTS_MAX แล้วทิ้งเงียบๆ ดีกว่าเขียนล้น — ตรวจได้ด้วย ct_rects_full()
static inline void ct_rects_add(ct_rects_t *rs, float x, float y, float w, float h,
                                uint16_t color)
{
    if (rs->count >= CT_RECTS_MAX) return;
    rs->items[rs->count++] = (ct_rect_t){x, y, w, h, color};
}

static inline bool ct_rects_full(const ct_rects_t *rs) { return rs->count >= CT_RECTS_MAX; }

// เลื่อนทั้งชุด ตั้งแต่ดัชนี from เป็นต้นไป (ใช้เลื่อนเฉพาะส่วนที่เพิ่งเพิ่มเข้าไป)
void ct_rects_move_from(ct_rects_t *rs, int from, float dx, float dy);

// ขอบรอบซิลลูเอ็ต: ชิ้นที่พองออกด้วยสีขอบ วาดไว้ข้างหลัง
// ถูกกว่าการหา contour จริง และให้ผลเหมือนกันเพราะทุกชิ้นเป็นสี่เหลี่ยมแกนตั้งฉาก
void ct_rects_outline_pass(ct_rects_t *dst, const ct_rects_t *src, float width, uint16_t color);

// กรอบรวมของทั้งชุด
void ct_rects_bounds(const ct_rects_t *rs, float *x0, float *y0, float *x1, float *y1);
