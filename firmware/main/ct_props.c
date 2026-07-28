#include "ct_props.h"

#include <math.h>

#include "layout.h"

// สีหรี่ลงเป็นเทาเข้มเมื่อ BLE หลุด — สัญญาณเดียวกับที่ใช้กับลำตัว
static uint16_t c(bool connected, uint16_t color)
{
    return connected ? color : CT_COL_GRAY_DARK;
}

// วงกลมกลวง หนา t — ตัดมุมทั้งสี่เป็นแนวทแยง จึงอ่านเป็นวงกลมไม่ใช่กรอบสี่เหลี่ยม
static void ring_round(ct_rects_t *o, float x, float y, float s, float t, uint16_t col)
{
    float k = s / 4.0f;  // ความยาวมุมที่ตัดออก
    ct_rects_add(o, x + k, y, s - 2 * k, t, col);          // บน
    ct_rects_add(o, x + k, y + s - t, s - 2 * k, t, col);  // ล่าง
    ct_rects_add(o, x, y + k, t, s - 2 * k, col);          // ซ้าย
    ct_rects_add(o, x + s - t, y + k, t, s - 2 * k, col);  // ขวา
    const float corner[4][2] = {{k - t, k - t}, {s - k, k - t}, {k - t, s - k}, {s - k, s - k}};
    for (int i = 0; i < 4; i++) {  // ชิ้นเชื่อมมุม
        ct_rects_add(o, x + corner[i][0], y + corner[i][1], t, t, col);
    }
}

// มุมบนซ้ายของเลนส์ในเฟรมนี้ — กระจกกับขอบต้องอ่านค่าเดียวกัน ไม่งั้นเลื่อนหลุดกัน
static void lens_box(float phase, float *ox, float *oy)
{
    // ขยับลงอย่างเดียว — เลนส์สูงกว่าหัวอยู่แล้ว ถ้าลอยขึ้นอีกจะฉีกซิลลูเอ็ตจนอ่านไม่ออก
    float lift = fabsf(sinf(phase * (float)M_PI * 2.0f)) * 0.4f;
    *ox = CT_EYE_R + CT_EYE_S / 2.0f - CT_LENS_S / 2.0f;  // จัดวงให้ล้อมตาข้างขวาพอดี
    *oy = CT_EYE_Y + CT_EYE_S / 2.0f - CT_LENS_S / 2.0f + lift;
}

// กระจกในเลนส์ — วาดก่อนตา (ct_mascot.c เป็นคนเรียก) ตาจึงทับอยู่บนกระจก
// ถ้าวาดพร้อมขอบเลนส์ซึ่งอยู่หน้าตา กระจกจะบังตาที่เป็นพระเอกของท่านี้
void ct_prop_magnifier_glass(ct_rects_t *o, float phase, bool connected)
{
    // ตอนหลุดการเชื่อมต่อใช้สีเดียวกับลำตัว = กระจกหายไปเลย ไม่ใช่หรี่เป็นเทาเข้ม
    // เพราะเทาเข้มจะกลืนกับสีตาจนมองไม่เห็นตาในวง
    uint16_t col = connected ? CT_COL_GLASS : CT_COL_GRAY;
    float x, y;
    lens_box(phase, &x, &y);
    float s = CT_LENS_S - 2 * CT_LENS_T;  // เต็มรูในวงแหวนพอดี
    x += CT_LENS_T;
    y += CT_LENS_T;
    // มุมที่ตัดต้องพอดีบันไดด้านในของวงแหวน ไม่เหลือรูและไม่ล้น
    float k = CT_LENS_S / 4.0f - CT_LENS_T;
    ct_rects_add(o, x + k, y, s - 2 * k, k, col);
    ct_rects_add(o, x, y + k, s, s - 2 * k, col);
    ct_rects_add(o, x + k, y + s - k, s - 2 * k, k, col);
}

// แว่นขยาย — Read/Grep/Glob
// ยกมาส่องที่ตาข้างขวาแทนที่จะถือห้อยข้างตัว: ท่านี้อ่านออกทันทีว่า "กำลังอ่าน"
// ในวงมีตาที่ถูกขยายบนกระจกฟ้าอ่อน (ct_mascot.c วาดให้ก่อนหน้านี้) ด้ามลากไปจบที่แขนขวา
// กรอบเป็นฟ้าเทา เข้มกว่ากระจกพอให้เห็นเป็นวงแหวน แต่ไม่ดังกว่าตาที่เป็นพระเอกของท่านี้
// วงใหญ่กว่าหัวและล้นขึ้นไปด้านบน — ตั้งใจ ให้อ่านออกแต่ไกลว่าเป็นแว่นขยาย ไม่ใช่แว่นตา
static void magnifier(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_STEEL);
    float s = CT_LENS_S, t = CT_LENS_T;
    float x, y;
    lens_box(phase, &x, &y);
    ring_round(o, x, y, s, t, col);
    // ด้ามลากลงขวาไปจบที่มือ — ต้องพ้นขอบแขน (16.5) ถึงจะอ่านออกว่าถืออยู่
    for (int i = 0; i < 3; i++) {
        ct_rects_add(o, x + s - 0.5f + i * 1.15f, y + s * 0.70f + i * 0.55f, 1.5f, 1.05f, col);
    }
    // แสงสะท้อนบนกระจกเป็นขีดสองขีดมุมบนซ้าย — วางในช่องว่างระหว่างตากับขอบ ไม่ทับตา
    uint16_t glint = c(connected, CT_COL_OUTLINE);
    ct_rects_add(o, x + 1.05f, y + 2.5f, 0.9f, 1.5f, glint);
    ct_rects_add(o, x + 2.3f, y + 1.05f, 1.5f, 0.9f, glint);
}

// โลโก้แอปเปิลบนฝา — เขียนเป็นภาพ ASCII ตรงๆ อ่านง่ายกว่าลิสต์ตัวเลข
// ช่องละ 0.25 unit = 1 พิกเซลพอดีที่ unit_px=4 จึงคมและไม่เพี้ยนจากการปัดเศษ
// ใบเอียงขึ้นขวา ตัวลูกเป็นก้อนกลมทึบ ขอบขวาเว้าสองแถว = รอยกัด ก้นแยกสองพู
// ตั้งใจให้รายละเอียดน้อย: ที่ 12 px ต่อโลโก้ รอยหยักย่อยๆ กลายเป็นขอบเละ ไม่ใช่รูปทรง
#define APPLE_PX 0.25f
#define APPLE_W 10
#define APPLE_H 11
static const char *const APPLE_ART[APPLE_H] = {
    ".....##...",
    "....##....",
    "..######..",
    ".########.",
    "##########",
    "########..",
    "########..",
    "##########",
    ".########.",
    "..######..",
    "..##..##..",
};

// แปลง APPLE_ART เป็น rect ทีละช่วงพิกเซลติดกัน ไม่ใช่ทีละช่อง
static void apple(ct_rects_t *o, float x, float y, uint16_t color)
{
    for (int row = 0; row < APPLE_H; row++) {
        const char *line = APPLE_ART[row];
        for (int col = 0; col < APPLE_W;) {
            if (line[col] != '#') {
                col++;
                continue;
            }
            int run = 1;
            while (col + run < APPLE_W && line[col + run] == '#') run++;
            ct_rects_add(o, x + col * APPLE_PX, y + row * APPLE_PX, run * APPLE_PX, APPLE_PX,
                         color);
            col += run;
        }
    }
}

// แล็ปท็อป — Edit/Write (นั่งพิมพ์ โดยจอหันหลังให้เรา)
// วางทับลำตัวแทนที่จะถือข้างตัวเหมือน prop อื่น: ท่า "พิมพ์โค้ดอยู่" อ่านออกจากการมีจอ
// คั่นระหว่างเรากับตัวมัน จอหันหลัง = ฝาเป็นแผ่นเหล็กทึบล้วน ไม่มีอะไรสว่างอยู่บนนั้น
// สิ่งเดียวที่บอกว่าจออีกด้านเปิดอยู่คือแสงที่รอดขึ้นมาเลาะขอบบนของฝาไปโดนหน้ามัน
// (จุดสว่างกลางฝาจะอ่านกลับเป็นจอหันเข้าหาเราทันที จึงห้ามมี)
// ส่วนสายตาที่กวาดซ้ายไปขวากับแขนที่ขยับสลับข้าง อยู่ใน ct_mascot.c
static void laptop(ct_rects_t *o, float phase, bool connected)
{
    // ฝาเป็นแผ่นเหล็กทึบ ไม่ใช่สีดำ — สี่เหลี่ยมดำใหญ่ๆ อ่านเป็น "จอที่เปิดอยู่" เสมอ
    // ต่อให้ไม่มีอะไรสว่างบนนั้น ขอบสีหมึกบางๆ ทำหน้าที่ตัดฝาออกจากลำตัวแทน
    uint16_t shell = c(connected, CT_COL_STEEL);
    uint16_t rim = c(connected, CT_COL_INK);
    // แสงที่รอดขอบจอ — ตอนหลุดการเชื่อมต่อใช้เทาอ่อน ไม่ใช่เทาเข้ม ไม่งั้นกลืนไปกับฝา
    uint16_t spill = connected ? CT_COL_GLASS : CT_COL_GRAY;

    // ขอบฝา — ตัดฝากับลำตัวสีดินออกจากกัน
    ct_rects_add(o, CT_LID_X, CT_LID_Y, CT_LID_W, CT_LID_H, rim);
    ct_rects_add(o, CT_LID_X + 0.5f, CT_LID_Y + 0.5f, CT_LID_W - 1.0f, CT_LID_H - 1.0f,
                 shell);  // หลังฝา (ทึบล้วน)
    // ฐาน — เข้มกว่าฝา จึงไม่อ่านเป็นก้อนเดียวกัน
    ct_rects_add(o, CT_LAP_X, CT_LAP_Y, CT_LAP_W, CT_LAP_H, rim);
    // สันบนของฐาน = ระนาบคีย์บอร์ดที่รับแสง
    ct_rects_add(o, CT_LAP_X, CT_LAP_Y, CT_LAP_W, 0.5f, shell);

    // แสงจอรอดขึ้นมาเหนือฝา หายใจเข้าออกช้าๆ — ขีดบางๆ ขีดเดียว ไม่ใช่ก้อนสว่าง
    // ต้องอยู่ *เหนือ* ขอบฝา ไม่ใช่บนฝา ไม่งั้นกลับไปอ่านเป็นเนื้อจออีก
    float w = CT_LID_W - 4.0f + 0.8f * sinf(phase * (float)M_PI * 2.0f);
    ct_rects_add(o, CT_LID_X + (CT_LID_W - w) / 2.0f, CT_LID_Y - 0.5f, w, 0.5f, spill);

    // โลโก้แอปเปิลกลางฝา — รูปทรงชัดเจน ไม่ใช่ก้อนสว่างสี่เหลี่ยม จึงไม่พลิกกลับไป
    // อ่านเป็นเนื้อจอ วาดทีละแถวเป็นแท่งยาว ไม่ใช่ทีละพิกเซล จะได้ไม่กิน rect budget
    uint16_t mark = c(connected, CT_COL_OUTLINE);
    apple(o, CT_LID_X + (CT_LID_W - APPLE_W * APPLE_PX) / 2.0f,
          CT_LID_Y + (CT_LID_H - APPLE_H * APPLE_PX) / 2.0f, mark);
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
        case CT_PROP_LAPTOP: laptop(out, phase, connected); break;
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
