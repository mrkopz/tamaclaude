// Prop — ของที่มาสคอตถือหรือลอยเหนือหัว บอกว่ากำลังทำอะไร
// พอร์ตจาก tools/gen/props.py แบบตรงตัว (ตัวเลขต้องตรงกัน ไม่งั้น preview โกหก)
#pragma once

#include "ct_rects.h"

typedef enum {
    CT_PROP_NONE = 0,
    CT_PROP_MAGNIFIER,
    CT_PROP_PENCIL,
    CT_PROP_HAMMER,
    CT_PROP_GLOBE,
    CT_PROP_DOTS,
    CT_PROP_BANG,
    CT_PROP_QUERY,
    CT_PROP_ZZZ,
    CT_PROP_SPARKLE,
    CT_PROP_CREW,
    CT_PROP_BEACON,
} ct_prop_t;

#define CT_HEAD_CX 8.0f  // กึ่งกลางลำตัวในแนวนอน
#define CT_HAND_X 17.2f  // ขอบซ้ายของพื้นที่ prop ที่ถือ (แขนจบที่ 16.5)
#define CT_HAND_Y 2.4f

void ct_prop_build(ct_rects_t *out, ct_prop_t prop, float phase, bool connected);
