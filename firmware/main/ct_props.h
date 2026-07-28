// Prop — ของที่มาสคอตถือหรือลอยเหนือหัว บอกว่ากำลังทำอะไร
// พอร์ตจาก tools/gen/props.py แบบตรงตัว (ตัวเลขต้องตรงกัน ไม่งั้น preview โกหก)
#pragma once

#include "ct_rects.h"

typedef enum {
    CT_PROP_NONE = 0,
    CT_PROP_MAGNIFIER,
    CT_PROP_LAPTOP,
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

// แล็ปท็อป — วางหน้าลำตัว ไม่ใช่ช่อง prop ข้างตัว จึงมีค่าคงที่ชุดของตัวเอง
// ใหญ่เกือบเท่าลำตัว แต่แคบกว่าอยู่ราวข้างละ 1 unit — ช่องนั้นคือที่ที่ไหล่ยังโผล่ให้เห็น
// แขนที่โผล่ข้างฝาคือแขนเดิมของลำตัว (nub) ที่ขยับขึ้นลง — ไม่มีแขนวาดเพิ่มพาดหน้าฝา
#define CT_LID_X 2.5f
#define CT_LID_W 11.0f
#define CT_LID_Y 5.0f   // ขอบบนต่ำกว่าตา (จบที่ 4.1) — จอไม่บังหน้า
#define CT_LID_H 4.9f
#define CT_LAP_X 1.8f   // ฐาน — ยื่นออกกว่าฝาจอนิดเดียว จึงอ่านเป็นแล็ปท็อปไม่ใช่ป้าย
#define CT_LAP_W 12.4f
#define CT_LAP_Y 9.9f   // ฐานจบพอดีระดับฝ่าเท้า (11.2) — แล็ปท็อปบังขาหมดทั้งสี่
#define CT_LAP_H 1.3f

// ฟองข้อความเหนือหัว — thinking
#define CT_BUB_W 9.4f
#define CT_BUB_H 3.9f

#define CT_LENS_S 8.0f  // ขนาดเลนส์แว่นขยาย
#define CT_LENS_T 0.9f  // ความหนาของขอบเลนส์

// ค้อน + หมวกวิศวกร + แท่นเหล็ก — ทั้งชุดคือ prop เดียวกัน (Bash) จึงใช้ค่าคงที่ร่วมกัน
// หนึ่งลูปคือการทุบหนึ่งครั้งที่มีจังหวะเงื้อนำ ไม่ใช่ค้อนเด้งขึ้นลงสองรอบ:
// จังหวะเงื้อคือสิ่งที่ทำให้การกระแทกมีน้ำหนัก ถ้าตัดทิ้งจะเหลือแค่ของขยับไปมา
typedef enum { CT_HAM_READY, CT_HAM_WINDUP, CT_HAM_STRIKE, CT_HAM_RECOVER } ct_ham_stage_t;
// ขอบเขตของแต่ละท่าในลูป — ท่าฟาดสั้นที่สุด (สองเฟรม) เพราะการกระแทกต้องคม
#define CT_HAM_T_WINDUP 0.25f
#define CT_HAM_T_STRIKE 0.45f
#define CT_HAM_T_RECOVER 0.62f

#define CT_ANVIL_CX 20.0f  // กลางแท่น = ปลายทางที่หัวค้อนตกลงมา
#define CT_ANVIL_TOP 8.7f  // ผิวบนของบล็อก = ก้นของชิ้นงานร้อน ทั้งตอนยุบและไม่ยุบ
#define CT_HOT_UP_H 1.3f   // ชิ้นงานยุบลงราวครึ่งหนึ่งตอนโดนทุบ
#define CT_HOT_DOWN_H 0.7f

#define CT_HAM_HEAD_W 4.0f  // หัวค้อน
#define CT_HAM_HEAD_H 2.4f
#define CT_HAM_GRIP_W 1.4f  // ความหนาของด้าม
#define CT_HAM_STEP 0.65f  // ระยะไล่ของบล็อกด้ามต่อชิ้น ทั้งสองแกน = ทแยง 45 องศาพอดี
#define CT_HAM_BLK 1.4f  // ด้านของบล็อกด้าม — ใหญ่กว่า step จึงเหลื่อมกันเป็นเส้นทึบ
#define CT_HAM_N 5  // จำนวนบล็อกด้าม

void ct_prop_build(ct_rects_t *out, ct_prop_t prop, float phase, bool connected);

// กระจกในเลนส์แว่นขยาย — ต้องวาดก่อนตา จึงแยกออกจาก ct_prop_build() ที่วาดหลังตา
void ct_prop_magnifier_glass(ct_rects_t *out, float phase, bool connected);

// แท่นเหล็กที่ค้อนทุบ — วางอยู่กับพื้น จึงแยกจาก ct_prop_build() ที่ถูกเลื่อนตามตัวมาสคอต
void ct_prop_hammer_anvil(ct_rects_t *out, float phase, bool connected);

// ท่าของการทุบในเฟรมนี้ — ct_mascot.c ใช้กำหนดท่าตัวมาสคอตให้ตรงจังหวะกับค้อน
ct_ham_stage_t ct_prop_hammer_stage(float phase);
