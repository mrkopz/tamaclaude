// page frame ของหน้าหุ้น (ADR-0003) — หนึ่งหน้า หนึ่งเฟรม หนึ่ง MTU
//
// รูปแบบบนสาย:
//   {"a":42,"c":[{"d":-21,"p":"189.44","s":"AAPL"}],"g":4,"k":1}
//
// เหมือนเฟรมคริปโตทุกอย่าง บวกสองข้อ:
//   `k` = ตลาดปิดอยู่ตอนที่ Mac อ่านค่าชุดนี้มา (ไม่มีคีย์ = ตลาดเปิด) ราคาที่ค้างข้ามคืน
//         จึงไม่ถูกอ่านว่าท่อพัง
//   `d` หายไปได้ทั้งคอลัมน์ — Mac ทิ้งเปอร์เซ็นต์ก่อนทิ้งสัญลักษณ์ตอนบีบเฟรม แถวที่ไม่มี
//       มันยังจริงทุกตัวอักษร ต่างจากแถวที่แสดง 0.0% ซึ่งแปลว่าราคานิ่ง
#pragma once

#include <stdbool.h>

#include "layout.h"

// สัญลักษณ์ของตลาดสหรัฐยาวสุดห้าตัว (Mac ตัดที่ 5 อยู่แล้ว) ส่วนราคายาวสุดคือหุ้นห้าหลัก
// กับทศนิยมสองตำแหน่ง
#define CT_STOCKS_SYM_LEN 8
#define CT_STOCKS_PRICE_LEN 16

typedef struct {
    char sym[CT_STOCKS_SYM_LEN];
    char price[CT_STOCKS_PRICE_LEN];
    int change;         // เปอร์เซ็นต์คูณสิบ
    bool has_change;    // เฟรมนี้พกเปอร์เซ็นต์มาด้วยไหม
} ct_stocks_row_t;

typedef struct {
    ct_stocks_row_t rows[CT_STOCKS_ROWS];
    int count;
    // วินาทีนับจากตอนที่ Mac อ่านค่านี้มาได้จริง — บอร์ดนับต่อเองหลังจากนั้น
    int age;
    bool market_closed;
} ct_stocks_t;

// แปลง JSON หนึ่งก้อนเป็นเฟรมหุ้น — คืน false เมื่อใช้ไม่ได้ (ของเดิมต้องไม่ถูกแตะ)
bool ct_stocks_parse(const char *json, int len, ct_stocks_t *out);

// เดินอายุข้อมูลไป `secs` วินาที — เรียกจากตัวโฮสต์ ไม่ใช่ตอนรับเฟรม
void ct_stocks_tick(ct_stocks_t *s, int secs);
