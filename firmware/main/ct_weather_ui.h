// หน้าอากาศ — โครงเดียวกับ tools/gen/weather.py
//
// ที่นี่วาดอย่างเดียว: page frame ที่วาดและนาฬิกาทุกเรือนเป็นของ `ct_pages` (ADR-0002)
// หน้านี้ได้พอยน์เตอร์ไปอ่านตอน init แล้วถูกบอกให้วาดใหม่เมื่อของที่อ่านอยู่เปลี่ยน
#pragma once

#include "ct_model.h"
#include "ct_weather.h"
#include "lvgl.h"

// สร้าง widget ทั้งหมดใต้ `parent` แล้วผูกกับสิ่งที่จะวาด
//
// `has_frame` คือธงของตัวโฮสต์ที่บอกว่าเคยได้ข้อมูลของหน้านี้แล้วหรือยัง — สภาพ
// "ยังไม่เคยได้เลย" มีหน้าตาของตัวเอง ห้ามเป็นจอเปล่าหรือโครงว่าง (ADR-0002)
// `mascot` คือ snapshot ของหน้ามาสคอต ซึ่งมาสคอตจิ๋วมุมจออ่าน pose จากมัน
void ct_weather_ui_init(lv_obj_t *parent, const ct_weather_t *frame, const bool *has_frame,
                        const ct_snapshot_t *mascot);

// เฟรมที่ผูกไว้เปลี่ยนไปแล้ว — วาดใหม่ทั้งใบ
void ct_weather_ui_redraw(void);

// ตัวโฮสต์เพิ่งเดินอายุข้อมูลไปหนึ่งวินาที — วาดเฉพาะบรรทัดที่บอกอายุ
void ct_weather_ui_redraw_age(void);

// มี snapshot สดอยู่ไหม — หลุดแล้วมาสคอตจิ๋วเป็นสีเทาเหมือนตัวใหญ่บนหน้ามาสคอต
void ct_weather_ui_set_connected(bool connected);

// เดินอนิเมชันของมาสคอตจิ๋วไป `elapsed_ms` — เรียกเมื่อหน้านี้เป็น active page เท่านั้น
void ct_weather_ui_tick(int elapsed_ms);
