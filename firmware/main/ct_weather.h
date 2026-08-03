// page frame ของหน้าอากาศ (ADR-0003) — หนึ่งหน้า หนึ่งเฟรม หนึ่ง MTU
//
// รูปแบบบนสาย (คีย์สั้นเพราะต้องพอดี 1 MTU เหมือน snapshot):
//   {"a":420,"g":1,"h":34,"l":26,"p":"Bangkok","t":31,"u":"C","w":61}
//
// `g` คือ `ct_page_kind_t` — เฟรมที่ *ไม่มี* คีย์นี้คือ snapshot ของหน้ามาสคอต ซึ่งเป็น
// เหตุผลที่ firmware รุ่นก่อนหน้ายังอ่านของเดิมได้โดยไม่ต้องรู้ว่ามีหลายหน้าแล้ว
//
// เฟรมที่มี `"x":1` คือคำสั่งให้ลืมหน้านี้ — ผู้ใช้ปิดมันบน Mac หน้าที่ปิดต้องหายไปจาก
// รอบ rotation จริงๆ ไม่ใช่ swipe ไปเจอหน้าที่เขียนว่า "ปิดอยู่"
#pragma once

#include <stdbool.h>

#define CT_WEATHER_PLACE_LEN 40

typedef struct {
    char place[CT_WEATHER_PLACE_LEN];
    int temp;
    int high;
    int low;
    // รหัสสภาพอากาศ WMO ดิบจาก Open-Meteo — บอร์ดแปลเป็นสัญลักษณ์เอง (ADR-0004)
    int code;
    char unit;  // 'C' หรือ 'F'
    // วินาทีนับจากตอนที่ Mac อ่านค่านี้มาได้จริง — บอร์ดนับต่อเองหลังจากนั้น จึงยัง
    // บอกความจริงได้ตอนลิงก์หลุด (กลไกเดียวกับ ct_usage_t.remaining)
    int age;
} ct_weather_t;

// แปลง JSON หนึ่งก้อนเป็นเฟรมอากาศ — คืน false เมื่อใช้ไม่ได้ (ของเดิมต้องไม่ถูกแตะ)
bool ct_weather_parse(const char *json, int len, ct_weather_t *out);

// เดินอายุข้อมูลไป `secs` วินาที — เรียกจากตัวโฮสต์ ไม่ใช่ตอนรับเฟรม
void ct_weather_tick(ct_weather_t *w, int secs);

// เก่าเกินกว่าจะบอกเป็นตัวเลขเฉยๆ แล้วหรือยัง (เกิน stale_factor เท่าของรอบดึง)
bool ct_weather_is_stale(const ct_weather_t *w);
