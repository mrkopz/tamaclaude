// ตัวโฮสต์ของทุก page บนจอ — เป็นเจ้าของ active page, ที่เก็บ page frame ของแต่ละหน้า
// และนาฬิกาที่ต้องเดินต่อแม้หน้านั้นไม่ได้แสดงอยู่ (ADR-0002)
//
// รอบนี้มีหน้าเดียวคือมาสคอต ยังไม่มีการเปลี่ยนหน้าและไม่มีอะไรใหม่บนสาย — โครงนี้มีไว้
// ให้การเพิ่มหน้าที่สองเป็นการ "เพิ่ม" ไม่ใช่การรื้อ
#pragma once

#include <stdbool.h>

#include "ct_model.h"

// ชนิดของ page เป็นชุดปิดที่บอร์ดรู้จักตั้งแต่ตอนแฟลช (ADR-0004) — การเพิ่มค่าที่นี่
// ต้องแก้ฝั่ง Swift และ Python พร้อมกัน ไม่ใช่สิ่งที่ Mac นิยามขึ้นตอนรันไทม์
typedef enum {
    CT_PAGE_MASCOT = 0,
    CT_PAGE_KIND_COUNT,
} ct_page_kind_t;

// สร้างจอและทุกหน้า ต้องเรียกหลัง lv_init และมี display แล้ว
void ct_pages_init(void);

// page frame ของหน้ามาสคอตมาถึง — เก็บทับของเดิม แล้ววาดถ้าหน้านี้แสดงอยู่
void ct_pages_set_snapshot(const ct_snapshot_t *snap);

// สถานะลิงก์เป็นของทั้งเครื่อง ไม่ใช่ของหน้าใดหน้าหนึ่ง — โฮสต์ส่งต่อให้หน้าที่สนใจ
void ct_pages_set_connected(bool connected);
void ct_pages_set_link(bool ble, bool wifi, const char *ip);

// เดินเวลาไป `elapsed_ms` — นาฬิกาของทุกหน้าเดินที่นี่ ส่วนอนิเมชันเดินเฉพาะหน้าที่แสดงอยู่
void ct_pages_tick(int elapsed_ms);
