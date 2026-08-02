// WiFi station — ทางเดินที่สองของ snapshot เมื่อ BLE ไกลเกินไป (DESIGN.md)
//
// บอร์ดไม่เคยยิง claude.ai เอง: `sessionKey` เป็น credential เต็มบัญชี และแฟลชบนบอร์ด
// ดัมพ์ออกได้ด้วยสาย USB WiFi จึงมีไว้คุยกับ Mac ผ่าน LAN เท่านั้น
//
// คำสั่งทั้งหมดเข้ามาทาง config characteristic (`...0003`) ซึ่งบังคับเข้ารหัสไว้ —
// รหัส WiFi เดินทางผ่านอากาศตรงนั้น รายงานกลับออกทาง event characteristic (`...0004`)
#pragma once

#include <stdbool.h>
#include <stdint.h>

// จำนวนเครือข่ายที่จำได้ — โต๊ะทำงานกับบ้านกับที่ที่ไปประจำ ยังไม่ถึงห้า
#define CT_WIFI_MAX_NETS 5
#define CT_WIFI_SSID_CAP 33
#define CT_WIFI_PSK_CAP 65

typedef enum {
    CT_WIFI_OFF = 0,      // ยังไม่มีเครือข่ายที่จำไว้เลย
    CT_WIFI_CONNECTING,   // กำลังสแกน/ต่อ/รอรอบถัดไปตาม backoff
    CT_WIFI_CONNECTED,    // ได้ IP แล้ว
    CT_WIFI_FAILED,       // รอบล่าสุดล้ม (รหัสผิด หรือหาไม่เจอ) — ยังลองต่อเรื่อยๆ
} ct_wifi_state_t;

typedef struct {
    // ทั้งหมดถูกเรียกจาก event task ของ esp_event ห้ามแตะ LVGL ตรงนั้น
    void (*on_ap)(const char *ssid, int8_t rssi, bool secured);
    void (*on_ap_end)(void);
    void (*on_status)(ct_wifi_state_t state, const char *ssid, const char *ip,
                      const char *err);
} ct_wifi_cbs_t;

// ต้องเรียกหลัง nvs_flash_init — เครือข่ายที่จำไว้ถูกอ่านตรงนี้ และถ้ามีจะเริ่มต่อทันที
void ct_wifi_init(const ct_wifi_cbs_t *cbs);

// สแกนแล้วรายงานผ่าน on_ap ทีละตัว ปิดท้ายด้วย on_ap_end
void ct_wifi_scan(void);

// จำเครือข่ายแล้วต่อทันที — psk เป็น NULL หรือสตริงว่างคือเครือข่ายเปิด
void ct_wifi_join(const char *ssid, const char *psk);

// ลืมเครือข่าย ถ้ากำลังใช้ตัวนั้นอยู่จะตัดแล้วไปหาตัวอื่นที่จำไว้
void ct_wifi_forget(const char *ssid);

// รายชื่อที่จำไว้ ตามลำดับที่เก็บ — คืนจำนวนที่เขียนลง out
int ct_wifi_saved(char out[][CT_WIFI_SSID_CAP], int cap);

ct_wifi_state_t ct_wifi_state(void);

// IP ปัจจุบัน สตริงว่างเมื่อยังไม่ได้ต่อ — Mac ใช้กรอกเองเมื่อ mDNS ไม่ผ่าน AP
const char *ct_wifi_ip(void);

// สั่งให้ยิง on_status ซ้ำหนึ่งครั้ง — ใช้ตอน Mac เพิ่งเปิดหน้าตั้งค่า
void ct_wifi_report(void);

// คำสั่ง JSON จาก config characteristic ที่ขึ้นต้นด้วยคีย์ "c" — คืน false ถ้าไม่ใช่ของเรา
bool ct_wifi_command(const char *json, int len);
