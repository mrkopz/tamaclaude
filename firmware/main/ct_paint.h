// วาด rect list ลง layer — ตัวแทนของ draw_rects ใน tools/gen/render.py
//
// แยกออกมาจาก ct_ui.c ตอนมีหน้าที่สอง: มาสคอตจิ๋วบนหน้าอื่นคือ rect list ชุดเดิม
// ที่ย่อแล้ว การก๊อปลูปวาดไปไว้อีกไฟล์แปลว่ากฎการปัดเศษกับการ clamp รัศมีจะดริฟต์
// ออกจากกัน แล้วสองหน้าบนจอเดียวกันจะวาดสี่เหลี่ยมคนละแบบ
#pragma once

#include "ct_rects.h"
#include "lvgl.h"

// ox/oy = พิกัดพิกเซลของจุด (0,0) ในตาราง unit · px = กี่พิกเซลต่อหนึ่ง unit
void ct_paint_rects(lv_layer_t *layer, const ct_rects_t *rects, float ox, float oy, float px);

// สี่เหลี่ยมใบเดียว — กฎการปัดเศษกับ clamp รัศมีชุดเดียวกับ ct_paint_rects
void ct_paint_rect(lv_layer_t *layer, const ct_rect_t *r, float ox, float oy, float px);

// สามเหลี่ยมขอบนุ่ม — LVGL วาดด้วย mask line ซึ่ง anti-alias ให้ ต่างจาก rect list ที่
// ขอบเฉียงทำได้แค่บันได (ตัวคู่ขนานฝั่ง Python คือ `draw_poly` ใน tools/gen/render.py)
void ct_paint_triangle(lv_layer_t *layer, const ct_pt_t p[3], uint16_t color, float ox,
                       float oy, float px);
