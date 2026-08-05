#include "ct_weather.h"

#include <string.h>

#include "cJSON.h"
#include "ct_age.h"
#include "layout.h"

// แถบพยากรณ์ — ทั้งชุดหรือไม่มีเลย ไม่มีครึ่งเดียว
//
// ต่างจากตัวเลขหลักตรงที่ *ไม่* ทำให้เฟรมทั้งใบใช้ไม่ได้: หน้าที่มีเลขใหญ่แต่แถบล่างว่าง
// ยังตอบคำถามหลักได้ ส่วนหน้าที่ไม่อัปเดตเลยเพราะบล็อกเสริมเปลี่ยนรูปคือหน้าที่ตายทั้งหน้า
// (ต้องตรงกับ `WeatherFrame.init(from:)` ฝั่ง Swift ซึ่งทิ้งทั้งชุดด้วยเงื่อนไขเดียวกัน)
static void parse_hours(const cJSON *root, ct_weather_t *out)
{
    out->hour_start = -1;
    out->hour_n = 0;

    const cJSON *start = cJSON_GetObjectItem(root, "n");
    const cJSON *temps = cJSON_GetObjectItem(root, "o");
    const cJSON *codes = cJSON_GetObjectItem(root, "c");
    if (!cJSON_IsNumber(start) || !cJSON_IsArray(temps) || !cJSON_IsArray(codes)) return;
    if (start->valueint < 0 || start->valueint > 23) return;

    int n = cJSON_GetArraySize(temps);
    // สองแถวที่ยาวไม่เท่ากันคืออุณหภูมิที่จับคู่กับสัญลักษณ์ผิดช่อง ไม่ใช่แถบที่สั้นลง
    if (n < 1 || n != cJSON_GetArraySize(codes)) return;
    if (n > CT_WEATHER_FC_COLS) n = CT_WEATHER_FC_COLS;

    for (int i = 0; i < n; i++) {
        const cJSON *t = cJSON_GetArrayItem(temps, i);
        const cJSON *c = cJSON_GetArrayItem(codes, i);
        // ออกกลางคัน = hour_n ยังเป็น 0 ไม่มีใครอ่านช่องที่เขียนไปแล้ว
        if (!cJSON_IsNumber(t) || !cJSON_IsNumber(c)) return;
        out->hour_temp[i] = t->valueint;
        out->hour_code[i] = c->valueint;
    }
    out->hour_start = start->valueint;
    out->hour_n = n;
}

bool ct_weather_parse(const char *json, int len, ct_weather_t *out)
{
    cJSON *root = cJSON_ParseWithLength(json, len);
    if (!root) return false;

    ct_weather_t tmp;
    memset(&tmp, 0, sizeof(tmp));
    tmp.unit = 'C';

    const cJSON *place = cJSON_GetObjectItem(root, "p");
    if (cJSON_IsString(place) && place->valuestring) {
        strncpy(tmp.place, place->valuestring, sizeof(tmp.place) - 1);
    }
    const cJSON *temp = cJSON_GetObjectItem(root, "t");
    const cJSON *high = cJSON_GetObjectItem(root, "h");
    const cJSON *low = cJSON_GetObjectItem(root, "l");
    const cJSON *code = cJSON_GetObjectItem(root, "w");
    const cJSON *age = cJSON_GetObjectItem(root, "a");
    const cJSON *unit = cJSON_GetObjectItem(root, "u");

    // ตัวเลขที่ขาดไปแม้ตัวเดียวคือเฟรมที่วาดไม่ได้ — วาดครึ่งใบแล้วเหลือ 0 ค้างอยู่
    // อ่านเป็นค่าจริง ซึ่งเป็นคำโกหกที่แยกจากอากาศหนาวไม่ออก
    if (!cJSON_IsNumber(temp) || !cJSON_IsNumber(high) || !cJSON_IsNumber(low)
        || !cJSON_IsNumber(code)) {
        cJSON_Delete(root);
        return false;
    }
    tmp.temp = temp->valueint;
    tmp.high = high->valueint;
    tmp.low = low->valueint;
    tmp.code = code->valueint;
    if (cJSON_IsNumber(age) && age->valueint > 0) tmp.age = age->valueint;
    if (cJSON_IsString(unit) && unit->valuestring && unit->valuestring[0]) {
        tmp.unit = unit->valuestring[0];
    }
    parse_hours(root, &tmp);

    cJSON_Delete(root);
    *out = tmp;  // เขียนทับทีเดียวตอนท้าย — JSON พังกลางทางต้องไม่ทิ้งภาพครึ่งๆ
    return true;
}

void ct_weather_tick(ct_weather_t *w, int secs)
{
    // ไม่มีเพดาน: อายุที่หยุดนับคืออายุที่โกหก และหน้าจอที่ค้างมาสองวันต้องพูดแบบนั้นได้
    w->age += secs;
}

bool ct_weather_is_stale(const ct_weather_t *w)
{
    return ct_age_is_stale(w->age, CT_WEATHER_REFRESH_S);
}
