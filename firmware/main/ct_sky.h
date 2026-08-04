// ช่วงเวลาของฟ้า — "กี่โมง" -> "ช่วงไหน"
//
// อยู่ที่นี่เพราะมีคนใช้สองหน้าแล้ว: หน้ามาสคอตใช้กับฉากเต็มจอตาม *เวลาตอนนี้*
// ส่วนหน้าปฏิทินใช้กับพื้นการ์ดตาม *เวลาของนัด* ถ้าปล่อยให้แต่ละหน้ามีสำเนาของตัวเอง
// ขอบช่วงจะเลื่อนจากกันได้เงียบๆ แล้ว 07:00 บนสองหน้าก็เป็นคนละช่วง
//
// ตรรกะทั้งหมดต้องตรงกับ tools/gen/sky.py
#pragma once

#include "layout.h"

typedef enum {
    CT_SKY_NIGHT = 0,
    CT_SKY_DAWN,
    CT_SKY_DAY,
    CT_SKY_DUSK,
    CT_SKY_PHASE_COUNT,
    CT_SKY_NONE,  // ไม่ต่อลิงก์ หรือยังไม่รู้เวลา -> ไม่มีฉากเลย
} ct_sky_phase_t;

// "14:32" -> 14.533 · คืนค่าติดลบเมื่ออ่านไม่ได้
// ติดลบไม่ใช่เที่ยงคืน แต่คือ "ยังไม่รู้เวลา" — ตอนบูตก่อน sync ครั้งแรก clock เป็น "--:--"
// และเวลาของนัดทั้งวันเป็น "all day" ทั้งคู่ต้องตกมาทางนี้ ไม่ใช่ไปโผล่เป็นฉากกลางดึก
static inline float ct_clock_hours(const char *c)
{
    for (int i = 0; i < 5; i++) {
        if (c[i] == '\0') return -1.0f;
    }
    if (c[2] != ':') return -1.0f;
    for (int i = 0; i < 5; i++) {
        if (i == 2) continue;
        if (c[i] < '0' || c[i] > '9') return -1.0f;
    }
    int h = (c[0] - '0') * 10 + (c[1] - '0');
    int m = (c[3] - '0') * 10 + (c[4] - '0');
    if (h > 23 || m > 59) return -1.0f;
    return (float)h + (float)m / 60.0f;
}

// ชั่วโมง -> ช่วง — กระโดดที่ขอบ ไม่ผสมสีระหว่างช่วง
static inline ct_sky_phase_t ct_sky_phase_at(float t)
{
    if (t < CT_SKY_DAWN_HOUR || t >= CT_SKY_NIGHT_HOUR) return CT_SKY_NIGHT;
    if (t < CT_SKY_DAY_HOUR) return CT_SKY_DAWN;
    if (t < CT_SKY_DUSK_HOUR) return CT_SKY_DAY;
    return CT_SKY_DUSK;
}
