// page frame ของหน้าปฏิทิน (ADR-0003) — หนึ่งหน้า หนึ่งเฟรม หนึ่ง MTU
//
// รูปแบบบนสาย:
//   {"a":42,"e":[{"d":"Today","n":"ประชุมทีม","t":"09:30"}],"g":3,"p":0}
//
// วันกับเวลามาเป็น *ข้อความที่จัดรูปแล้ว* ไม่ใช่เวลาสัมบูรณ์ เพราะบอร์ดไม่มี timezone
// ไม่มีปฏิทิน และไม่มีนาฬิกาที่ตั้งตรง การให้มันจัดรูปเองคือการขอให้มันเดาสามอย่างที่
// Mac รู้อยู่แล้ว (ADR-0001: Mac ถือข้อมูล board วาด)
//
// `p` คือสภาพของหน้า ไม่ใช่จำนวนนัด: หน้าที่ไม่มีนัดต้องบอกได้ว่าเพราะสัปดาห์ว่าง
// เพราะยังไม่ได้สิทธิ์ หรือเพราะผู้ใช้ยังไม่ได้เลือกปฏิทิน — สามเรื่องคนละเรื่องกัน
#pragma once

#include <stdbool.h>

#include "layout.h"

// ชื่อนัดถูกตัดที่ 22 *ช่อง* ฝั่ง Mac แล้ว ซึ่งไม่ใช่ 22 ไบต์: หนึ่งช่องไทยคือพยัญชนะ +
// สระบน + วรรณยุกต์ = สามตัว และตัวที่ประกอบร่างแล้วอยู่ใน PUA ซึ่งกิน 3 ไบต์เสมอ
// (ADR-0008) ช่องหนึ่งจึงกินได้ถึง 9 ไบต์ · 22 ช่องเต็มวัดได้ 102 ไบต์ บัฟเฟอร์ 96
// ที่เคยตั้งไว้ตัดกลางลำดับ UTF-8 แล้วขึ้นกล่องสี่เหลี่ยมท้ายชื่อ
#define CT_CAL_TITLE_LEN 128
#define CT_CAL_DAY_LEN 12
#define CT_CAL_TIME_LEN 12

// สภาพของหน้า — ตัวเลขเดินทางบนสาย ห้ามเรียงใหม่
// ฝั่ง Mac คือ `CalendarState` (host/Sources/TamaCore/Calendar.swift)
typedef enum {
    CT_CAL_OK = 0,
    CT_CAL_EMPTY = 1,
    CT_CAL_NEEDS_ACCESS = 2,
    CT_CAL_NO_CALENDARS = 3,
    CT_CAL_NOT_ASKED = 4,
} ct_calendar_state_t;

typedef struct {
    char day[CT_CAL_DAY_LEN];
    char time[CT_CAL_TIME_LEN];
    char title[CT_CAL_TITLE_LEN];
} ct_calendar_row_t;

typedef struct {
    ct_calendar_row_t rows[CT_CALENDAR_ROWS];
    int count;
    ct_calendar_state_t state;
    // วินาทีนับจากตอนที่ Mac อ่านค่านี้มาได้จริง — บอร์ดนับต่อเองหลังจากนั้น
    int age;
} ct_calendar_t;

// แปลง JSON หนึ่งก้อนเป็นเฟรมปฏิทิน — คืน false เมื่อใช้ไม่ได้ (ของเดิมต้องไม่ถูกแตะ)
bool ct_calendar_parse(const char *json, int len, ct_calendar_t *out);

// เดินอายุข้อมูลไป `secs` วินาที — เรียกจากตัวโฮสต์ ไม่ใช่ตอนรับเฟรม
void ct_calendar_tick(ct_calendar_t *c, int secs);
