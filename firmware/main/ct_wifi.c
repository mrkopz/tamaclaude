#include "ct_wifi.h"

#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs.h"

static const char *TAG = "wifi";

// เก็บทีละก้อนต่อเครือข่าย ไม่ใช่ key แยก ssid/psk — การเขียนสองครั้งเปิดช่องให้
// ไฟดับคาแล้วเหลือ ssid ที่ไม่มีรหัส ซึ่งลูปต่อไม่ติดตลอดโดยไม่มีใครบอกว่าทำไม
typedef struct {
    char ssid[CT_WIFI_SSID_CAP];
    char psk[CT_WIFI_PSK_CAP];
} net_t;

#define NVS_NS "tamawifi"

// ตัดให้พอดีปลายทางแบบเงียบๆ — ปลายทางบางที่ (`wifi_config_t`) สั้นกว่าที่เราเก็บอยู่
// หนึ่งไบต์เพราะไม่ได้เผื่อ NUL และ `snprintf` จะเตือนเป็น error ทุกครั้งที่เห็นแบบนั้น
static void copy_str(char *dst, size_t cap, const char *src)
{
    if (cap == 0) return;
    if (!src) {
        dst[0] = '\0';
        return;
    }
    // คัดลอกทีละไบต์ ไม่ใช่ strnlen+memcpy — ต้นทางบางตัวเป็นสตริงคงที่ที่สั้นกว่า cap
    // แล้ว GCC จะฟ้อง stringop-overread ทั้งที่โค้ดถูก
    size_t i = 0;
    while (i + 1 < cap && src[i] != '\0') {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
}

static ct_wifi_cbs_t s_cbs;
static net_t s_nets[CT_WIFI_MAX_NETS];
static int s_net_count;

static ct_wifi_state_t s_state = CT_WIFI_OFF;
static char s_ssid[CT_WIFI_SSID_CAP];
static char s_ip[16];
static char s_err[24];

// สแกนมีสองความหมายและผลลัพธ์ไปคนละที่ ตัวแปรเดียวจึงต้องบอกว่ารอบนี้ใครสั่ง
typedef enum { SCAN_NONE, SCAN_REPORT, SCAN_PICK } scan_mode_t;
static scan_mode_t s_scan = SCAN_NONE;
static bool s_started;

// ผู้ใช้ขอรายชื่อไว้แล้วแต่วิทยุยังไม่ว่าง — จำไว้เพื่อสแกนต่อทันทีที่ว่าง
//
// ไม่มีตัวนี้แล้วคำขอจะหล่นหายเงียบๆ ตอนที่บอร์ดกำลังจับมือกับ AP อยู่ ซึ่งเป็นเวลาส่วน
// ใหญ่พอดีเมื่อรหัสผิด: ฝั่ง Mac ค้างที่สปินเนอร์กับลิสต์เปล่า และปุ่ม Rescan ดูเหมือนตาย
static bool s_want_report;

// วงที่ผู้ใช้เพิ่งสั่งต่อ ซึ่ง *ยังไม่พิสูจน์ว่ารหัสถูก* จึงยังไม่อยู่ใน s_nets และยังไม่ลง NVS
//
// รหัสที่ยังไม่เคยต่อติดไม่ใช่ของที่ควรจำ: พิมพ์ผิดครั้งเดียวแล้วเหลือวงที่ต่อไม่ได้ค้างใน
// ลิสต์ตลอดไปคือสิ่งที่ผู้ใช้ต้องมาไล่ลบเอง · และเมื่อวงเดียวกันเคยมีรหัสที่ใช้ได้อยู่แล้ว
// การพิมพ์ผิดจะไม่ทำลายของเดิม — พอรอบนี้ล้ม บอร์ดกลับไปใช้รหัสที่จำไว้ได้ทันที
// เขียนลง NVS ที่เดียวเท่านั้น: ตอนได้ IP
static net_t s_try;
static bool s_have_try;

// รหัสในรอบนี้ผู้ใช้เพิ่งพิมพ์มา และยังไม่เคยต่อติดด้วยรหัสนี้เลย
//
// มีไว้กันการกล่าวหาผิดตัว: รหัสที่ *เคยต่อติดแล้ว* ไม่มีวันกลายเป็นรหัสผิด การล้ม
// ระหว่างจับมือของมันคือเรื่องของวิทยุ (สลับ AP, ช่องสัญญาณชนกัน, AP ตอบช้า) ซึ่ง
// เกิดประจำตอนย้ายจากวงหนึ่งไปอีกวง · ไม่มีตัวนี้แล้วการกลับไปหาวงเดิมจะขึ้นว่า
// "wrong password" ทั้งที่รหัสที่จำไว้ถูกต้อง แล้วบอร์ดก็หยุดลองไปอีกหนึ่งนาที
static bool s_try_unproven;

// เราสั่งตัดสายเองแล้วรอใบแจ้ง — ใบที่ตามมาเป็นของสายเก่า ไม่ใช่ความล้มเหลวที่ต้องรายงาน
//
// `esp_wifi_connect` ตัวที่สองคืน ESP_ERR_WIFI_CONN เงียบๆ ถ้าสายเก่ายังไม่ขาด และการ
// สั่งตัดแล้วต่อทันทีในบรรทัดถัดไปก็ไม่ช่วย: ใบแจ้ง STA_DISCONNECTED มาถึง *หลัง* เรา
// ตั้งสถานะเป็น CONNECTING แล้ว ผลคือหน้าตั้งค่าค้างที่ "disconnected" ทั้งที่การต่อ
// รอบใหม่กำลังไปได้ดี · งานที่ต้องทำต่อจึงอยู่ในตัวจัดการใบแจ้ง ไม่ใช่บรรทัดถัดไป
static bool s_join_after_drop;
static bool s_drop_for_scan;

static esp_timer_handle_t s_retry;
static int s_backoff_ms = 1000;

static void report(void)
{
    if (s_cbs.on_status) s_cbs.on_status(s_state, s_ssid, s_ip, s_err);
}

static void set_state(ct_wifi_state_t st, const char *err)
{
    s_state = st;
    copy_str(s_err, sizeof(s_err), err);
    if (st != CT_WIFI_CONNECTED) s_ip[0] = '\0';
    report();
}

// --- เครือข่ายที่จำไว้ ---------------------------------------------------------
static void nets_load(void)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READONLY, &h) != ESP_OK) return;
    for (int i = 0; i < CT_WIFI_MAX_NETS; i++) {
        char key[8];
        snprintf(key, sizeof(key), "n%d", i);
        size_t len = sizeof(net_t);
        net_t n;
        if (nvs_get_blob(h, key, &n, &len) != ESP_OK || len != sizeof(net_t)) continue;
        if (n.ssid[0] == '\0') continue;
        s_nets[s_net_count++] = n;
    }
    nvs_close(h);
    ESP_LOGI(TAG, "%d saved network(s)", s_net_count);
}

static void nets_store(void)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READWRITE, &h) != ESP_OK) return;
    for (int i = 0; i < CT_WIFI_MAX_NETS; i++) {
        char key[8];
        snprintf(key, sizeof(key), "n%d", i);
        if (i < s_net_count) {
            nvs_set_blob(h, key, &s_nets[i], sizeof(net_t));
        } else {
            nvs_erase_key(h, key);
        }
    }
    nvs_commit(h);
    nvs_close(h);
}

static net_t *net_find(const char *ssid)
{
    for (int i = 0; i < s_net_count; i++) {
        if (strcmp(s_nets[i].ssid, ssid) == 0) return &s_nets[i];
    }
    return NULL;
}

// `psk == NULL` คือ "ไม่แตะรหัสที่จำไว้" ไม่ใช่ "รหัสคือค่าว่าง" — ฝั่ง Mac ส่งแบบนี้
// (ไม่มีคีย์ `psk` ในคำสั่ง join) ตอนผู้ใช้กลับไปต่อวงเดิมโดยไม่พิมพ์อะไร ดู
// `WiFiCommand.join` ใน host/Sources/TamaCore/WiFiProvisioning.swift · เขียนทับด้วย ""
// ตรงนี้เท่ากับลบรหัสที่ใช้ได้อยู่ทิ้ง แล้วรอบต่อไปล้มด้วย auth fail
static void net_remember(const char *ssid, const char *psk)
{
    net_t *existing = net_find(ssid);
    if (existing) {
        if (psk) copy_str(existing->psk, sizeof(existing->psk), psk);
    } else {
        // เต็มแล้วให้ตัวเก่าสุดหลุดออก ไม่ใช่ปฏิเสธตัวใหม่ — ผู้ใช้ที่กำลังยืนอยู่หน้า
        // เครือข่ายใหม่ต้องการตัวนี้ ส่วนตัวที่จำไว้ตั้งแต่ปีที่แล้วไม่มีใครคิดถึง
        if (s_net_count == CT_WIFI_MAX_NETS) {
            memmove(&s_nets[0], &s_nets[1], sizeof(net_t) * (CT_WIFI_MAX_NETS - 1));
            s_net_count--;
        }
        net_t *n = &s_nets[s_net_count++];
        copy_str(n->ssid, sizeof(n->ssid), ssid);
        copy_str(n->psk, sizeof(n->psk), psk);
    }
    nets_store();
}

// --- การต่อ --------------------------------------------------------------------
static void connect_to(const net_t *n)
{
    wifi_config_t cfg = {0};
    copy_str((char *)cfg.sta.ssid, sizeof(cfg.sta.ssid), n->ssid);
    copy_str((char *)cfg.sta.password, sizeof(cfg.sta.password), n->psk);
    cfg.sta.scan_method = WIFI_ALL_CHANNEL_SCAN;
    esp_wifi_set_config(WIFI_IF_STA, &cfg);
    copy_str(s_ssid, sizeof(s_ssid), n->ssid);
    set_state(CT_WIFI_CONNECTING, NULL);
    esp_wifi_connect();
}

static void search(void)
{
    // รอบสแกนที่ค้างอยู่เป็นของใครก็ได้ — ทับโหมดมันคือทำให้ผลไปผิดที่
    if (s_scan != SCAN_NONE) return;
    // การต่อที่กำลังเดินอยู่ต้องได้จบเรื่องของมันเอง: สแกนระหว่างจับมือทำให้ทั้งสองอย่างล้ม
    // และรอบนี้มาจากนาฬิกาที่ตั้งไว้เป็นตาข่ายรับ ไม่ใช่จากใครที่กำลังรอคำตอบ
    if (s_state == CT_WIFI_CONNECTING || s_state == CT_WIFI_CONNECTED) return;
    // วงที่ผู้ใช้เพิ่งสั่งยังไม่อยู่ในลิสต์ที่จำไว้ การเลือกจากผลสแกนจึงมองไม่เห็นมัน
    if (s_have_try) {
        connect_to(&s_try);
        return;
    }
    if (s_net_count == 0) {
        set_state(CT_WIFI_OFF, NULL);
        return;
    }
    // สแกนก่อนต่อเสมอ แม้จะจำเครือข่ายเดียว — เลือกตัวที่แรงที่สุดในบรรดาที่จำไว้
    // ได้ และรู้ได้ว่า "ไม่เจอเลย" ต่างจาก "รหัสผิด" ซึ่งผู้ใช้ต้องแก้คนละอย่าง
    s_scan = SCAN_PICK;
    if (esp_wifi_scan_start(NULL, false) != ESP_OK) {
        s_scan = SCAN_NONE;
        set_state(CT_WIFI_FAILED, "scan busy");
    }
}

static void retry_cb(void *arg) { search(); }

// ตั้งนาฬิกาลองใหม่ที่ระยะปัจจุบัน โดยไม่ถ่างระยะ — ใช้ตอนกลับมาจากงานที่ผู้ใช้แทรก
static void resume_search(void)
{
    esp_timer_stop(s_retry);
    esp_timer_start_once(s_retry, (uint64_t)s_backoff_ms * 1000);
}

static void schedule_retry(void)
{
    // เพดาน 60 วิ ไม่ใช่การเลิกล้ม: บอร์ดอยู่บนโต๊ะทั้งวัน เครือข่ายที่หายไปตอนเช้า
    // กลับมาตอนบ่ายได้ และไม่มีใครมากดปุ่มให้ลองใหม่
    if (s_backoff_ms < 60000) s_backoff_ms *= 2;
    resume_search();
}

// เริ่มรอบสแกนที่ผลจะถูกส่งกลับไปให้ Mac — เรียกได้เฉพาะตอนวิทยุว่างแล้ว
//
// ทุกทางออกของฟังก์ชันนี้ต้องจบด้วย `on_ap_end` เสมอเมื่อสแกนไม่ได้เกิดขึ้นจริง:
// ฝั่ง Mac ถือ "กำลังสแกน" ไว้จนกว่าจะเห็นเครื่องหมายจบ ไม่มีตัวจับเวลาของตัวเอง
static void start_report_scan(void)
{
    if (!s_want_report) return;
    s_scan = SCAN_REPORT;
    if (esp_wifi_scan_start(NULL, false) == ESP_OK) return;
    s_scan = SCAN_NONE;
    s_want_report = false;
    if (s_cbs.on_ap_end) s_cbs.on_ap_end();
    if (s_state != CT_WIFI_CONNECTED) resume_search();
}

// --- เหตุการณ์จาก esp_wifi -----------------------------------------------------

// แปลเหตุผลของการหลุดเป็นคำที่หน้าตั้งค่าเอาไปตัดสินใจต่อได้
//
// `esp_wifi` ไม่มีค่าเดียวที่แปลว่า "รหัสผิด": AP คนละยี่ห้อคืน 15 (4WAY_HANDSHAKE_TIMEOUT),
// 202 (AUTH_FAIL), 205 (CONNECTION_FAIL) หรือแม้แต่ 1 (UNSPECIFIED) ให้กับรหัสผิดตัว
// เดียวกัน · การไล่แจกแจงเลขจึงพลาดเสมอ สิ่งที่แยกได้แน่คือ **จังหวะ**: ล้มทั้งที่ยังไม่เคย
// ต่อติดในรอบนี้ = เรื่องของตัวตน (ผู้ใช้ต้องพิมพ์ใหม่) · หลุดหลังจากต่อติดแล้ว = เรื่องของ
// วิทยุ (รอเดี๋ยวก็กลับ) · เหลือแค่กลุ่ม "ไม่เจอ AP" ที่ต้องดักด้วยเลขจริงๆ
//
// สตริงที่คืนออกไปเป็นสัญญากับ `WiFiStatus.needsPassword` ใน
// host/Sources/TamaCore/WiFiProvisioning.swift — สองไฟล์นี้อ้างถึงกันตอนรันไม่ได้
static const char *why(uint8_t reason, bool was_connected, bool unproven)
{
    switch (reason) {
    case WIFI_REASON_NO_AP_FOUND:
    case WIFI_REASON_NO_AP_FOUND_IN_AUTHMODE_THRESHOLD:
    case WIFI_REASON_NO_AP_FOUND_IN_RSSI_THRESHOLD:
        return "not in range";
    case WIFI_REASON_BEACON_TIMEOUT:
        return was_connected ? "signal lost" : "not in range";
    default:
        // 210 (ไม่เจอ AP ที่ security ตรงกัน) ตกมาที่นี่โดยตั้งใจ: มันคือความไม่ตรงกัน
        // ของรหัส/โหมดเข้ารหัส ซึ่งผู้ใช้แก้ที่ช่องรหัสผ่านช่องเดียวกัน
        if (was_connected) return "disconnected";
        return unproven ? "wrong password" : "could not connect";
    }
}
static void emit_scan_results(void)
{
    uint16_t num = 0;
    esp_wifi_scan_get_ap_num(&num);
    if (num > 20) num = 20;  // จอเดียวไม่มีใครไล่อ่านเกินยี่สิบ และ RAM ไม่ได้มีเหลือ
    wifi_ap_record_t *recs = calloc(num, sizeof(wifi_ap_record_t));
    if (!recs) {
        esp_wifi_clear_ap_list();
        if (s_cbs.on_ap_end) s_cbs.on_ap_end();
        return;
    }
    esp_wifi_scan_get_ap_records(&num, recs);

    for (int i = 0; i < num; i++) {
        const char *ssid = (const char *)recs[i].ssid;
        if (ssid[0] == '\0') continue;
        // AP เดียวกันโผล่หลายช่อง/หลายย่าน — รายการที่มีชื่อซ้ำอ่านเหมือนบอร์ดพัง
        bool dup = false;
        for (int j = 0; j < i && !dup; j++) {
            dup = strcmp(ssid, (const char *)recs[j].ssid) == 0;
        }
        if (dup) continue;
        if (s_cbs.on_ap) {
            s_cbs.on_ap(ssid, recs[i].rssi, recs[i].authmode != WIFI_AUTH_OPEN);
        }
        // notification ไม่มี flow control ฝั่งเรา ปล่อยรัวจนคิวของ NimBLE ล้นแล้ว
        // รายการจะขาดหายเป็นช่วงๆ ซึ่งดูเหมือนสัญญาณอ่อน ไม่ใช่บั๊ก
        vTaskDelay(pdMS_TO_TICKS(20));
    }
    free(recs);
    if (s_cbs.on_ap_end) s_cbs.on_ap_end();
}

static void pick_from_scan(void)
{
    uint16_t num = 0;
    esp_wifi_scan_get_ap_num(&num);
    if (num > 30) num = 30;
    wifi_ap_record_t *recs = calloc(num, sizeof(wifi_ap_record_t));
    if (!recs) {
        esp_wifi_clear_ap_list();
        schedule_retry();
        return;
    }
    esp_wifi_scan_get_ap_records(&num, recs);

    const net_t *best = NULL;
    int8_t best_rssi = -127;
    for (int i = 0; i < num; i++) {
        net_t *n = net_find((const char *)recs[i].ssid);
        if (n && recs[i].rssi > best_rssi) {
            best = n;
            best_rssi = recs[i].rssi;
        }
    }
    free(recs);

    if (!best) {
        set_state(CT_WIFI_FAILED, "not in range");
        schedule_retry();
        return;
    }
    connect_to(best);
}

static void wifi_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        s_started = true;
        search();
        return;
    }
    if (base == WIFI_EVENT && id == WIFI_EVENT_SCAN_DONE) {
        scan_mode_t mode = s_scan;
        s_scan = SCAN_NONE;
        if (mode == SCAN_REPORT) {
            s_want_report = false;
            emit_scan_results();
            // รอบนี้เป็นของผู้ใช้ ลูปต่อเองจึงไม่ได้เดินระหว่างนั้น — ปลุกมันกลับมาเอง
            // ไม่งั้นบอร์ดที่ยังไม่ได้ต่อจะนิ่งไปตลอดจนกว่าจะมีคนกด Rescan อีกครั้ง
            if (s_state != CT_WIFI_CONNECTED) resume_search();
        } else if (mode == SCAN_PICK) {
            pick_from_scan();
        } else {
            esp_wifi_clear_ap_list();
        }
        return;
    }
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        const wifi_event_sta_disconnected_t *d = data;
        // เลข reason ไม่โผล่ที่อื่นเลย และมันคือสิ่งเดียวที่บอกได้ว่ารอบนี้ล้มเพราะอะไร —
        // การรายงานบั๊กเรื่อง WiFi ที่ไม่มีเลขนี้แนบมาคือการเดา
        ESP_LOGW(TAG, "disconnected from %s reason=%d", s_ssid, (int)d->reason);

        // ใบของสายเก่าที่เราสั่งตัดเอง: งานที่ค้างอยู่มาก่อน และ `d->reason` เป็นเรื่อง
        // ของการต่อครั้งก่อน ไม่ใช่ครั้งนี้ จึงต้องไม่ถูกแปลเป็นข้อความให้ผู้ใช้อ่าน
        if (s_join_after_drop) {
            s_join_after_drop = false;
            connect_to(&s_try);
            return;
        }
        if (s_drop_for_scan) {
            s_drop_for_scan = false;
            set_state(CT_WIFI_FAILED, "stopped to scan");
            start_report_scan();
            return;
        }

        const char *err = why(d->reason, s_state == CT_WIFI_CONNECTED,
                              s_have_try && s_try_unproven);
        set_state(CT_WIFI_FAILED, err);

        // รหัสที่ผิดลองอีกกี่รอบก็ผิดเท่าเดิม — ทิ้งตัวที่ผู้ใช้เพิ่งพิมพ์ทันที ไม่เขียนลง
        // NVS และไม่วนต่อ · เวลาหนึ่งนาทีก่อนกลับไปหาวงที่จำไว้คือเวลาที่ผู้ใช้ได้อ่าน
        // ข้อความและพิมพ์ใหม่ ก่อนที่การต่อรอบถัดไปจะทับมันทิ้ง
        if (s_have_try && strcmp(err, "wrong password") == 0) {
            s_have_try = false;
            s_backoff_ms = 60000;
            resume_search();
            return;
        }

        // การตัดสายอาจมาจาก `ct_wifi_scan` เองที่ต้องการวิทยุคืน — คำขอของผู้ใช้มาก่อน
        if (s_want_report) {
            start_report_scan();
        } else {
            schedule_retry();
        }
        return;
    }
    if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        const ip_event_got_ip_t *e = data;
        snprintf(s_ip, sizeof(s_ip), IPSTR, IP2STR(&e->ip_info.ip));
        // ที่เดียวที่รหัสผ่านลง NVS: ตอนนี้เท่านั้นที่รู้ว่ามันใช้ได้จริง
        if (s_have_try) {
            net_remember(s_try.ssid, s_try.psk);
            s_have_try = false;
        }
        s_backoff_ms = 1000;
        set_state(CT_WIFI_CONNECTED, NULL);
        ESP_LOGI(TAG, "connected to %s as %s", s_ssid, s_ip);
        return;
    }
}

// --- API ----------------------------------------------------------------------
void ct_wifi_init(const ct_wifi_cbs_t *cbs)
{
    s_cbs = *cbs;
    nets_load();

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                                        wifi_event, NULL, NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                                        wifi_event, NULL, NULL));
    // เก็บ credential เองใน NVS namespace ของเรา ไม่ให้ esp_wifi เขียนทับซ้อน —
    // ต้นทางเดียวเท่านั้นที่รู้ว่าเราจำอะไรไว้ ไม่งั้น "ลืมเครือข่าย" จะลืมไม่หมด
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    // วิทยุตัวเดียวกันแบ่งกับ BLE อยู่ — โหมดประหยัดไฟทำให้ค่าหน่วงพุ่งเป็นวินาที
    // ซึ่งกินเวลาที่เราตั้งใจประหยัดตอน BLE หลุดไปทั้งหมด
    ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));

    const esp_timer_create_args_t args = {.callback = retry_cb, .name = "wifi_retry"};
    ESP_ERROR_CHECK(esp_timer_create(&args, &s_retry));

    ESP_ERROR_CHECK(esp_wifi_start());
}

void ct_wifi_scan(void)
{
    if (!s_started) {
        if (s_cbs.on_ap_end) s_cbs.on_ap_end();
        return;
    }
    s_want_report = true;

    // ลูปต่อเองต้องหลบให้คนที่ยืนอยู่หน้าเครื่อง: รหัสผิดทำให้บอร์ดวนจับมือกับ AP เดิม
    // ไม่รู้จบ และ `esp_wifi_scan_start` คืน ESP_ERR_WIFI_STATE ตลอดช่วงนั้น ผลคือปุ่ม
    // Rescan ที่กดแล้วไม่เกิดอะไรเลย ซึ่งเป็นทางเดียวที่ผู้ใช้จะแก้รหัสได้
    esp_timer_stop(s_retry);

    // รอบที่ลูปต่อเองสั่งไว้เป็นการกวาดคลื่นชุดเดียวกัน — ยึดผลของมันมาส่งต่อ ดีกว่า
    // ทิ้งคำขอของผู้ใช้แล้วให้ Mac ค้างที่สปินเนอร์
    if (s_scan == SCAN_PICK) {
        s_scan = SCAN_REPORT;
        return;
    }
    if (s_scan == SCAN_REPORT) return;  // ของผู้ใช้เองที่ยังวิ่งอยู่

    // ตัดการจับมือที่ค้างอยู่แล้วสแกนต่อใน STA_DISCONNECTED — `esp_wifi_disconnect`
    // ไม่ได้คืนวิทยุทันทีที่มันคืนค่า
    // เฉพาะเมื่อคำสั่งตัดสายรับไปจริง ไม่งั้นจะไม่มี STA_DISCONNECTED มาปลุกใคร แล้วทั้ง
    // ลูปต่อเองกับรายชื่อของผู้ใช้จะค้างด้วยกันทั้งคู่ (นาฬิกาลองใหม่ก็ถูกหยุดไปแล้ว)
    if (s_state == CT_WIFI_CONNECTING) {
        s_drop_for_scan = true;
        if (esp_wifi_disconnect() == ESP_OK) return;
        s_drop_for_scan = false;
    }
    start_report_scan();
}

void ct_wifi_join(const char *ssid, const char *psk)
{
    if (!ssid || ssid[0] == '\0') return;

    const net_t *known = net_find(ssid);
    copy_str(s_try.ssid, sizeof(s_try.ssid), ssid);
    // ไม่ส่งรหัสมา = ใช้ของที่จำไว้ · ไม่เคยจำก็คือวงเปิด
    copy_str(s_try.psk, sizeof(s_try.psk), psk ? psk : (known ? known->psk : ""));
    // รหัสที่ตรงกับของที่จำไว้คือรหัสที่เคยต่อติดแล้ว ไม่ว่ามันจะมาทางไหน
    s_try_unproven = !known || strcmp(known->psk, s_try.psk) != 0;
    s_have_try = true;
    s_backoff_ms = 1000;
    esp_timer_stop(s_retry);
    // ผู้ใช้เลือกวงแล้ว รายชื่อจึงหมดหน้าที่ — ปิดสปินเนอร์ฝั่ง Mac ด้วยตัวเอง เพราะ
    // การต่อจะกินวิทยุจนรอบสแกนที่ค้างอยู่ไม่มีวันรายงานผล
    if (s_want_report) {
        s_want_report = false;
        s_scan = SCAN_NONE;
        if (s_cbs.on_ap_end) s_cbs.on_ap_end();
    }
    // ตัดของเดิมก่อน แล้วต่อใน STA_DISCONNECTED — วิทยุยังไม่คืนตอน `esp_wifi_disconnect`
    // คืนค่า · นาฬิกาลองใหม่เดินต่อเป็นตาข่ายรับ เผื่อใบแจ้งไม่มาเลย ไม่งั้นบอร์ดจะนิ่ง
    // ค้างที่ CONNECTING โดยไม่มีอะไรมาปลุก
    if (s_state == CT_WIFI_CONNECTED || s_state == CT_WIFI_CONNECTING) {
        s_join_after_drop = true;
        resume_search();
        if (esp_wifi_disconnect() == ESP_OK) return;
        s_join_after_drop = false;
    }
    connect_to(&s_try);
}

void ct_wifi_forget(const char *ssid)
{
    // ตัวที่กำลังลองอยู่ก็ต้องหลุดไปด้วย ไม่งั้นลูปต่อเองจะพากลับไปหาวงที่เพิ่งถูกลืม
    if (s_have_try && strcmp(s_try.ssid, ssid) == 0) s_have_try = false;
    net_t *n = net_find(ssid);
    if (!n) return;
    int idx = (int)(n - s_nets);
    memmove(&s_nets[idx], &s_nets[idx + 1], sizeof(net_t) * (s_net_count - idx - 1));
    s_net_count--;
    nets_store();
    if (strcmp(s_ssid, ssid) == 0) {
        esp_wifi_disconnect();
        s_ssid[0] = '\0';
        s_backoff_ms = 1000;
        search();
    }
}

int ct_wifi_saved(char out[][CT_WIFI_SSID_CAP], int cap)
{
    int n = s_net_count < cap ? s_net_count : cap;
    for (int i = 0; i < n; i++) copy_str(out[i], CT_WIFI_SSID_CAP, s_nets[i].ssid);
    return n;
}

ct_wifi_state_t ct_wifi_state(void) { return s_state; }

const char *ct_wifi_ip(void) { return s_ip; }

void ct_wifi_report(void) { report(); }

bool ct_wifi_command(const char *json, int len)
{
    cJSON *root = cJSON_ParseWithLength(json, len);
    if (!root) return false;
    const cJSON *cmd = cJSON_GetObjectItem(root, "c");
    if (!cJSON_IsString(cmd) || !cmd->valuestring) {
        cJSON_Delete(root);
        return false;
    }
    const char *c = cmd->valuestring;
    const cJSON *ssid = cJSON_GetObjectItem(root, "ssid");
    const cJSON *psk = cJSON_GetObjectItem(root, "psk");

    if (strcmp(c, "scan") == 0) {
        ct_wifi_scan();
    } else if (strcmp(c, "join") == 0 && cJSON_IsString(ssid)) {
        ct_wifi_join(ssid->valuestring, cJSON_IsString(psk) ? psk->valuestring : NULL);
    } else if (strcmp(c, "forget") == 0 && cJSON_IsString(ssid)) {
        ct_wifi_forget(ssid->valuestring);
    } else if (strcmp(c, "status") == 0) {
        ct_wifi_report();
    }
    cJSON_Delete(root);
    return true;
}
