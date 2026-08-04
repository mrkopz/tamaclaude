#include "ct_stocks.h"

#include <string.h>

#include "cJSON.h"

bool ct_stocks_parse(const char *json, int len, ct_stocks_t *out)
{
    cJSON *root = cJSON_ParseWithLength(json, len);
    if (!root) return false;

    const cJSON *list = cJSON_GetObjectItem(root, "c");
    if (!cJSON_IsArray(list)) {
        cJSON_Delete(root);
        return false;
    }

    ct_stocks_t tmp;
    memset(&tmp, 0, sizeof(tmp));

    const cJSON *item = NULL;
    cJSON_ArrayForEach(item, list) {
        if (tmp.count >= CT_STOCKS_ROWS) break;  // Mac บังคับเพดานแล้ว นี่คือด่านสุดท้าย
        const cJSON *sym = cJSON_GetObjectItem(item, "s");
        const cJSON *price = cJSON_GetObjectItem(item, "p");
        const cJSON *change = cJSON_GetObjectItem(item, "d");
        // แถวที่ขาดสัญลักษณ์หรือราคาคือแถวที่วาดไม่ได้ — ราคาที่ไม่มีสัญลักษณ์กำกับคือ
        // ตัวเลขที่ไม่มีใครรู้ว่าของอะไร ส่วนเปอร์เซ็นต์ที่หายไปยังวาดได้ (Mac ทิ้งมันเอง
        // ตอนบีบเฟรม) จึงไม่ใช่เหตุให้ทิ้งทั้งแถว
        if (!cJSON_IsString(sym) || !sym->valuestring) continue;
        if (!cJSON_IsString(price) || !price->valuestring) continue;
        ct_stocks_row_t *row = &tmp.rows[tmp.count++];
        strncpy(row->sym, sym->valuestring, sizeof(row->sym) - 1);
        strncpy(row->price, price->valuestring, sizeof(row->price) - 1);
        row->has_change = cJSON_IsNumber(change);
        row->change = row->has_change ? change->valueint : 0;
    }
    // watchlist ว่างไม่ใช่เฟรม — Mac ไม่ส่งเฟรมที่ไม่มีแถวเลย ถ้ามาถึงจริงแปลว่าเฟรมพัง
    // และของเดิมบนจอยังจริงกว่า
    if (tmp.count == 0) {
        cJSON_Delete(root);
        return false;
    }

    const cJSON *age = cJSON_GetObjectItem(root, "a");
    if (cJSON_IsNumber(age) && age->valueint > 0) tmp.age = age->valueint;
    const cJSON *closed = cJSON_GetObjectItem(root, "k");
    tmp.market_closed = cJSON_IsNumber(closed) && closed->valueint != 0;

    cJSON_Delete(root);
    *out = tmp;  // เขียนทับทีเดียวตอนท้าย — JSON พังกลางทางต้องไม่ทิ้งภาพครึ่งๆ
    return true;
}

void ct_stocks_tick(ct_stocks_t *s, int secs)
{
    // ไม่มีเพดาน: อายุที่หยุดนับคืออายุที่โกหก และราคาที่ค้างมาตั้งแต่ศุกร์ต้องพูดแบบนั้นได้
    s->age += secs;
}
