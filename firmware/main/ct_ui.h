// หน้ามาสคอต — โครงเดียวกับ tools/gen/screen.py
//
// ที่นี่วาดอย่างเดียว: page frame ที่วาดเป็นของ `ct_pages` และนาฬิกาทุกเรือนก็เดินที่นั่น
// (ADR-0002) หน้านี้ได้พอยน์เตอร์ไปอ่านตอน init แล้วถูกบอกให้วาดใหม่เมื่อของที่อ่านอยู่เปลี่ยน
#pragma once

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
// ไม่มีไอคอน ไม่มีข้อความ (DESIGN.md) · ตัวนี้คุมสี ส่วน `ct_ui_set_link` คุมข้อความ
void ct_ui_set_connected(bool connected);

// ไอคอนลิงก์บนแถบบน + ป้ายชื่อข้างจุด — BLE ชนะ WiFi เสมอเพราะเป็นทางหลัก
// ทั้งคู่ false = ยังไม่มีใครคุยกับบอร์ดเลย · `ip` โผล่แทนชื่อเมื่อเหลือแต่ WiFi
// ซึ่งเป็นตอนเดียวที่ผู้ใช้ต้องการมันจริงๆ (Mac หาบอร์ดไม่เจอ ต้องกรอกเอง)
void ct_ui_set_link(bool ble, bool wifi, const char *ip);

// เดินอนิเมชันไป `elapsed_ms` เรียกเมื่อหน้านี้เป็น active page เท่านั้น
// เวลามาจากตัวโฮสต์ ไม่ใช่ค่าคงที่ที่นี่ — นาฬิกาของหน้ากับของโฮสต์ต้องเป็นก้อนเดียวกัน
void ct_ui_tick(int elapsed_ms);
