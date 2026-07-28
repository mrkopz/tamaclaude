#include "ct_props.h"

#include <math.h>

#include "layout.h"

// สีหรี่ลงเป็นเทาเข้มเมื่อ BLE หลุด — สัญญาณเดียวกับที่ใช้กับลำตัว
static uint16_t c(bool connected, uint16_t color)
{
    return connected ? color : CT_COL_GRAY_DARK;
}

// สี่เหลี่ยมกลวง หนา t
static void ring(ct_rects_t *o, float x, float y, float s, float t, uint16_t col)
{
    ct_rects_add(o, x, y, s, t, col);
    ct_rects_add(o, x, y + s - t, s, t, col);
    ct_rects_add(o, x, y + t, t, s - 2 * t, col);
    ct_rects_add(o, x + s - t, y + t, t, s - 2 * t, col);
}

// แว่นขยาย — Read/Grep/Glob (ส่ายซ้ายขวาเหมือนกำลังไล่อ่าน)
static void magnifier(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_ACCENT);
    float x = CT_HAND_X + sinf(phase * (float)M_PI * 2.0f) * 0.35f;
    float y = CT_HAND_Y, s = 4.5f, t = 0.8f;
    // เลนส์ปล่อยโปร่ง — ถ้าถมสีจะเพี้ยนเวลาพื้นหลังเปลี่ยน
    ring(o, x, y, s, t, col);
    for (int i = 0; i < 2; i++) {  // ด้ามจับทแยงลงขวา
        ct_rects_add(o, x + s - 0.3f + i * 0.65f, y + s - 0.3f + i * 0.65f, 0.9f, 0.9f, col);
    }
}

// ดินสอ — Edit/Write (ขยับเป็นจังหวะเขียน)
static void pencil(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_ACCENT);
    uint16_t tip = c(connected, CT_COL_TEXT);
    float wob = sinf(phase * (float)M_PI * 4.0f) * 0.4f;
    float x = CT_HAND_X, y = CT_HAND_Y + wob;
    for (int i = 0; i < 4; i++) {
        ct_rects_add(o, x + 3.5f - i * 0.95f, y + i * 1.02f, 1.6f, 1.25f, col);
    }
    ct_rects_add(o, x - 0.1f, y + 4.06f, 1.4f, 1.4f, tip);  // ปลายไส้
}

// ค้อน — Bash (ทุบเป็นจังหวะ มีประกายตอนกระแทก)
static void hammer(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_ACCENT);
    uint16_t head = c(connected, CT_COL_TEXT_DIM);
    bool down = fmodf(phase, 0.5f) < 0.25f;
    float x = CT_HAND_X + 0.3f;
    float y = CT_HAND_Y + (down ? 2.0f : 0.0f);
    ct_rects_add(o, x + 1.7f, y + 1.8f, 1.3f, 3.4f, col);  // ด้าม
    ct_rects_add(o, x, y, 4.8f, 2.0f, head);               // หัวค้อน
    if (down) {
        ct_rects_add(o, x - 0.9f, y + 4.4f, 1.0f, 1.0f, CT_COL_ACCENT);
        ct_rects_add(o, x + 4.7f, y + 4.4f, 1.0f, 1.0f, CT_COL_ACCENT);
    }
}

// ลูกโลก — WebSearch/WebFetch
// ทรงกลมตัน ไม่ใช่สี่เหลี่ยมกลวง เพราะจะไปซ้ำกับแว่นขยายจนแยกไม่ออกที่ 12px
static void globe(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_ACCENT);
    uint16_t dark = c(connected, CT_COL_INK);
    float x = CT_HAND_X, y = CT_HAND_Y, s = 5.0f;
    float cut = s / 6.0f;  // ความลึกของมุมที่ตัดออก ทำให้อ่านเป็นทรงกลม
    ct_rects_add(o, x + cut, y, s - 2 * cut, cut, col);
    ct_rects_add(o, x, y + cut, s, s - 2 * cut, col);
    ct_rects_add(o, x + cut, y + s - cut, s - 2 * cut, cut, col);

    float spin = fmodf(phase, 1.0f) * s;
    const float cont[2][4] = {{0.0f, 1.4f, 1.2f, 1.0f}, {2.3f, 2.9f, 1.5f, 0.9f}};
    for (int i = 0; i < 2; i++) {
        float px = x + fmodf(cont[i][0] + spin, s);
        // ตัดชิ้นที่จะล้นขอบลูกโลกทิ้ง แทนที่จะให้ยื่นออกมา
        if (px + cont[i][2] <= x + s) {
            ct_rects_add(o, px, y + cont[i][1], cont[i][2], cont[i][3], dark);
        }
    }
}

// จุดคิด — thinking (ไล่สว่างทีละจุด)
static void dots(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_TEXT);
    int lit = (int)(phase * 3.0f) % 3;
    for (int i = 0; i < 3; i++) {
        float s = (i == lit) ? 2.2f : 1.4f;
        float cx = CT_HEAD_CX + (i - 1) * 3.4f;
        float cy = -2.7f - ((i == lit) ? 0.5f : 0.0f);
        ct_rects_add(o, cx - s / 2, cy - s / 2, s, s, col);
    }
}

// อัศเจรีย์แดง — alert (พัง/ต้องดูด่วน)
static void bang(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_ALERT);
    float pulse = 0.4f * (0.5f + 0.5f * sinf(phase * (float)M_PI * 4.0f));
    float x = CT_HEAD_CX - 0.95f, y = -5.1f - pulse;
    ct_rects_add(o, x, y, 1.9f, 3.0f, col);
    ct_rects_add(o, x, y + 3.8f, 1.9f, 1.3f, col);
}

// เครื่องหมายคำถามเหลือง — waiting (รอคำตอบ)
// ต้องแยกจาก bang ให้ขาด: "รอคุณ" ไม่ใช่ "พัง" — ต่างทั้งรูปทรงและสี
static void query(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_ACCENT);
    float u = 0.74f;
    float pulse = 0.35f * (0.5f + 0.5f * sinf(phase * (float)M_PI * 2.0f));
    float x = CT_HEAD_CX - 2 * u, y = -5.2f - pulse;
    const int cells[8][2] = {{1, 0}, {2, 0}, {0, 1}, {3, 1}, {3, 2}, {2, 3}, {2, 4}, {2, 6}};
    for (int i = 0; i < 8; i++) {
        ct_rects_add(o, x + cells[i][0] * u, y + cells[i][1] * u, u, u, col);
    }
}

// Zzz — sleeping (ลอยขึ้นทแยงจากมุมบนขวาของหัว)
static void zzz(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_TEXT_DIM);
    for (int i = 0; i < 3; i++) {
        float t = fmodf(phase + i / 3.0f, 1.0f);
        float s = 1.0f + i * 0.55f;
        ct_rects_add(o, 12.4f + i * 2.0f + t * 1.0f, -1.1f - i * 1.5f - t * 1.3f, s, s, col);
    }
}

// ประกาย — celebrate (กระพริบสลับรอบตัว)
static void sparkle(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_ACCENT);
    const float spots[5][2] = {
        {1.6f, -2.6f}, {14.4f, -2.0f}, {CT_HEAD_CX, -4.0f}, {1.2f, 2.5f}, {18.6f, 5.2f}};
    for (int i = 0; i < 5; i++) {
        if (((int)(phase * 4.0f) + i) % 2) continue;
        float x = spots[i][0], y = spots[i][1];
        ct_rects_add(o, x - 0.45f, y - 1.5f, 0.9f, 3.0f, col);
        ct_rects_add(o, x - 1.5f, y - 0.45f, 3.0f, 0.9f, col);
    }
}

// มาสคอตจิ๋วสองตัวลอยเหนือหัว — conducting (มี subagent กำลังทำงานให้)
// เป็นรูปย่อของมาสคอตเอง ไม่ใช่สัญลักษณ์นามธรรม และกระเด้งคนละเฟส
static void crew(ct_rects_t *o, float phase, bool connected)
{
    uint16_t body = c(connected, CT_COL_CLAY);
    uint16_t ink = c(connected, CT_COL_INK);
    for (int i = 0; i < 2; i++) {
        float bob = sinf(phase * (float)M_PI * 2.0f + i * (float)M_PI) * 0.5f;
        float x = CT_HEAD_CX + (i * 2 - 1) * 4.0f - 1.7f;
        float y = -4.8f + bob;
        ct_rects_add(o, x, y, 3.4f, 2.4f, body);                // ลำตัว
        ct_rects_add(o, x - 0.5f, y + 0.7f, 0.5f, 0.9f, body);  // แขนซ้าย
        ct_rects_add(o, x + 3.4f, y + 0.7f, 0.5f, 0.9f, body);  // แขนขวา
        ct_rects_add(o, x + 0.35f, y + 2.4f, 0.8f, 0.9f, body);  // ขาซ้าย
        ct_rects_add(o, x + 2.25f, y + 2.4f, 0.8f, 0.9f, body);  // ขาขวา
        ct_rects_add(o, x + 0.6f, y + 0.7f, 0.8f, 0.8f, ink);   // ตา
        ct_rects_add(o, x + 2.0f, y + 0.7f, 0.8f, 0.8f, ink);
    }
}

// เสาสัญญาณ — LSP/MCP (คลื่นแผ่ออกสองข้างเป็นจังหวะ)
// "คุยกับบริการอื่นอยู่" ไม่ใช่ "ค้นหา" จึงไม่ใช้ลูกโลกซ้ำ ทุกชิ้นตั้งฉากจึงอ่านออกที่ 3 px/unit
static void beacon(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_ACCENT);
    uint16_t post = c(connected, CT_COL_TEXT_DIM);
    // กึ่งกลางพื้นที่ prop — คลื่นแผ่ได้เท่ากันสองข้าง
    float cx = (CT_HAND_X + CT_BOX_X1) / 2.0f;
    ct_rects_add(o, cx - 0.5f, CT_HAND_Y + 1.4f, 1.0f, 3.8f, post);  // เสา
    ct_rects_add(o, cx - 1.8f, CT_HAND_Y + 5.2f, 3.6f, 0.9f, post);  // ฐาน
    ct_rects_add(o, cx - 0.9f, CT_HAND_Y, 1.8f, 1.4f, col);          // ไฟยอดเสา

    for (int i = 0; i < 2; i++) {
        float t = fmodf(phase + i * 0.5f, 1.0f);
        // ดับก่อนถึงขอบ อ่านเป็นคลื่นจางหาย ไม่ใช่คลื่นโดนตัด
        if (t > 0.8f) continue;
        float spread = 1.0f + t * 1.4f;  // กว้างสุด 2.4 — พอดีขอบ CT_BOX_X1
        float rise = t * 0.7f;
        ct_rects_add(o, cx - spread - 0.7f, CT_HAND_Y - rise, 0.7f, 1.9f, col);
        ct_rects_add(o, cx + spread, CT_HAND_Y - rise, 0.7f, 1.9f, col);
    }
}

void ct_prop_build(ct_rects_t *out, ct_prop_t prop, float phase, bool connected)
{
    switch (prop) {
        case CT_PROP_MAGNIFIER: magnifier(out, phase, connected); break;
        case CT_PROP_PENCIL: pencil(out, phase, connected); break;
        case CT_PROP_HAMMER: hammer(out, phase, connected); break;
        case CT_PROP_GLOBE: globe(out, phase, connected); break;
        case CT_PROP_DOTS: dots(out, phase, connected); break;
        case CT_PROP_BANG: bang(out, phase, connected); break;
        case CT_PROP_QUERY: query(out, phase, connected); break;
        case CT_PROP_ZZZ: zzz(out, phase, connected); break;
        case CT_PROP_SPARKLE: sparkle(out, phase, connected); break;
        case CT_PROP_CREW: crew(out, phase, connected); break;
        case CT_PROP_BEACON: beacon(out, phase, connected); break;
        case CT_PROP_NONE:
        default: break;
    }
}
