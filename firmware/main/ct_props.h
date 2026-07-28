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

// ตาข้างขวา — อยู่ที่นี่เพราะ prop บางชิ้น (แว่นขยาย) ต้องเล็งไปที่ตา
// ct_mascot.c ใช้ค่าชุดเดียวกันนี้ ไม่ต้องซิงก์สองที่
#define CT_EYE_R 10.64f
#define CT_EYE_Y 2.10f
#define CT_EYE_S 2.0f
// ตาที่อยู่หลังเลนส์ต้องโตกว่าอีกข้าง ไม่งั้นวงแหวนอ่านเป็นแค่ห่วงคล้องหน้า ไม่ใช่แว่นขยาย
// ct_mascot.c เป็นคนวาดตาที่ขยายแล้ว (มันรู้ว่าตากำลังเป็นท่าไหน เช่นตอนกะพริบ)
#define CT_EYE_MAG 2.0f

#define CT_LENS_S 8.0f  // ขนาดเลนส์แว่นขยาย
#define CT_LENS_T 0.9f  // ความหนาของขอบเลนส์

void ct_prop_build(ct_rects_t *out, ct_prop_t prop, float phase, bool connected);

// กระจกในเลนส์แว่นขยาย — ต้องวาดก่อนตา จึงแยกออกจาก ct_prop_build() ที่วาดหลังตา
void ct_prop_magnifier_glass(ct_rects_t *out, float phase, bool connected);
