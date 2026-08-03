#include "ct_weather.h"

#include <string.h>

#include "cJSON.h"
#include "ct_age.h"
#include "layout.h"

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
