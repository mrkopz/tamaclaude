// หน้าอากาศ — โครงเดียวกับ tools/gen/weather.py
//
// ที่นี่วาดอย่างเดียว: page frame ที่วาดและนาฬิกาทุกเรือนเป็นของ `ct_pages` (ADR-0002)
// หน้านี้ได้พอยน์เตอร์ไปอ่านตอน init แล้วถูกบอกให้วาดใหม่เมื่อของที่อ่านอยู่เปลี่ยน
#pragma once

#include "ct_weather.h"
#include "lvgl.h"

// สร้าง widget ทั้งหมดใต้ `parent` แล้วผูกกับสิ่งที่จะวาด
//
// `has_frame` คือธงของตัวโฮสต์ที่บอกว่าเคยได้ข้อมูลของหน้านี้แล้วหรือยัง — สภาพ
// "ยังไม่เคยได้เลย" มีหน้าตาของตัวเอง ห้ามเป็นจอเปล่าหรือโครงว่าง (ADR-0002)
// มาสคอตจิ๋วมุมจอไม่ได้เป็นของหน้านี้ — มันอยู่ทุกหน้า และเป็นของ `ct_mini`
void ct_weather_ui_init(lv_obj_t *parent, const ct_weather_t *frame, const bool *has_frame);

// เฟรมที่ผูกไว้เปลี่ยนไปแล้ว — วาดใหม่ทั้งใบ
void ct_weather_ui_redraw(void);

// ตัวโฮสต์เพิ่งเดินอายุข้อมูลไปหนึ่งวินาที — วาดเฉพาะบรรทัดที่บอกอายุ
void ct_weather_ui_redraw_age(void);

// มี snapshot สดอยู่ไหม — หลุดแล้วตัวเลขกับสัญลักษณ์ที่ค้างอยู่เป็นเทา
void ct_weather_ui_set_connected(bool connected);
