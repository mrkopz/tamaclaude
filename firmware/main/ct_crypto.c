#include "ct_crypto.h"

#include <string.h>

#include "cJSON.h"

bool ct_crypto_parse(const char *json, int len, ct_crypto_t *out)
{
    cJSON *root = cJSON_ParseWithLength(json, len);
    if (!root) return false;

    const cJSON *list = cJSON_GetObjectItem(root, "c");
    if (!cJSON_IsArray(list)) {
        cJSON_Delete(root);
        return false;
    }

    ct_crypto_t tmp;
    memset(&tmp, 0, sizeof(tmp));

    const cJSON *item = NULL;
    cJSON_ArrayForEach(item, list) {
        if (tmp.count >= CT_CRYPTO_ROWS) break;  // Mac บังคับเพดานแล้ว นี่คือด่านสุดท้าย
        const cJSON *sym = cJSON_GetObjectItem(item, "s");
        const cJSON *price = cJSON_GetObjectItem(item, "p");
        const cJSON *change = cJSON_GetObjectItem(item, "d");
        // แถวที่ขาดอะไรไปคือแถวที่วาดไม่ได้ — ราคาที่ไม่มีสัญลักษณ์กำกับคือตัวเลขที่ไม่มี
        // ใครรู้ว่าของอะไร ส่วนสัญลักษณ์ที่ไม่มีราคาคือแถวว่างที่อ่านว่าอุปกรณ์พัง
        if (!cJSON_IsString(sym) || !sym->valuestring) continue;
        if (!cJSON_IsString(price) || !price->valuestring) continue;
        if (!cJSON_IsNumber(change)) continue;
        ct_crypto_row_t *row = &tmp.rows[tmp.count++];
        strncpy(row->sym, sym->valuestring, sizeof(row->sym) - 1);
        strncpy(row->price, price->valuestring, sizeof(row->price) - 1);
        row->change = change->valueint;
    }
    // watchlist ว่างไม่ใช่เฟรม — Mac ไม่ส่งเฟรมที่ไม่มีแถวเลย (มันหยุดตั้งแต่ไม่มีอะไร
    // ให้ถาม) ถ้ามาถึงจริงแปลว่าเฟรมพัง และของเดิมบนจอยังจริงกว่า
    if (tmp.count == 0) {
        cJSON_Delete(root);
        return false;
    }

    const cJSON *age = cJSON_GetObjectItem(root, "a");
    if (cJSON_IsNumber(age) && age->valueint > 0) tmp.age = age->valueint;

    cJSON_Delete(root);
    *out = tmp;  // เขียนทับทีเดียวตอนท้าย — JSON พังกลางทางต้องไม่ทิ้งภาพครึ่งๆ
    return true;
}

void ct_crypto_tick(ct_crypto_t *c, int secs)
{
    // ไม่มีเพดาน: อายุที่หยุดนับคืออายุที่โกหก และราคาที่ค้างมาสองวันต้องพูดแบบนั้นได้
    c->age += secs;
}
