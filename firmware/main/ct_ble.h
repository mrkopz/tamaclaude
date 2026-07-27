// GATT peripheral — daemon ฝั่ง Mac เป็น central
//
// UUID ต้องตรงกับ host/Sources/TamaCore/BLETransport.swift ทุกตัว
//   service  7A9B0001-4C1E-4B6D-9E2A-1D5C3F0A0001
//   state    ...0002  daemon เขียน snapshot ลงตัวนี้
//   config   ...0003  ความสว่าง อ่าน/เขียนได้
//   event    ...0004  แจ้งกลับ — สงวนไว้ v2
#pragma once

#include <stdbool.h>
#include <stddef.h>

typedef struct {
    // ทั้งสองตัวถูกเรียกจาก NimBLE host task ห้ามแตะ LVGL ตรงนั้น
    void (*on_state)(const char *json, int len);
    void (*on_config)(const char *json, int len);
    void (*on_link)(bool connected);
} ct_ble_cbs_t;

void ct_ble_init(const ct_ble_cbs_t *cbs);
