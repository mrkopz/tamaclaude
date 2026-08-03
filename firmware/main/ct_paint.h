// วาด rect list ลง layer — ตัวแทนของ draw_rects ใน tools/gen/render.py
//
// แยกออกมาจาก ct_ui.c ตอนมีหน้าที่สอง: มาสคอตจิ๋วบนหน้าอากาศคือ rect list ชุดเดิม
// ที่ย่อแล้ว การก๊อปลูปวาดไปไว้อีกไฟล์แปลว่ากฎการปัดเศษกับการ clamp รัศมีจะดริฟต์
// ออกจากกัน แล้วสองหน้าบนจอเดียวกันจะวาดสี่เหลี่ยมคนละแบบ
#pragma once

#include "ct_rects.h"
#include "lvgl.h"

// ox/oy = พิกัดพิกเซลของจุด (0,0) ในตาราง unit · px = กี่พิกเซลต่อหนึ่ง unit
void ct_paint_rects(lv_layer_t *layer, const ct_rects_t *rects, float ox, float oy, float px);
