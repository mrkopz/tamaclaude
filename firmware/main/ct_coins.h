// สร้างอัตโนมัติจาก tools/coins/*.svg — ห้ามแก้ไฟล์นี้ด้วยมือ
// แก้ที่ SVG แล้วรัน: python3 tools/export_coins.py

#pragma once

#include "lvgl.h"

#define CT_COINS_COUNT 12
#define CT_COINS_MAX   32
#define CT_COIN_PX_CARD 32
#define CT_COIN_PX_ROW  16

// สัญลักษณ์ที่ไม่มีในตารางได้รูปของ `_default.svg` — ไม่เคยคืน NULL
// เหรียญที่เราไม่รู้จักต้องกินที่เท่ากับเหรียญที่รู้จัก ไม่งั้นคอลัมน์แหว่งเป็นแถวๆ
// ปนกับแถวที่มีรูป ซึ่งเป็นสิ่งเดียวที่คอลัมน์นี้มีไว้กัน
const lv_image_dsc_t *ct_coin_card(const char *sym);
const lv_image_dsc_t *ct_coin_row(const char *sym);
