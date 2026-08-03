#include "ct_calendar.h"

#include <string.h>

#include "cJSON.h"

// คัดลอกข้อความโดยไม่ตัดกลางลำดับ UTF-8
//
// `strncpy` ที่ชนเพดานพอดีจะทิ้งไบต์ต่อของตัวอักษรตัวสุดท้ายไว้ครึ่งตัว แล้ว LVGL วาด
// กล่องสี่เหลี่ยมท้ายชื่อ — อาการเดียวกับที่ `Text.sanitize` ฝั่ง Mac มีไว้กัน ปกติ Mac
// ตัดมาให้พอดีอยู่แล้ว นี่คือด่านสุดท้าย ไม่ใช่ด่านเดียว
static void copy_utf8(char *dst, size_t cap, const char *src)
{
    size_t n = strlen(src);
    if (n > cap - 1) {
        n = cap - 1;
        // ถอยจนพ้นไบต์ต่อ (10xxxxxx) — ตัวอักษรที่ไม่ครบตัวหายไปทั้งตัว ดีกว่าเหลือครึ่ง
        while (n > 0 && (src[n] & 0xC0) == 0x80) n--;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
}

bool ct_calendar_parse(const char *json, int len, ct_calendar_t *out)
{
    cJSON *root = cJSON_ParseWithLength(json, len);
    if (!root) return false;

    // สภาพของหน้าเป็นสิ่งที่ *ต้อง* มี ต่างจากลิสต์นัดซึ่งว่างได้: เฟรมที่ไม่บอกสภาพคือ
    // เฟรมที่ทำให้จอว่างโดยไม่มีใครรู้ว่าเพราะสัปดาห์ว่างหรือเพราะยังไม่ได้สิทธิ์
    const cJSON *state = cJSON_GetObjectItem(root, "p");
    if (!cJSON_IsNumber(state) || state->valueint < CT_CAL_OK
        || state->valueint > CT_CAL_NOT_ASKED) {
        cJSON_Delete(root);
        return false;
    }

    ct_calendar_t tmp;
    memset(&tmp, 0, sizeof(tmp));
    tmp.state = (ct_calendar_state_t)state->valueint;

    const cJSON *list = cJSON_GetObjectItem(root, "e");
    if (list && !cJSON_IsArray(list)) {
        cJSON_Delete(root);
        return false;
    }
    const cJSON *item = NULL;
    cJSON_ArrayForEach(item, list) {
        if (tmp.count >= CT_CALENDAR_ROWS) break;  // Mac บังคับเพดานแล้ว นี่คือด่านสุดท้าย
        const cJSON *day = cJSON_GetObjectItem(item, "d");
        const cJSON *time = cJSON_GetObjectItem(item, "t");
        const cJSON *title = cJSON_GetObjectItem(item, "n");
        // นัดที่ขาดอะไรไปคือแถวที่วาดไม่ได้ — ชื่อที่ไม่มีเวลากำกับคือสิ่งที่ผู้ใช้ต้องไป
        // เปิดปฏิทินจริงเพื่ออ่านอยู่ดี ส่วนเวลาที่ไม่มีชื่อคือแถวว่างที่อ่านว่าอุปกรณ์พัง
        if (!cJSON_IsString(day) || !day->valuestring) continue;
        if (!cJSON_IsString(time) || !time->valuestring) continue;
        if (!cJSON_IsString(title) || !title->valuestring) continue;
        ct_calendar_row_t *row = &tmp.rows[tmp.count++];
        copy_utf8(row->day, sizeof(row->day), day->valuestring);
        copy_utf8(row->time, sizeof(row->time), time->valuestring);
        copy_utf8(row->title, sizeof(row->title), title->valuestring);
    }
    // สภาพ `ok` ที่ไม่มีนัดสักรายการเป็นไปไม่ได้ — Mac เปลี่ยนมันเป็น `empty` ตั้งแต่
    // ตอนสร้างเฟรม ถ้ามาถึงจริงแปลว่าเฟรมพัง และของเดิมบนจอยังจริงกว่า
    if (tmp.state == CT_CAL_OK && tmp.count == 0) {
        cJSON_Delete(root);
        return false;
    }

    const cJSON *age = cJSON_GetObjectItem(root, "a");
    if (cJSON_IsNumber(age) && age->valueint > 0) tmp.age = age->valueint;

    cJSON_Delete(root);
    *out = tmp;  // เขียนทับทีเดียวตอนท้าย — JSON พังกลางทางต้องไม่ทิ้งภาพครึ่งๆ
    return true;
}

void ct_calendar_tick(ct_calendar_t *c, int secs)
{
    // ไม่มีเพดาน: อายุที่หยุดนับคืออายุที่โกหก (กติกาเดียวกับทุกหน้า)
    c->age += secs;
}
