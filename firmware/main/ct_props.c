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
    float x = CT_HAND_X + sinf(phase * (float)M_PI * 2.0f) * 0.45f;
    float y = CT_HAND_Y, s = 4.0f, t = 0.7f;
    // เลนส์ปล่อยโปร่ง — ถ้าถมสีจะเพี้ยนเวลาพื้นหลังเปลี่ยน
    ring(o, x, y, s, t, col);
    for (int i = 0; i < 2; i++) {  // ด้ามจับทแยงลงขวา
        ct_rects_add(o, x + s - 0.25f + i * 0.7f, y + s - 0.25f + i * 0.7f, 0.9f, 0.9f, col);
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
        ct_rects_add(o, x + 2.9f - i * 0.78f, y + i * 0.86f, 1.3f, 1.05f, col);
    }
    ct_rects_add(o, x - 0.1f, y + 3.44f, 1.15f, 1.15f, tip);  // ปลายไส้
}

// ค้อน — Bash (ทุบเป็นจังหวะ มีประกายตอนกระแทก)
static void hammer(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_ACCENT);
    uint16_t head = c(connected, CT_COL_TEXT_DIM);
    bool down = fmodf(phase, 0.5f) < 0.25f;
    float x = CT_HAND_X + 0.3f;
    float y = CT_HAND_Y + (down ? 2.2f : 0.0f);
    ct_rects_add(o, x + 1.4f, y + 1.2f, 1.0f, 2.9f, col);  // ด้าม
    ct_rects_add(o, x, y, 3.8f, 1.4f, head);               // หัวค้อน
    if (down) {
        ct_rects_add(o, x - 0.8f, y + 4.3f, 0.8f, 0.8f, CT_COL_ACCENT);
        ct_rects_add(o, x + 3.8f, y + 4.3f, 0.8f, 0.8f, CT_COL_ACCENT);
    }
}

// ลูกโลก — WebSearch/WebFetch
// ทรงกลมตัน ไม่ใช่สี่เหลี่ยมกลวง เพราะจะไปซ้ำกับแว่นขยายจนแยกไม่ออกที่ 12px
static void globe(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_ACCENT);
    uint16_t dark = c(connected, CT_COL_INK);
    float x = CT_HAND_X, y = CT_HAND_Y, s = 4.2f;
    float cut = s / 6.0f;  // ความลึกของมุมที่ตัดออก ทำให้อ่านเป็นทรงกลม
    ct_rects_add(o, x + cut, y, s - 2 * cut, cut, col);
    ct_rects_add(o, x, y + cut, s, s - 2 * cut, col);
    ct_rects_add(o, x + cut, y + s - cut, s - 2 * cut, cut, col);

    float spin = fmodf(phase, 1.0f) * s;
    const float cont[2][4] = {{0.0f, 1.2f, 1.0f, 0.8f}, {1.9f, 2.4f, 1.3f, 0.7f}};
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
        float s = (i == lit) ? 1.7f : 1.05f;
        float cx = CT_HEAD_CX + (i - 1) * 2.8f;
        float cy = -2.5f - ((i == lit) ? 0.5f : 0.0f);
        ct_rects_add(o, cx - s / 2, cy - s / 2, s, s, col);
    }
}

// อัศเจรีย์แดง — alert (พัง/ต้องดูด่วน)
static void bang(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_ALERT);
    float pulse = 0.4f * (0.5f + 0.5f * sinf(phase * (float)M_PI * 4.0f));
    float x = CT_HEAD_CX - 0.75f, y = -4.7f - pulse;
    ct_rects_add(o, x, y, 1.5f, 2.6f, col);
    ct_rects_add(o, x, y + 3.3f, 1.5f, 1.2f, col);
}

// เครื่องหมายคำถามเหลือง — waiting (รอคำตอบ)
// ต้องแยกจาก bang ให้ขาด: "รอคุณ" ไม่ใช่ "พัง" — ต่างทั้งรูปทรงและสี
static void query(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_ACCENT);
    float u = 0.62f;
    float pulse = 0.35f * (0.5f + 0.5f * sinf(phase * (float)M_PI * 2.0f));
    float x = CT_HEAD_CX - 2 * u, y = -4.9f - pulse;
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
        float s = 0.7f + i * 0.4f;
        ct_rects_add(o, 12.0f + i * 1.8f + t * 0.9f, -0.7f - i * 1.3f - t * 1.2f, s, s, col);
    }
}

// ประกาย — celebrate (กระพริบสลับรอบตัว)
static void sparkle(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_ACCENT);
    const float spots[5][2] = {
        {1.6f, -2.3f}, {14.0f, -1.8f}, {CT_HEAD_CX, -3.9f}, {0.1f, 2.5f}, {17.5f, 5.0f}};
    for (int i = 0; i < 5; i++) {
        if (((int)(phase * 4.0f) + i) % 2) continue;
        float x = spots[i][0], y = spots[i][1];
        ct_rects_add(o, x - 0.4f, y - 1.2f, 0.8f, 2.4f, col);
        ct_rects_add(o, x - 1.2f, y - 0.4f, 2.4f, 0.8f, col);
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
        case CT_PROP_NONE:
        default: break;
    }
}
