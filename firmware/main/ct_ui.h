// หน้าจอทั้งใบ — โครงเดียวกับ tools/gen/screen.py
#pragma once

#include "ct_model.h"

// สร้าง widget ทั้งหมด ต้องเรียกหลัง lv_init และมี display แล้ว
void ct_ui_init(void);

// เปลี่ยนภาพทั้งใบตาม snapshot ใหม่
void ct_ui_set_snapshot(const ct_snapshot_t *snap);

// BLE ต่ออยู่หรือไม่ — หลุดแล้วมาสคอตเป็นสีเทา ไม่มีไอคอน ไม่มีข้อความ (DESIGN.md)
void ct_ui_set_connected(bool connected);

// เดินอนิเมชันหนึ่งเฟรม เรียกจากลูปหลัก
void ct_ui_tick(void);
