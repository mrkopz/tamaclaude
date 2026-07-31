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
    // ด้ามลากลงขวาไปจบที่มือ — ต้องพ้นขอบแขน (16.25) ถึงจะอ่านออกว่าถืออยู่
    for (int i = 0; i < 3; i++) {
        ct_rects_add(o, x + s - 0.5f + i * 1.15f, y + s * 0.70f + i * 0.55f, 1.5f, 1.05f, col);
    }
    // แสงสะท้อนบนกระจกเป็นขีดสองขีดมุมบนซ้าย — วางในช่องว่างระหว่างตากับขอบ ไม่ทับตา
    uint16_t glint = c(connected, CT_COL_OUTLINE);
    ct_rects_add(o, x + 0.75f, y + 2.0f, 0.75f, 1.25f, glint);
    ct_rects_add(o, x + 1.75f, y + 0.75f, 1.25f, 0.75f, glint);
}

// แว่นตาคร่อมตาสองข้าง — วาดหลังตา (ct_mascot.c เป็นคนเรียก) กรอบจึงทับขอบตา
// วงกลวงทั้งสองข้าง จึงยังเห็นสายตาที่กวาดอ่านอยู่ข้างใน ซึ่งเป็นสัญญาณหลักของท่านี้
// ใช้ steel เหมือนกรอบแว่นขยาย ไม่ใช่สีหมึก: กรอบสีหมึกจะเชื่อมกับตาซึ่งเป็นสีหมึก
// เหมือนกันที่ 4 px/unit แล้วอ่านเป็นก้อนดำก้อนเดียว ไม่ใช่ตาที่อยู่ในกรอบ
void ct_prop_glasses(ct_rects_t *o, float eye_l, bool connected)
{
    uint16_t col = c(connected, CT_COL_STEEL);
    float y = CT_EYE_Y + CT_EYE_S / 2.0f - CT_GLS_S / 2.0f;
    float xs[2] = {eye_l + CT_EYE_S / 2.0f - CT_GLS_S / 2.0f,
                   CT_EYE_R + CT_EYE_S / 2.0f - CT_GLS_S / 2.0f};
    for (int i = 0; i < 2; i++) ring_round(o, xs[i], y, CT_GLS_S, CT_GLS_T, col);
    // สะพานจมูกกับขาแว่นอยู่กลางความสูงของวง = ระดับเดียวกับตา จึงอ่านเป็นเส้นเดียวพาดหน้า
    // (เคยวางไว้แถวบนของวงตามแว่นจริง แล้วอ่านเป็นสายคาดหัว ไม่ใช่แว่น)
    float by = y + CT_GLS_S / 2.0f - CT_GLS_T / 2.0f;
    ct_rects_add(o, xs[0] + CT_GLS_S, by, xs[1] - xs[0] - CT_GLS_S, CT_GLS_T, col);
    ct_rects_add(o, xs[0] - CT_GLS_TEMPLE, by, CT_GLS_TEMPLE, CT_GLS_T, col);
    ct_rects_add(o, xs[1] + CT_GLS_S, by, CT_GLS_TEMPLE, CT_GLS_T, col);
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

// ท่าของการทุบในเฟรมนี้ — ค้อน ตัวมาสคอต ชิ้นงาน และประกาย ต้องอ่านค่าเดียวกัน
// ถ้าแต่ละชิ้นคิดจังหวะเอง จะได้ภาพที่ตัวยุบตอนค้อนยังลอย หรือประกายมาก่อนโดน
ct_ham_stage_t ct_prop_hammer_stage(float phase)
{
    if (phase < CT_HAM_T_WINDUP) return CT_HAM_READY;
    if (phase < CT_HAM_T_STRIKE) return CT_HAM_WINDUP;
    if (phase < CT_HAM_T_RECOVER) return CT_HAM_STRIKE;
    return CT_HAM_RECOVER;
}

// แท่นเหล็กกับชิ้นงานร้อน — วาดแยกจาก hammer() เพราะห้ามกระเด้งตามตัวมาสคอต
// ของที่วางอยู่กับพื้นต้องนิ่ง ถ้าเลื่อนตาม dy ของลำตัวจะอ่านเป็นแท่นลอยได้
// (ct_mascot.c จึงเรียกอันนี้แยกโดยไม่ move ตาม dy เหมือน prop ชิ้นอื่น)
void ct_prop_hammer_anvil(ct_rects_t *o, float phase, bool connected)
{
    bool strike = ct_prop_hammer_stage(phase) == CT_HAM_STRIKE;
    // แท่นเป็นเทาสองโทน ไม่ใช่สีหมึก — สีหมึกจมหายไปกับพื้นหลังช่อง เหลือชิ้นงานลอยเดี่ยว
    uint16_t block = c(connected, CT_COL_STEEL);
    uint16_t base = c(connected, CT_COL_TEXT_DIM);
    // ชิ้นงานวาบเป็นเหลืองสว่างในเฟรมที่โดนกระแทก แล้วคืนเป็นแดงร้อน
    uint16_t hot = c(connected, strike ? CT_COL_ACCENT : CT_COL_ALERT);
    float h = strike ? CT_HOT_DOWN_H : CT_HOT_UP_H;
    // ฐานกว้างกว่าบล็อก จึงอ่านเป็นของตั้งอยู่กับพื้น ไม่ใช่ก้อนลอย (จบที่ระดับฝ่าเท้า 12.0)
    ct_rects_add(o, CT_ANVIL_CX - 2.6f, 11.2f, 5.2f, 0.8f, base);
    ct_rects_add(o, CT_ANVIL_CX - 1.9f, CT_ANVIL_TOP, 3.8f, 1.7f, block);  // บล็อกเหล็ก
    // ชิ้นงานร้อน — ยุบตอนโดนทุบ
    ct_rects_add(o, CT_ANVIL_CX - 1.25f, CT_ANVIL_TOP - h, 2.5f, h, hot);
}

// หมวกนิรภัย — พีระมิดขั้นบันได กว้างขึ้นทีละขั้นจนจบที่ปีกที่ยื่นพ้นลำตัวข้างละ 1
// '#' คือด้านที่รับแสง '+' คือริ้วเงา — ริ้วแนวตั้งสลับกันคือสิ่งที่ทำให้หมวกมีสัน
// ไม่ใช่โดมเรียบ และอ่านออกว่าเป็นหมวกนิรภัยตั้งแต่แวบแรก
// ยอดบนสุดเว้าหายไปหนึ่งช่องตรงกลาง — ร่องบนสันหมวกจริง และกันไม่ให้ยอดอ่านเป็นจุกแหลม
#define HAT_ROWS 5
#define HAT_COLS 15
static const char *const HAT_ART[HAT_ROWS] = {
    ".....##.##.....",
    "....+##+##+....",
    "...+##+#+##+...",
    "..++#######++..",
    "+++++++++++++++",
};
#define HAT_W 14.0f  // ปีกยื่นพ้นลำตัว (2..14) ข้างละ 1 — กว้างกว่านี้อ่านเป็นหมวกชาวนา
#define HAT_X0 1.0f
#define HAT_ROW_H 0.96f  // ห้าแถวรวม 4.8 — สูงกว่านี้ยอดหมวกจะโผล่พ้นกรอบวาดตอนตัวกระเด้ง

// แปลง HAT_ART เป็น rect ทีละช่วงสีติดกัน ไม่ใช่ทีละช่อง
static void hat(ct_rects_t *o, uint16_t light, uint16_t dark)
{
    const float u = HAT_W / HAT_COLS;
    for (int row = 0; row < HAT_ROWS; row++) {
        const char *line = HAT_ART[row];
        float y = -HAT_ROWS * HAT_ROW_H + row * HAT_ROW_H;
        for (int col = 0; col < HAT_COLS;) {
            char ch = line[col];
            if (ch == '.') {
                col++;
                continue;
            }
            int run = 1;
            while (col + run < HAT_COLS && line[col + run] == ch) run++;
            ct_rects_add(o, HAT_X0 + col * u, y, run * u, HAT_ROW_H,
                         ch == '#' ? light : dark);
            col += run;
        }
    }
}

// ค้อนในท่าหนึ่ง — สามท่าคีย์ ไม่ใช่การหมุนต่อเนื่อง
// renderer วาดได้แต่สี่เหลี่ยมแกนตั้งฉาก การหมุนจริงจึงทำไม่ได้ ท่าคีย์สามท่า
// (ตั้งพัก / เงื้อทแยงขึ้น / ฟาดทแยงลง) ให้สายตาเติมส่วนที่ขาดเองอยู่แล้ว
static void hammer_tool(ct_rects_t *o, ct_ham_stage_t stage, uint16_t grip, uint16_t head,
                        uint16_t face)
{
    float hx, hy;
    if (stage == CT_HAM_READY || stage == CT_HAM_RECOVER) {
        // ตั้งพักข้างตัว — ด้ามเอียงขวาเป็นสองขั้น ปลายล่างจบในระดับมือ ไม่ลอยห่างจากแขน
        ct_rects_add(o, 16.7f, 2.8f, CT_HAM_GRIP_W, 3.2f, grip);
        ct_rects_add(o, 17.6f, -0.6f, CT_HAM_GRIP_W, 3.6f, grip);
        hx = 16.4f;
        hy = -3.0f;
    } else {
        // ด้ามทแยง 45 องศาจากมือ — ขึ้นตอนเงื้อ ลงตอนฟาด (สะท้อนรอบระดับมือเดียวกัน)
        bool up = stage == CT_HAM_WINDUP;
        float y0 = up ? 4.2f : 3.2f;
        float step = up ? -CT_HAM_STEP : CT_HAM_STEP;
        for (int i = 0; i < CT_HAM_N; i++) {
            ct_rects_add(o, 16.8f + i * CT_HAM_STEP, y0 + i * step, CT_HAM_BLK, CT_HAM_BLK,
                         grip);
        }
        // หัวค้อนต้องคาบปลายด้ามไว้เสมอ ไม่งั้นเห็นเป็นก้อนเทาลอยแยกจากด้าม
        // ตอนฟาด ก้นหัวจบที่ผิวชิ้นงานที่ยุบแล้วพอดี = จุดที่แรงลงจริง
        hx = up ? 18.8f : CT_ANVIL_CX - CT_HAM_HEAD_W / 2.0f;
        hy = up ? -1.0f : CT_ANVIL_TOP - CT_HOT_DOWN_H - CT_HAM_HEAD_H;
    }
    ct_rects_add(o, hx, hy, CT_HAM_HEAD_W, CT_HAM_HEAD_H, head);
    // ครึ่งล่างของหัวเข้ม = หน้าค้อนที่ฟาดลงไป ทำให้ก้อนเทาไม่แบนเป็นก้อนเดียว
    ct_rects_add(o, hx, hy + CT_HAM_HEAD_H / 2.0f, CT_HAM_HEAD_W, CT_HAM_HEAD_H / 2.0f, face);
}

// ประกายกระเด็นจากจุดกระแทก — สามทิศที่ไม่สมมาตรกัน จึงอ่านเป็นเศษที่กระเด็นจริง
// ไม่ใช่เอฟเฟกต์ที่ก๊อปวางสองข้าง
static const float SPARK_DIRS[3][2] = {{2.5f, -3.8f}, {3.1f, -0.6f}, {1.9f, 1.9f}};

// หมวกวิศวกร + ค้อน — Bash (เงื้อแล้วฟาดชิ้นงานบนแท่น หนึ่งครั้งต่อลูป)
// ค้อนแกว่งอย่างเดียวอ่านได้แค่ "ถือของ" — ท่าที่อ่านออกว่ากำลังสั่งงานเครื่องคือครบชุด:
// หมวกบอกว่าเป็นคนคุมงาน ค้อนคือเครื่องมือ แท่นคือสิ่งที่ถูกลงแรง
// น้ำหนักของการกระแทกมาจากจังหวะ (เงื้อค้าง -> ฟาดสองเฟรม -> คืนตัว) ไม่ใช่จากขนาด
static void hammer(ct_rects_t *o, float phase, bool connected)
{
    ct_ham_stage_t stage = ct_prop_hammer_stage(phase);
    hat(o, c(connected, CT_COL_ACCENT), c(connected, CT_COL_ACCENT_WARM));
    // เงาของหัวค้อนต้องเป็นเทากลาง ไม่ใช่สีหมึก — สีหมึกเกือบเท่าพื้นหลังช่อง
    // ครึ่งล่างของหัวจะหายไปกับฉาก เหลือหัวค้อนบางเป็นขีด
    hammer_tool(o, stage, c(connected, CT_COL_CLAY_DARK), c(connected, CT_COL_TEXT_DIM),
                c(connected, CT_COL_GRAY));

    // หยดเหงื่อกระเด็นออกข้างหมวก ตั้งแต่เงื้อจนฟาด — สัญญาณว่ากำลังออกแรง ไม่ใช่กำลังเล่น
    if (stage == CT_HAM_WINDUP || stage == CT_HAM_STRIKE) {
        uint16_t drop = c(connected, CT_COL_GLASS);
        float fly = stage == CT_HAM_STRIKE ? 1.2f : 0.0f;
        float x = 1.0f - fly, y = -1.2f - fly;
        ct_rects_add(o, x, y, 1.3f, 1.3f, drop);
        ct_rects_add(o, x + 0.3f, y - 0.8f, 0.7f, 0.8f, drop);
    }

    if (stage == CT_HAM_STRIKE) {
        // กระเด็นออกครึ่งทางในเฟรมที่สองของการฟาด — เฟรมเดียวจะอ่านเป็นจุดค้าง ไม่ใช่ประกาย
        float t = phase < (CT_HAM_T_STRIKE + CT_HAM_T_RECOVER) / 2.0f ? 0.0f : 1.0f;
        uint16_t spark = c(connected, CT_COL_ACCENT);
        for (int i = 0; i < 3; i++) {
            ct_rects_add(o, CT_ANVIL_CX - 0.6f + SPARK_DIRS[i][0] * t,
                         CT_ANVIL_TOP - 1.4f + SPARK_DIRS[i][1] * t, 1.2f, 1.2f, spark);
        }
    }
}

// ลูกโลกบนหัว — วัดจากระดับหัว (y = 0)
// ลูกโลกกับนาฬิกาเป็น prop คู่ที่คร่อมหัวเหมือนกัน จึงใช้ทั้งขนาดและตำแหน่งชุดเดียวกัน
// (CLK_S / CLK_Y) ถ้าสองชิ้นนี้ไม่เท่ากัน การสลับสถานะจะอ่านเป็น "ของโตขึ้น/เล็กลง"
#define CT_GLB_D 7.0f      // เส้นผ่านศูนย์กลาง — เท่า CLK_S
#define CT_GLB_CY (-2.0f)  // ขอบบน -5.5 (ไม่ล้น BOX_Y0) ขอบล่าง 1.5 = ขอบบนของตา เท่า CLK_Y
#define CT_GLB_PX 0.25f    // หนึ่งพิกเซลเป็นหน่วย unit ที่ unit_px = 4
#define CT_GLB_BANDS 14    // แถบแนวนอนที่ประกอบเป็นวงกลม — แถบละ 0.5 unit = 2 px (7.0 / 14)
// ขอบลูก 4 px — เท่ากับขอบนาฬิกา (CLK_T) โดยตั้งใจ: ลูกโลกกับนาฬิกาเป็น prop สองชิ้นที่
// คร่อมหัวเหมือนกัน ถ้าน้ำหนักเส้นต่างกันจะอ่านเป็นของคนละชุด ไม่ใช่ภาษาเดียวกัน
#define CT_GLB_RIM 1.0f
// แถบละสองพิกเซลคือจุดที่บันไดยังละเอียดพอให้อ่านเป็นวงกลม แถบละ 4 px (8 แถบ)
// ให้หัวท้ายเป็นแผ่นแบนกว้างจนอ่านเป็นโดม ไม่ใช่ลูกกลม

// ทวีป (dx จากขอบซ้ายของลูก, dy จากขอบบน, กว้าง, สูง) — สามก้อนกระจายคนละระดับ
// ก้อนเดียวอ่านเป็นรอยเปื้อน สามก้อนที่ไม่เรียงกันอ่านเป็นแผ่นดินบนลูกกลม
static const float GLB_LAND[3][4] = {
    {0.5f, 1.5f, 2.0f, 1.5f},
    {3.5f, 3.0f, 2.5f, 1.5f},
    {1.5f, 4.5f, 1.5f, 1.0f},
};

// ลูกโลกบนหัว — WebSearch/WebFetch
// ทรงกลมตัน ไม่ใช่สี่เหลี่ยมกลวง เพราะจะไปซ้ำกับแว่นขยายจนแยกไม่ออกที่ 12px
// ประกอบจากแถบแนวนอนที่กว้างตามสมการวงกลม จึงกลมจริงแม้ที่ 4 px/unit
// น้ำเป็นฟ้า ทวีปเป็นเขียวและเลื่อนไปทางเดียวกันตลอด อ่านเป็น "โลกที่กำลังหมุน"
static void globe(ct_rects_t *o, float phase, bool connected)
{
    // ตอนหลุดการเชื่อมต่อยังต้องเหลือสองค่าความสว่าง ไม่งั้นทวีปจมหายกลายเป็นก้อนเทาตัน
    uint16_t ocean = connected ? CT_COL_GLASS : CT_COL_GRAY;
    uint16_t land = connected ? CT_COL_GOOD : CT_COL_GRAY_DARK;
    // ขอบรอบลูก — น้ำสีฟ้าอ่อนกับฟ้ากลางวันห่างกันไม่ถึงหนึ่งสเต็ป ลูกโลกจึงหายไปกับฟ้า
    // ฟ้ามีสี่ช่วงตั้งแต่เกือบดำถึงฟ้าอ่อน ไม่มีสีน้ำสีเดียวที่ตัดกับทั้งสี่
    // ขอบเข้ม + ไส้สว่างตัดกันคนละทาง อย่างน้อยหนึ่งอย่างจึงเห็นเสมอ
    // steel (สีกรอบแว่นขยาย) ไม่ใช่ ink — ขอบสีหมึกอ่านเป็นเส้นขีดดำ ไม่ใช่ขอบของทรงกลม
    uint16_t rim = connected ? CT_COL_STEEL : CT_COL_GRAY_DARK;

    // ครึ่งความกว้างวัดที่กึ่งกลางแถบ (ไม่ใช่ขอบ) หัวท้ายจึงแคบลงตามวงกลมจริง
    // แล้วปัดเป็นจำนวนพิกเซลเต็ม ขอบซ้าย/ขวาจึงตกบนเส้นพิกเซลพอดี ไม่มีขั้นบันไดครึ่งพิกเซล
    // ไส้ต้องมาจาก *วงกลมที่เล็กลง* (r - CT_GLB_RIM) ไม่ใช่จากการหักขอบออกทางแนวนอน:
    // การหักแนวนอนกินแค่ซ้าย/ขวา แถบบน/ล่างจึงยาวเท่าเดิม ไส้ออกมาเป็นวงรีตั้ง
    // (ที่ขอบ 4 px ไส้กลายเป็น 18 x 22 px — เห็นชัดว่าลูกโลกไม่กลม)
    float r = CT_GLB_D / 2.0f, r_in = r - CT_GLB_RIM, bh = CT_GLB_D / CT_GLB_BANDS;
    // bhw = ครึ่งความกว้างของ "ไส้" — ทวีปเกาะไส้ ไม่ใช่ขอบ จึงไม่ทับขอบมืด
    float by0[CT_GLB_BANDS], by1[CT_GLB_BANDS], bhw[CT_GLB_BANDS];
    for (int i = 0; i < CT_GLB_BANDS; i++) {
        by0[i] = CT_GLB_CY - r + i * bh;
        by1[i] = by0[i] + bh;
        float yy = fabsf(by0[i] + bh / 2.0f - CT_GLB_CY);
        float q = r * r - yy * yy;
        float hw = roundf(sqrtf(q > 0.0f ? q : 0.0f) / CT_GLB_PX) * CT_GLB_PX;
        ct_rects_add(o, CT_HEAD_CX - hw, by0[i], 2 * hw, by1[i] - by0[i], rim);
        float qi = r_in * r_in - yy * yy;
        float ihw = roundf(sqrtf(qi > 0.0f ? qi : 0.0f) / CT_GLB_PX) * CT_GLB_PX;
        // แถบบนสุด/ล่างสุดเป็นขอบล้วน — ถ้าเจาะไส้ด้วย ขอบด้านบน/ล่างจะหายไปทั้งเส้น
        if (i == 0 || i == CT_GLB_BANDS - 1) ihw = 0.0f;
        if (ihw > 0.0f) {
            ct_rects_add(o, CT_HEAD_CX - ihw, by0[i], 2 * ihw, by1[i] - by0[i], ocean);
        }
        bhw[i] = ihw;
    }

    float left = CT_HEAD_CX - CT_GLB_D / 2.0f, top = CT_GLB_CY - CT_GLB_D / 2.0f;
    float spin = fmodf(phase, 1.0f) * CT_GLB_D;
    for (int i = 0; i < 3; i++) {
        float px = left + fmodf(GLB_LAND[i][0] + spin, CT_GLB_D);
        float py = top + GLB_LAND[i][1], w = GLB_LAND[i][2], h = GLB_LAND[i][3];
        // ครึ่งความกว้างที่แคบที่สุดในช่วงที่ทวีปกินอยู่ — ทวีปจึงไม่ยื่นล้นขอบลูกโลก
        float hw = 0.0f;
        bool first = true;
        for (int k = 0; k < CT_GLB_BANDS; k++) {
            if (by1[k] > py && by0[k] < py + h && (first || bhw[k] < hw)) {
                hw = bhw[k];
                first = false;
            }
        }
        // เล็มด้านที่ล้นขอบทิ้ง แทนที่จะซ่อนทั้งก้อน — ทวีปที่หายวับทั้งชิ้นอ่านเป็นกะพริบ
        // ส่วนทวีปที่ค่อยๆ โผล่จากขอบอ่านเป็นแผ่นดินที่หมุนอ้อมมาจากอีกด้าน
        float lo = CT_HEAD_CX - hw, hi = CT_HEAD_CX + hw;
        float x0 = px > lo ? px : lo, x1 = (px + w) < hi ? (px + w) : hi;
        if (x1 - x0 >= 0.6f) {  // เศษที่แคบกว่านี้อ่านเป็นจุด ไม่ใช่แผ่นดิน
            ct_rects_add(o, x0, py, x1 - x0, h, land);
        }
    }
}

// ฟองข้อความเหนือหัว — thinking (จุดในฟองไล่สว่างทีละจุด)
// ฟองทึบสีสว่าง จุดเป็นสีเข้ม — อ่านออกที่ 12px กว่าจุดลอยเปล่าๆ ซึ่งดูเหมือนเศษ noise
// หางฟองเป็นบันไดชี้ลงหาหัว บอกว่าความคิดนี้เป็นของมาสคอต ไม่ใช่ของ slot ข้างๆ
static void dots(ct_rects_t *o, float phase, bool connected)
{
    // ตอนหลุดการเชื่อมต่อฟองต้องหรี่เป็นเทา แต่ยังต้องเข้มพอให้จุดข้างในไม่จม
    uint16_t skin = connected ? CT_COL_TEXT : CT_COL_GRAY;
    // จุดฟ้า: ทั้งสามใช้ฟ้าเทาเข้ม (steel) ตัวเดียวกัน ต่างกันแค่ขนาด
    // (ถ้าให้จุดที่ยังไม่ติดเป็นฟ้าอ่อน มันจะจมหายไปกับฟองสว่างเมื่อย่อลงเหลือ ~4px/unit)
    uint16_t dot = connected ? CT_COL_STEEL : CT_COL_GRAY_DARK;

    float bob = 0.3f * (0.5f + 0.5f * sinf(phase * (float)M_PI * 2.0f));  // ลงอย่างเดียว กันล้นขอบบน
    float x = CT_HEAD_CX - CT_BUB_W / 2.0f, y = -5.4f + bob;
    float cut = 0.8f;  // มุมที่ตัดออก ทำให้ฟองมนไม่ใช่กล่อง
    ct_rects_add(o, x + cut, y, CT_BUB_W - 2 * cut, cut, skin);
    ct_rects_add(o, x, y + cut, CT_BUB_W, CT_BUB_H - 2 * cut, skin);
    ct_rects_add(o, x + cut, y + CT_BUB_H - cut, CT_BUB_W - 2 * cut, cut, skin);

    // หางบันไดสองขั้น — เยื้องซ้ายของฟอง ชี้ลงหาหัวที่ y=0
    float ty = y + CT_BUB_H;
    ct_rects_add(o, x + 2.4f, ty, 1.7f, 0.7f, skin);
    ct_rects_add(o, x + 2.4f, ty + 0.7f, 0.9f, 0.6f, skin);

    int lit = (int)(phase * 3.0f) % 3;
    for (int i = 0; i < 3; i++) {
        float s = (i == lit) ? 1.7f : 1.0f;
        float cx = CT_HEAD_CX + (i - 1) * 2.6f;
        float cy = y + CT_BUB_H / 2.0f;
        ct_rects_add(o, cx - s / 2, cy - s / 2, s, s, dot);
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

// เรือนใหญ่คร่อมหัวแบบเดียวกับลูกโลก — ที่ 5.0 unit หน้าปัดเหลือไส้แค่ 3.5 unit
// เข็มสองเล่มในนั้นอ่านเป็นรอยเปื้อน ไม่ใช่เข็ม ต้องโตจนไส้กว้างพอให้เข็มยาวกับเข็มสั้น
// ต่างกันเห็นชัด แล้วยอมให้ล้นลงมาทับหน้าผากแทน
// 7.0 ไม่ใช่ 6.5 ของลูกโลก เพราะวงแหวนไล่บันไดที่ s/4: 6.5 ทำให้มุมตกที่ 1.625 unit
// = ครึ่งพิกเซล แล้วบันไดเหลื่อมกันจนเห็นเป็นร่อง (บทเรียนเดียวกับเลนส์แว่นขยาย)
#define CLK_S 7.0f  // เส้นผ่านศูนย์กลางหน้าปัด
#define CLK_T 1.0f  // ความหนาขอบ
#define CLK_Y (-5.5f)  // ขอบบนไม่ล้น BOX_Y0 (-5.6) ขอบล่างจบพอดีที่ 1.5 = ขอบบนของตา
#define CLK_HAND_PX 0.75f  // ขนาดก้อนของเข็มหนึ่งช่วง
#define CLK_TICKS 12  // จำนวนตำแหน่งที่เข็มยาวหยุดได้ = จำนวนขีดบนหน้าปัดจริง

// เข็มหนึ่งเล่ม — ก้อนสี่เหลี่ยมเรียงจากศูนย์กลางออกไป
// ทุกก้อนสแนปลงตาราง 0.25 unit (= 1 px) ก่อนวาด ถ้าปล่อยให้ตกครึ่งพิกเซล
// เข็มจะเบลอเป็นเงาสองชั้นแทนที่จะเป็นขีดคม และมุมที่ต่างกันจะหนาไม่เท่ากัน
static void clock_hand(ct_rects_t *o, float cx, float cy, float ang, float len, uint16_t col)
{
    int n = (int)(len / 0.4f + 0.5f);
    if (n < 1) n = 1;
    for (int k = 1; k <= n; k++) {
        float r = k * (len / n);
        float px = roundf((cx + sinf(ang) * r - CLK_HAND_PX / 2) * 4.0f) / 4.0f;
        float py = roundf((cy - cosf(ang) * r - CLK_HAND_PX / 2) * 4.0f) / 4.0f;
        ct_rects_add(o, px, py, CLK_HAND_PX, CLK_HAND_PX, col);
    }
}

// นาฬิกาเหลือง — waiting (รอคำตอบจากคุณ)
// เคยเป็น "?" แต่คำถามอ่านเป็น "งง/ไม่รู้" ปนกับ bang ที่แปลว่าพัง สารจริงคือ
// "เวลากำลังเดินอยู่ ถึงตาคุณแล้ว" ซึ่งนาฬิกาบอกได้ตรงกว่าและไม่ชนกับ prop อื่น
// เข็มยาวเดินเป็นขั้น 12 ขั้น ไม่ไหลต่อเนื่อง: ที่ ~28px ทั้งเรือน การไหลอ่านเป็นภาพสั่น
// เรือนไม่เด้งขึ้นลงเลย จังหวะทั้งหมดอยู่ที่เข็ม — นาฬิกาที่ลอยเด้งอ่านเป็นลูกโป่ง
// และที่สำคัญกว่า: ขอบล่างจ่อขอบบนของตาอยู่แล้ว ขยับลงอีกนิดเดียวก็กินตา
// (ตัวมาสคอตเด้งผ่านเรือนไปเอง — ct_mascot.c ไม่เลื่อน prop นี้ตาม dy)
static void clockface(ct_rects_t *o, float phase, bool connected)
{
    uint16_t rim = c(connected, CT_COL_ACCENT);
    uint16_t face = connected ? CT_COL_TEXT : CT_COL_GRAY;
    uint16_t hand = c(connected, CT_COL_INK);

    float x = CT_HEAD_CX - CLK_S / 2.0f, y = CLK_Y;
    float s = CLK_S, t = CLK_T, k = CLK_S / 4.0f;

    ct_rects_add(o, x + t, y + k, s - 2 * t, s - 2 * k, face);  // แถบกลาง เต็มความกว้างในขอบ
    ct_rects_add(o, x + k, y + t, s - 2 * k, k - t, face);      // เติมช่องบนใต้ขอบ
    ct_rects_add(o, x + k, y + s - k, s - 2 * k, k - t, face);  // และช่องล่าง
    ring_round(o, x, y, s, t, rim);

    float cx = x + s / 2.0f, cy = y + s / 2.0f;
    int step = (int)(phase * CLK_TICKS) % CLK_TICKS;
    clock_hand(o, cx, cy, step * 2.0f * (float)M_PI / CLK_TICKS, 2.0f, hand);
    // เข็มสั้นค้างที่ 10 นาฬิกา — มุมที่หน้าปัดทุกเรือนในโฆษณาใช้ เพราะเป็นตำแหน่งที่
    // เข็มสองเล่มไม่ทับกันและไม่ตั้งฉากจนอ่านเป็นกากบาท
    clock_hand(o, cx, cy, -(float)M_PI / 3.0f, 1.2f, hand);
    ct_rects_add(o, cx - 0.375f, cy - 0.375f, 0.75f, 0.75f, hand);  // ดุมกลาง
}

// Zzz — sleeping (ลอยขึ้นทแยงจากมุมบนขวาของหัว)
static void zzz(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_TEXT_DIM);
    for (int i = 0; i < 3; i++) {
        float t = fmodf(phase + i / 3.0f, 1.0f);
        float s = 1.0f + i * 0.55f;
        ct_rects_add(o, 11.4f + i * 2.0f + t * 1.0f, -1.1f - i * 1.5f - t * 1.3f, s, s, col);
    }
}

// ประกาย — celebrate (กระพริบสลับรอบตัว)
static void sparkle(ct_rects_t *o, float phase, bool connected)
{
    uint16_t col = c(connected, CT_COL_ACCENT);
    const float spots[5][2] = {
        {2.6f, -2.6f}, {13.4f, -2.0f}, {CT_HEAD_CX, -4.0f}, {0.5f, 3.2f}, {18.6f, 5.6f}};
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

// เสาอากาศบนหัว — LSP/MCP (คลื่นสว่างไล่ออกด้านข้างทีละชั้น)
// "คุยกับบริการอื่นอยู่" ไม่ใช่ "ค้นหา" จึงไม่ใช้ลูกโลกซ้ำ เสาอยู่บนหัวไม่ใช่ถือข้างตัว
// เพราะสัญญาณต้องออกจากตัวมาสคอตเอง ไม่ใช่จากอุปกรณ์ที่ตั้งอยู่ข้างๆ
// คลื่นแผ่ออกด้านข้าง ไม่ใช่ขึ้นบน — เหนือหัวมีที่แค่ 5.6 unit แต่แนวนอนมีเหลือเฟือ
// ชั้นที่ไล่ออกข้างจึงเดินได้ไกลกว่าและอ่านเป็นคลื่นวิ่งออกจริง ไม่ใช่ขีดซ้อนกันคาหัว
#define CT_BEA_TIP_Y (-2.6f)  // กึ่งกลางไฟยอดเสา — สูงกว่านี้ชั้นนอกสุดล้น CT_BOX_Y0 ตอนตัวเด้ง
#define CT_BEA_MAST_H 3.0f    // ความสูงเสา จากใต้ไฟยอดเสาลงมาจมในหัว
#define CT_BEA_ARCS 3
#define CT_BEA_ARC_D0 1.6f  // ระยะจากเสาของชั้นในสุด
#define CT_BEA_ARC_DD 1.7f  // ไกลขึ้นต่อชั้น
#define CT_BEA_ARC_H0 1.5f  // ความสูงสันของชั้นในสุด
#define CT_BEA_ARC_DH 0.7f  // สูงขึ้นต่อชั้น
#define CT_BEA_ARC_T 0.6f   // ความหนาของส่วนโค้ง
#define CT_BEA_TIP_R 1.0f   // รัศมีไฟยอดเสา

// ไฟยอดเสาทรงกลม — สองแท่งไขว้กัน มุมทั้งสี่จึงหายไปและอ่านเป็นวงกลมที่ 3 px/unit
static void beacon_tip(ct_rects_t *o, uint16_t color)
{
    float r = CT_BEA_TIP_R, cut = CT_BEA_TIP_R * 0.34f;  // cut = มุมที่ตัดออกแต่ละด้าน
    float x = CT_HEAD_CX - r, y = CT_BEA_TIP_Y - r;
    ct_rects_add(o, x + cut, y, 2 * r - 2 * cut, 2 * r, color);  // แท่งตั้ง
    ct_rects_add(o, x, y + cut, 2 * r, 2 * r - 2 * cut, color);  // แท่งนอน
}

// ส่วนโค้งชั้นที่ k สองข้างของเสา (0 = ชั้นในสุด) — สันตั้งกับปีกที่ร่นเข้าหาเสา
// ยิ่งไกลสันยิ่งสูง จึงอ่านเป็นวงที่กว้างขึ้น ไม่ใช่ขีดสามขีดที่ยาวเท่ากัน
static void beacon_arc(ct_rects_t *o, int k, uint16_t color)
{
    float d = CT_BEA_ARC_D0 + k * CT_BEA_ARC_DD;
    float h = CT_BEA_ARC_H0 + k * CT_BEA_ARC_DH;
    float t = CT_BEA_ARC_T;
    float y = CT_BEA_TIP_Y - h / 2.0f;
    for (int i = 0; i < 2; i++) {
        float side = i == 0 ? -1.0f : 1.0f;  // ซ้าย/ขวา สมมาตรรอบเสา
        // ขอบซ้ายของสันตั้ง — ข้างซ้ายต้องถอยอีกหนึ่งความหนา สันสองข้างจึงห่างเสาเท่ากัน
        float x = CT_HEAD_CX + side * d - (side < 0.0f ? t : 0.0f);
        float wing = x - side * t;  // ปีกร่นเข้าหาเสาหนึ่งช่วงความหนา
        ct_rects_add(o, x, y, t, h, color);          // สันตั้ง
        ct_rects_add(o, wing, y - t, t, t, color);   // ปีกบน
        ct_rects_add(o, wing, y + h, t, t, color);   // ปีกล่าง
    }
}

static void beacon(ct_rects_t *o, float phase, bool connected)
{
    // ชั้นโผล่สะสมทีละชั้น 1 -> 2 -> 3 แล้ววนใหม่ = สัญญาณที่แผ่ออกไกลขึ้นเรื่อยๆ
    // ไม่มีชั้นเทาค้างไว้ ชั้นที่ยังไม่ถึงคิวคือไม่วาดเลย จอจึงเหลือแต่คลื่นจริง
    int step = (int)(phase * CT_BEA_ARCS) % CT_BEA_ARCS;  // ชั้นนอกสุดที่โผล่แล้วในเฟรมนี้
    // สีเดียวทั้งชุด — หลายสีอ่านเป็นของหลายชิ้น ไม่ใช่คลื่นชุดเดียว
    uint16_t lit = c(connected, CT_COL_ACCENT);
    // ไฟยอดเสาแดงคงที่ ไม่กะพริบ — จังหวะทั้งหมดอยู่ที่คลื่นแล้ว ถ้าไฟกะพริบด้วยจะแย่งกันเต้น
    uint16_t tip = c(connected, CT_COL_ALERT);
    // เสาเป็นสีขาวเหมือนเส้นขอบตัว จึงอ่านเป็นชิ้นส่วนของมาสคอตเอง ไม่ใช่ของที่พิงอยู่
    uint16_t mast = connected ? CT_COL_OUTLINE : CT_COL_GRAY;

    for (int k = 0; k <= step; k++) beacon_arc(o, k, lit);  // สะสมจากชั้นในออกไปข้างนอก
    ct_rects_add(o, CT_HEAD_CX - 0.5f, CT_BEA_TIP_Y + 0.6f, 1.0f, CT_BEA_MAST_H, mast);  // เสา
    beacon_tip(o, tip);  // ไฟยอดเสา — กลม ไม่ใช่ก้อนเหลี่ยม
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
        case CT_PROP_CLOCK: clockface(out, phase, connected); break;
        case CT_PROP_ZZZ: zzz(out, phase, connected); break;
        case CT_PROP_SPARKLE: sparkle(out, phase, connected); break;
        case CT_PROP_CREW: crew(out, phase, connected); break;
        case CT_PROP_BEACON: beacon(out, phase, connected); break;
        case CT_PROP_NONE:
        default: break;
    }
}
