// หน้ามาสคอต — โครงเดียวกับ tools/gen/screen.py
//
// ที่นี่วาดอย่างเดียว: page frame ที่วาดเป็นของ `ct_pages` และนาฬิกาทุกเรือนก็เดินที่นั่น
// (ADR-0002) หน้านี้ได้พอยน์เตอร์ไปอ่านตอน init แล้วถูกบอกให้วาดใหม่เมื่อของที่อ่านอยู่เปลี่ยน
#pragma once

#include <stdint.h>

#include "ct_model.h"
#include "lvgl.h"

// สร้าง widget ทั้งหมดลงใต้ `parent` แล้วผูกกับ page frame ที่จะวาด
// ต้องเรียกหลัง lv_init และมี display แล้ว
void ct_ui_init(lv_obj_t *parent, const ct_snapshot_t *frame);

// page frame ที่ผูกไว้เปลี่ยนไปแล้ว — วาดใหม่ทั้งใบ
void ct_ui_redraw(void);

// ตัวโฮสต์เพิ่งเดินนาฬิกาโควตาไปหนึ่งวินาที — วาดเฉพาะส่วนที่ตัวเลขนั้นโผล่อยู่
void ct_ui_redraw_usage(void);

// มี snapshot สดอยู่ไหม — ไม่ว่าจะมาทาง BLE หรือ LAN ก็ตาม หลุดแล้วมาสคอตเป็นสีเทา
// ไม่มีไอคอน ไม่มีข้อความ (DESIGN.md) · เรื่องของแถบบนเป็นของ `ct_topbar_set_connected`
void ct_ui_set_connected(bool connected);

// หน้านี้แสดงนาฬิกาตัวใหญ่ / แผงโควตาเต็มอยู่ไหม — แถบบน (`ct_topbar`) ถามก่อนวาดของ
// ของมัน เพราะกติกาคือ "แถบไม่พูดซ้ำสิ่งที่หน้านั้นแสดงใหญ่กว่าอยู่แล้ว" ตัวกติกาอยู่ที่
// `ct_topbar` ส่วน *ข้อเท็จจริง* ว่าหน้านี้แสดงอะไรอยู่เป็นของที่นี่ ซึ่งเป็นคนตัดสิน
bool ct_ui_shows_clock(void);
bool ct_ui_shows_usage(void);

// เปอร์เซ็นต์ -> สีตามระดับ · แถบบนใช้สูตรเดียวกันกับแผงเต็ม ไม่ใช่สำเนาของมัน
uint16_t ct_ui_usage_color(int percent);

// เดินอนิเมชันไป `elapsed_ms` เรียกเมื่อหน้านี้เป็น active page เท่านั้น
// เวลามาจากตัวโฮสต์ ไม่ใช่ค่าคงที่ที่นี่ — นาฬิกาของหน้ากับของโฮสต์ต้องเป็นก้อนเดียวกัน
void ct_ui_tick(int elapsed_ms);
