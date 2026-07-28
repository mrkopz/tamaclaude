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
    // รัศมีมุมเป็น unit — 0 = มุมคม ซึ่งเป็นค่าตั้งต้นของทุกชิ้นยกเว้นซิลลูเอ็ตมาสคอต
    // ไม่ย่อตาม ct_rects_scale_from(): ที่ 2px การย่อทุกกรณีในโค้ดนี้ปัดกลับมาเป็น 2px อยู่ดี
    float r;
} ct_rect_t;

typedef struct {
    ct_rect_t items[CT_RECTS_MAX];
    int count;
} ct_rects_t;

static inline void ct_rects_reset(ct_rects_t *rs) { rs->count = 0; }

// เกิน CT_RECTS_MAX แล้วทิ้งเงียบๆ ดีกว่าเขียนล้น — ตรวจได้ด้วย ct_rects_full()
static inline void ct_rects_add_round(ct_rects_t *rs, float x, float y, float w, float h,
                                      uint16_t color, float r)
{
    if (rs->count >= CT_RECTS_MAX) return;
    rs->items[rs->count++] = (ct_rect_t){x, y, w, h, color, r};
}

static inline void ct_rects_add(ct_rects_t *rs, float x, float y, float w, float h,
                                uint16_t color)
{
    ct_rects_add_round(rs, x, y, w, h, color, 0.0f);
}

static inline bool ct_rects_full(const ct_rects_t *rs) { return rs->count >= CT_RECTS_MAX; }

// เลื่อนทั้งชุด ตั้งแต่ดัชนี from เป็นต้นไป (ใช้เลื่อนเฉพาะส่วนที่เพิ่งเพิ่มเข้าไป)
void ct_rects_move_from(ct_rects_t *rs, int from, float dx, float dy);

// ย่อ/ขยายชุด ตั้งแต่ดัชนี from เป็นต้นไป รอบจุด (ox, oy)
void ct_rects_scale_from(ct_rects_t *rs, int from, float sx, float sy, float ox, float oy);

// กรอบรวมของทั้งชุด
void ct_rects_bounds(const ct_rects_t *rs, float *x0, float *y0, float *x1, float *y1);
