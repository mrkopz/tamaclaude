// ตัวโฮสต์ของทุก page บนจอ — เป็นเจ้าของ active page, ที่เก็บ page frame ของแต่ละหน้า
// และนาฬิกาที่ต้องเดินต่อแม้หน้านั้นไม่ได้แสดงอยู่ (ADR-0002)
#pragma once

#include <stdbool.h>

#include "ct_model.h"

// `ct_page_kind_t` ถูก generate ลง layout.h จาก tools/gen/pages.py — ชนิดของ page
// เป็นชุดปิดที่บอร์ดรู้จักตั้งแต่ตอนแฟลช (ADR-0004) ไม่ใช่สิ่งที่ Mac นิยามตอนรันไทม์
// การเพิ่มหน้าใหม่จึงแก้ที่ pages.py แล้วรัน export_layout.py ส่วนฝั่ง Swift (`PageKind`)
// มีเทสต์อ่าน layout.h มาเทียบให้
#include "layout.h"

// สร้างจอและทุกหน้า ต้องเรียกหลัง lv_init และมี display แล้ว
void ct_pages_init(void);

// page frame ของหน้ามาสคอตมาถึง — เก็บทับของเดิม แล้ววาดถ้าหน้านี้แสดงอยู่
void ct_pages_set_snapshot(const ct_snapshot_t *snap);

// เฟรมของหน้าอื่นมาถึง — คืน false เมื่อ JSON ไม่ใช่รูปร่างที่หน้านั้นรับได้
//
// ประตูเดียวสำหรับทุกหน้าที่ไม่ใช่มาสคอต: ตัวเรียกอ่านคีย์ `g` ได้อย่างเดียว ส่วนการ
// ตีความเนื้อในเป็นของหน้านั้น ซึ่งเป็นที่เดียวที่รู้ว่าเฟรมของตัวเองหน้าตาอย่างไร
bool ct_pages_set_frame(ct_page_kind_t kind, const char *json, int len);

// ผู้ใช้ปิดหน้านั้นบน Mac — ลืมทั้งเฟรมและถอนออกจากรอบ rotation
// (หน้าที่ปิดต้องหายไปจริง ไม่ใช่ swipe ไปเจอหน้าที่เขียนว่า "ปิดอยู่")
void ct_pages_forget(ct_page_kind_t kind);

// รายการ PageKind ที่บอร์ดตัวนี้รู้จัก เป็น JSON พร้อมส่งกลับไปให้ Mac (ADR-0006)
// เขียนลง `out` แล้วคืนความยาว
int ct_pages_capability_json(char *out, int size);

// สถานะลิงก์เป็นของทั้งเครื่อง ไม่ใช่ของหน้าใดหน้าหนึ่ง — โฮสต์ส่งต่อให้หน้าที่สนใจ
void ct_pages_set_connected(bool connected);
void ct_pages_set_link(bool ble, bool wifi, const char *ip);

// เดินเวลาไป `elapsed_ms` — นาฬิกาของทุกหน้าเดินที่นี่ ส่วนอนิเมชันเดินเฉพาะหน้าที่แสดงอยู่
void ct_pages_tick(int elapsed_ms);
