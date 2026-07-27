// RGB LED บนบอร์ด (active low) — กะพริบตอนมีการเตือนใหม่
#pragma once

#include <stdbool.h>

void ct_led_init(void);

// เริ่มลำดับกะพริบ เรียกซ้ำได้ = เริ่มนับใหม่
void ct_led_flash(void);

// เดินลำดับกะพริบ เรียกจากลูปหลักพร้อมเวลาที่ผ่านไป (ms)
void ct_led_tick(int elapsed_ms);
