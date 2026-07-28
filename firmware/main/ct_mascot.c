#include "ct_mascot.h"

#include <math.h>
#include <string.h>

#include "ct_props.h"

// --- โครงร่าง (พิกัด unit) --------------------------------------------------
// สัดส่วนวัดจากภาพอ้างอิง ลำตัวกว้าง 14 เป็นฐานของทุกค่า
#define BODY_X 1.0f
#define BODY_Y 0.0f
#define BODY_W 14.0f
#define BODY_H 8.0f
#define NUB_Y 2.8f
#define NUB_H 2.5f
#define NUB_W 1.5f
#define LEG_TOP 8.0f
#define LEG_H 3.2f
#define FOOT_Y (LEG_TOP + LEG_H)  // 11.2 — ระดับที่มาสคอตยืน
#define EYE_L 3.36f
#define EYE_R CT_EYE_R  // ตาข้างขวานิยามใน ct_props.h — แว่นขยายต้องเล็งไปที่นั่น
#define EYE_Y CT_EYE_Y
#define EYE_S CT_EYE_S

// ขาและช่องว่างวัดจากภาพอ้างอิง: ขานอกกว้างกว่าขาใน ช่องกลางกว้างกว่าช่องข้าง
static const float LEG_SPANS[4][2] = {
    {1.00f, 2.46f}, {4.50f, 2.20f}, {9.29f, 2.20f}, {12.53f, 2.46f}};

// ช่วง phase ที่ตากะพริบ — สั้นมากโดยตั้งใจ กะพริบนานกว่านี้จะดูเหมือนง่วง
#define BLINK_FROM 0.88f
#define BLINK_TO 0.94f
// กะพริบทุกกี่รอบลูป — ลูปเดียวยาวราว 1 วินาที กะพริบทุกวินาทีจะดูกระวนกระวาย
#define BLINK_EVERY 4

typedef enum { EYE_OPEN, EYE_SLEEP, EYE_SQUINT, EYE_FOCUS, EYE_WIDE, EYE_BLINK, EYE_HAPPY, EYE_DEAD } eye_t;
typedef enum { GAIT_STAND, GAIT_WALK, GAIT_SIT } gait_t;

typedef struct {
    eye_t eye;
    gait_t gait;
    float squash;
    float bob;     // ระยะแกว่งขึ้นลง (unit)
    float bob_hz;
    float shake;
    float look;
    float scan;    // กวาดสายตาซ้าย->ขวาแล้ววกกลับ (unit) — ท่าอ่านโค้ด
    float arm;     // ระยะที่แขนขยับสลับข้าง (unit) — ท่าพิมพ์
    bool blink;    // ตาลืมเท่านั้นที่กะพริบได้
    bool strike;   // ใช้จังหวะทุบของ ct_prop_hammer_stage() แทนการกระเด้งเป็นคลื่น
    float sink;    // >0 = จมลงดินตามความคืบหน้าของ phase (ท่ามุดหาย)
    float arm_up;  // ระยะที่แขนยกค้างพร้อมกันสองข้าง (unit) — ท่าเพ่งพลัง
    float arm_out; // ระยะที่ท่อนนอกของแขนเยื้องออกนอกตัว (unit) — ใช้คู่กับ arm_up
} mood_t;

typedef enum {
    MOOD_IDLE, MOOD_WORKING, MOOD_TYPING, MOOD_HAMMERING, MOOD_WALKING, MOOD_WAITING,
    MOOD_SLEEPING, MOOD_ALERT, MOOD_CELEBRATE, MOOD_ERROR, MOOD_SIGNALLING,
    MOOD_ENTERING, MOOD_LEAVING,
    MOOD_COUNT,
} mood_id_t;

// bob วัดเป็น unit — 1 unit = CT_SLOTS_UNIT_PX พิกเซล ต่ำกว่า 0.5 unit จะมองแทบไม่เห็นบนจอ
// ลำดับฟิลด์: eye, gait, squash, bob, bob_hz, shake, look, scan, arm, blink, strike, sink,
// arm_up, arm_out (ท่าที่ไม่ยกแขนไม่ต้องเขียนสองค่าสุดท้าย — C เติม 0 ให้เอง)
static const mood_t MOODS[MOOD_COUNT] = {
    [MOOD_IDLE]      = {EYE_OPEN,   GAIT_STAND, 0.00f, 0.75f, 1.0f, 0.00f, 0.00f, 0.00f, 0.00f, true,  false, 0.0f, 0.0f, 0.0f},
    [MOOD_WORKING]   = {EYE_FOCUS,  GAIT_STAND, 0.03f, 0.50f, 2.4f, 0.00f, 0.00f, 0.00f, 0.00f, true,  false, 0.0f, 0.0f, 0.0f},
    // ท่านั่งพิมพ์ — ตัวแทบไม่กระเด้ง เพราะสัญญาณอยู่ที่สายตาที่กวาดอ่านกับแขนที่พิมพ์
    [MOOD_TYPING]    = {EYE_FOCUS,  GAIT_STAND, 0.03f, 0.30f, 2.0f, 0.00f, 0.00f, 1.00f, 0.70f, true,  false, 0.0f, 0.0f, 0.0f},
    // ท่าทุบ — ไม่กระเด้งเป็นคลื่น แต่ยืดตัวตอนเงื้อและยุบตัวตอนกระแทกตามจังหวะค้อน
    [MOOD_HAMMERING] = {EYE_FOCUS,  GAIT_STAND, 0.00f, 0.35f, 2.0f, 0.00f, 0.00f, 0.00f, 0.00f, true,  true,  0.0f, 0.0f, 0.0f},
    [MOOD_WALKING]   = {EYE_OPEN,   GAIT_WALK,  0.00f, 0.75f, 2.0f, 0.00f, 0.00f, 0.00f, 0.00f, true,  false, 0.0f, 0.0f, 0.0f},
    [MOOD_WAITING]   = {EYE_OPEN,   GAIT_STAND, 0.00f, 1.00f, 0.7f, 0.00f, 0.40f, 0.00f, 0.00f, true,  false, 0.0f, 0.0f, 0.0f},
    [MOOD_SLEEPING]  = {EYE_SLEEP,  GAIT_SIT,   0.10f, 0.50f, 0.35f, 0.00f, 0.00f, 0.00f, 0.00f, false, false, 0.0f, 0.0f, 0.0f},
    [MOOD_ALERT]     = {EYE_WIDE,   GAIT_STAND, 0.00f, 0.90f, 3.2f, 0.20f, 0.00f, 0.00f, 0.00f, false, false, 0.0f, 0.0f, 0.0f},
    [MOOD_CELEBRATE] = {EYE_HAPPY,  GAIT_STAND, -0.05f, 1.25f, 2.6f, 0.00f, 0.00f, 0.00f, 0.00f, false, false, 0.0f, 0.0f, 0.0f},
    [MOOD_ERROR]     = {EYE_DEAD,   GAIT_SIT,   0.12f, 0.00f, 1.0f, 0.08f, 0.00f, 0.00f, 0.00f, false, false, 0.0f, 0.0f, 0.0f},
    // ท่าส่งสัญญาณ — ตาปกติ ไม่เบิกกว้าง (ตาโตอ่านเป็นตกใจ ซึ่งเป็นสารของ alert)
    // สารของท่านี้อยู่ที่เสาอากาศกับมือที่ยกค้าง ไม่ใช่ที่หน้า
    // แขนยกค้างนิ่งพร้อมกันสองข้างแบบเพ่งพลัง — ไม่โยก เพราะการโยกอ่านเป็นโบกมือ
    // ท่อนนอกเยื้องออกนอกตัว จึงเห็นเป็นมือที่ยกขึ้นจริง ไม่ใช่ไหล่ที่สูงขึ้นเฉยๆ
    [MOOD_SIGNALLING] = {EYE_OPEN,  GAIT_STAND, 0.00f, 0.45f, 1.3f, 0.00f, 0.00f, 0.00f, 0.00f, true,  false, 0.0f, 1.9f, 0.9f},
    // ท่าเปลี่ยนผ่าน — phase ทำหน้าที่เป็นความคืบหน้า 0->1 ไม่ใช่ลูปวน
    [MOOD_ENTERING]  = {EYE_OPEN,   GAIT_WALK,  0.00f, 1.00f, 4.0f, 0.00f, 0.00f, 0.00f, 0.00f, true,  false, 0.0f, 0.0f, 0.0f},
    [MOOD_LEAVING]   = {EYE_SQUINT, GAIT_SIT,   0.30f, 0.00f, 1.0f, 0.00f, 0.00f, 0.00f, 0.00f, false, false, 1.0f, 0.0f, 0.0f},
};

// visual state = mood + prop — ต้องตรงกับ STATES ใน tools/gen/mascot.py
static const struct {
    mood_id_t mood;
    ct_prop_t prop;
} STATES[CT_STATE_COUNT] = {
    [CT_STATE_IDLE]      = {MOOD_IDLE,      CT_PROP_NONE},
    [CT_STATE_READING]   = {MOOD_WORKING,   CT_PROP_MAGNIFIER},
    [CT_STATE_WRITING]   = {MOOD_TYPING,    CT_PROP_LAPTOP},
    [CT_STATE_BUILDING]  = {MOOD_HAMMERING, CT_PROP_HAMMER},
    [CT_STATE_SEARCHING] = {MOOD_WORKING,   CT_PROP_GLOBE},
    [CT_STATE_THINKING]  = {MOOD_IDLE,      CT_PROP_DOTS},
    [CT_STATE_WAITING]   = {MOOD_WAITING,   CT_PROP_QUERY},
    [CT_STATE_SLEEPING]  = {MOOD_SLEEPING,  CT_PROP_ZZZ},
    [CT_STATE_ALERT]     = {MOOD_ALERT,     CT_PROP_BANG},
    [CT_STATE_CELEBRATE] = {MOOD_CELEBRATE, CT_PROP_SPARKLE},
    [CT_STATE_ERROR]     = {MOOD_ERROR,     CT_PROP_NONE},
    [CT_STATE_ENTERING]  = {MOOD_ENTERING,  CT_PROP_NONE},
    [CT_STATE_LEAVING]   = {MOOD_LEAVING,   CT_PROP_NONE},
    [CT_STATE_CONDUCTING] = {MOOD_WORKING,  CT_PROP_CREW},
    [CT_STATE_BEACON]    = {MOOD_SIGNALLING, CT_PROP_BEACON},
};

// ท่าที่มีของประกอบเยอะจนแน่นช่อง ย่อลงเล็กน้อยเพื่อให้ยังมีที่หายใจรอบตัว
// ต้องตรงกับ STATE_SCALE ใน tools/gen/mascot.py
static float state_scale(ct_state_t state)
{
    return state == CT_STATE_BUILDING ? 0.875f : 1.0f;
}

// --- ตา ---------------------------------------------------------------------
// ตาหนึ่งข้าง กล่องฐาน EYE_S x EYE_S ที่ (x, EYE_Y) — ทุกค่าอิงสัดส่วน ไม่ฝังตัวเลขดิบ
// scale > 1 = ตาโตขึ้นโดยยึดจุดกึ่งกลางเดิม (ใช้กับตาที่อยู่หลังเลนส์แว่นขยาย)
static void eye(ct_rects_t *o, float x, eye_t kind, float look, uint16_t ink, float scale)
{
    const float s = EYE_S * scale;
    const float grow = (s - EYE_S) / 2.0f;
    const float y = EYE_Y - grow;
    x -= grow;
    switch (kind) {
        case EYE_SLEEP:
            ct_rects_add(o, x, y + s * 0.62f, s, s * 0.3f, ink);
            return;
        case EYE_SQUINT:
            ct_rects_add(o, x, y + s * 0.34f, s, s * 0.42f, ink);
            return;
        case EYE_FOCUS: {
            float m = s * 0.22f;
            ct_rects_add(o, x + m + look, y + m, s - 2 * m, s - 2 * m, ink);
            return;
        }
        case EYE_WIDE: {
            float m = s * 0.24f;
            ct_rects_add(o, x - m + look, y - m, s + 2 * m, s + 2 * m, ink);
            return;
        }
        case EYE_BLINK:
            ct_rects_add(o, x, y + s * 0.42f, s, s * 0.28f, ink);
            return;
        case EYE_HAPPY: {  // ^ ^ — ต้องไม่ใช่ขีดแบน ไม่งั้นซ้ำกับตาหลับ
            float u = s / 3.0f;
            const int cells[3][2] = {{0, 1}, {1, 0}, {2, 1}};
            for (int i = 0; i < 3; i++) {
                ct_rects_add(o, x + cells[i][0] * u, y + cells[i][1] * u, u, u, ink);
            }
            return;
        }
        case EYE_DEAD: {  // x_x — บันไดขั้นละ 1 บล็อกทำเป็นกากบาท
            float u = s / 3.0f;
            const int cells[5][2] = {{0, 0}, {1, 1}, {2, 2}, {2, 0}, {0, 2}};
            for (int i = 0; i < 5; i++) {
                ct_rects_add(o, x + cells[i][0] * u, y + cells[i][1] * u, u, u, ink);
            }
            return;
        }
        case EYE_OPEN:
        default:
            ct_rects_add(o, x + look, y, s, s, ink);
            return;
    }
}

// --- ขา ---------------------------------------------------------------------
static void legs(ct_rects_t *o, gait_t gait, float phase, uint16_t color, float extra_lift)
{
    for (int i = 0; i < 4; i++) {
        float lift = extra_lift;
        if (gait == GAIT_WALK) {
            // ขาคู่ทแยง (0,2) กับ (1,3) สลับกันยก
            bool up = (phase < 0.5f) == (i % 2 == 0);
            lift += up ? LEG_H * 0.34f : 0.0f;
        } else if (gait == GAIT_SIT) {
            lift += LEG_H * 0.66f;
        }
        float h = LEG_H - lift;
        if (h < 0.6f) h = 0.6f;
        ct_rects_add(o, LEG_SPANS[i][0], LEG_TOP, LEG_SPANS[i][1], h, color);
    }
}

// --- ลำตัว ------------------------------------------------------------------
// ลำตัวกับแขนสองข้างในสัดส่วนปกติ — การยุบตัวทำทีหลังด้วย squashed()
// arm_l/arm_r เลื่อนแขน (nub) ทีละข้าง — ท่าพิมพ์ใช้ค่าคนละเครื่องหมายจึงอ่านเป็นสลับมือ
// arm_out > 0 = แขนเป็นสองท่อนลดหลั่นออกนอกตัว (ท่ายกมือค้าง) แทนที่จะเป็นก้อนเดียว
// ก้อนเดียวที่เลื่อนขึ้นเฉยๆ อ่านเป็น "ไหล่สูงขึ้น" ไม่ใช่ "ยกมือ" — ต้องมีท่อนที่เยื้อง
// ออกไปนอกซิลลูเอ็ต สายตาถึงจะเห็นเป็นแขนที่กางขึ้น
static void body(ct_rects_t *o, uint16_t color, float arm_l, float arm_r, float arm_out)
{
    ct_rects_add(o, BODY_X, BODY_Y, BODY_W, BODY_H, color);
    if (arm_out == 0.0f) {
        ct_rects_add(o, BODY_X - NUB_W, NUB_Y + arm_l, NUB_W, NUB_H, color);
        ct_rects_add(o, BODY_X + BODY_W, NUB_Y + arm_r, NUB_W, NUB_H, color);
        return;
    }
    // แต่ละท่อนเตี้ยกว่าแขนปกติ สองท่อนรวมกันจึงไม่ยาวเกินสัดส่วนเดิม
    float h = NUB_H * 0.8f;
    const float SIDE[2] = {-1.0f, 1.0f};
    const float X0[2] = {BODY_X - NUB_W, BODY_X + BODY_W};
    const float DY[2] = {arm_l, arm_r};
    for (int i = 0; i < 2; i++) {
        // ท่อนใน — ติดลำตัว ยกขึ้นครึ่งทางของท่อนนอก จึงอ่านเป็นแขนที่เอียงขึ้น
        ct_rects_add(o, X0[i], NUB_Y + DY[i] + h * 0.5f, NUB_W, h, color);
        ct_rects_add(o, X0[i] + SIDE[i] * arm_out, NUB_Y + DY[i], NUB_W, h, color);
    }
}

// ยุบทั้งตัวรอบฝ่าเท้า — ลำตัว ขา และตา ต้องยุบเป็นก้อนเดียวกัน
// ถ้ายุบเฉพาะลำตัว ก้นลำตัวจะค้างอยู่ที่เดิมและขายาวเท่าเดิม อ่านเป็นกล่องเตี้ยลง
// บนขาชุดเดิม ไม่ใช่ตัวที่โดนกระแทก ฝ่าเท้าไม่ขยับเพราะระดับที่ยืนต้องคงที่
static void squashed(ct_rects_t *rs, int from, float squash)
{
    if (squash == 0.0f) return;
    ct_rects_scale_from(rs, from, 1.0f + squash * 0.45f, 1.0f - squash, CT_HEAD_CX, FOOT_Y);
}

// คืน (สีตัว, สีตา, สีขอบ)
static void skin(bool connected, ct_state_t state, uint16_t *body_c, uint16_t *ink,
                 uint16_t *edge)
{
    if (!connected) {
        *body_c = CT_COL_GRAY;
        *ink = CT_COL_GRAY_DARK;
        *edge = CT_COL_TEXT_DIM;
        return;
    }
    if (state == CT_STATE_SLEEPING) {
        // หรี่ลงเล็กน้อยเท่านั้น — ถ้าเปลี่ยนสีแรงจะไปชนกับสัญญาณ "หลุดการเชื่อมต่อ"
        *body_c = CT_COL_CLAY_DARK;
        *ink = CT_COL_INK;
        *edge = CT_COL_OUTLINE;
        return;
    }
    *body_c = CT_COL_CLAY;
    *ink = CT_COL_INK;
    *edge = CT_COL_OUTLINE;
}

void ct_mascot_build(ct_rects_t *out, ct_state_t state, float phase, bool connected,
                     int cycle)
{
    if (state < 0 || state >= CT_STATE_COUNT) state = CT_STATE_IDLE;
    const mood_t *m = &MOODS[STATES[state].mood];
    uint16_t body_c, ink, edge;
    skin(connected, state, &body_c, &ink, &edge);

    // ปัด dy ลงตารางพิกเซลก่อน ไม่งั้นแต่ละ rect ปัดคนละทางแล้วเห็นแค่เส้นขอบกระพริบ
    // แทนที่จะเห็นทั้งตัวเลื่อนขึ้นลงพร้อมกัน
    float dy = -fabsf(sinf(phase * (float)M_PI * m->bob_hz)) * m->bob;
    // ท่าทุบเดินตาม timeline ของค้อน ไม่ใช่คลื่น: ยืดตัวตอนเงื้อ ยุบตัวตอนกระแทก
    // (ยุบด้วย squash ซึ่งยึดฝ่าเท้าไว้ ไม่ใช่ dy บวก ที่จะดันขาจมลงใต้พื้น)
    ct_ham_stage_t stage = m->strike ? ct_prop_hammer_stage(phase) : CT_HAM_READY;
    if (m->strike && stage == CT_HAM_WINDUP) {
        dy = -0.5f;  // เงื้อค้าง — ตัวยกลอยขึ้นทั้งตัว
    } else if (m->strike && stage == CT_HAM_STRIKE) {
        dy = 0.0f;  // แรงลง — ตัวหยุดนิ่งที่พื้น ที่ยุบคือ squash ไม่ใช่ dy
    }
    dy = roundf(dy * CT_SLOTS_UNIT_PX) / (float)CT_SLOTS_UNIT_PX;
    float dx = sinf(phase * (float)M_PI * 12.0f) * m->shake;

    // ท่ามุดหาย: ยิ่ง phase เดินหน้า ยิ่งแบนลงติดพื้นและขาหด
    float squash = m->squash + m->sink * phase * 0.60f;
    if (m->strike) {
        squash += stage == CT_HAM_WINDUP ? -0.04f : (stage == CT_HAM_STRIKE ? 0.15f : 0.03f);
    }

    ct_rects_t silhouette;
    ct_rects_reset(&silhouette);
    // แขนพิมพ์ — แขนข้างลำตัวสลับขึ้นลงสองรอบต่อลูป ไม่มีแขนพาดหน้าแล็ปท็อป
    // (แขนที่เอื้อมมาข้างหน้าอ่านเป็น "กดจอ" ไม่ใช่ "พิมพ์อยู่หลังจอ")
    float arm = m->arm * sinf(phase * (float)M_PI * 4.0f);
    // ยกค้างนิ่ง — ถ้าขยับขึ้นลงจะอ่านเป็นโบกมือ ไม่ใช่ยกค้างเพ่งพลัง
    float arm_lift = m->arm_up;
    body(&silhouette, body_c, arm - arm_lift, -arm - arm_lift, m->arm_out);
    legs(&silhouette, m->gait, phase, body_c, m->sink * phase * LEG_H * 0.9f);
    squashed(&silhouette, 0, squash);
    ct_rects_move_from(&silhouette, 0, dx, dy);

    eye_t eye_kind = m->eye;
    // หลับตาเบ่งตอนแรงลง — เฟรมสั้นๆ นี้คือที่ที่น้ำหนักอยู่
    if (m->strike && stage == CT_HAM_STRIKE) eye_kind = EYE_SQUINT;
    if (m->blink && cycle % BLINK_EVERY == BLINK_EVERY - 1 && phase >= BLINK_FROM &&
        phase < BLINK_TO) {
        eye_kind = EYE_BLINK;
    }

    ct_rects_reset(out);
    if (CT_MASCOT_OUTLINE > 0.0f) {
        ct_rects_outline_pass(out, &silhouette, CT_MASCOT_OUTLINE, edge);
    }
    for (int i = 0; i < silhouette.count; i++) {
        ct_rect_t r = silhouette.items[i];
        ct_rects_add(out, r.x, r.y, r.w, r.h, r.color);
    }

    // แท่นวางอยู่กับพื้น จึงไม่เลื่อนตาม dy ที่ลำตัวขยับ
    if (STATES[state].prop == CT_PROP_HAMMER) {
        ct_prop_hammer_anvil(out, phase, connected);
    }

    if (STATES[state].prop == CT_PROP_MAGNIFIER) {  // กระจกอยู่ใต้ตา ขอบเลนส์อยู่บนตา
        int glass_from = out->count;
        ct_prop_magnifier_glass(out, phase, connected);
        squashed(out, glass_from, squash);
        ct_rects_move_from(out, glass_from, dx, dy);
    }

    int eyes_from = out->count;
    float look = m->look * sinf(phase * (float)M_PI * 2.0f);
    // กวาดสายตา: ไล่จากซ้ายไปขวาแล้ววกกลับทันที = อ่านทีละบรรทัด ไม่ใช่ส่ายไปมา
    // สองบรรทัดต่อลูป — ช้ากว่านี้จะอ่านเป็นเหม่อ ไม่ใช่กำลังไล่โค้ด
    look += m->scan * (fmodf(phase * 2.0f, 1.0f) - 0.5f) * 2.0f;
    // ตาข้างที่อยู่หลังเลนส์แว่นขยายต้องโตกว่าอีกข้าง
    float mag = STATES[state].prop == CT_PROP_MAGNIFIER ? CT_EYE_MAG : 1.0f;
    eye(out, EYE_L, eye_kind, look, ink, 1.0f);
    eye(out, EYE_R, eye_kind, look, ink, mag);
    // ตายุบไปกับลำตัว ไม่ใช่ค้างอยู่บนหน้าที่เตี้ยลง
    squashed(out, eyes_from, squash);
    ct_rects_move_from(out, eyes_from, dx, dy);

    if (STATES[state].prop != CT_PROP_NONE) {
        int prop_from = out->count;
        ct_prop_build(out, STATES[state].prop, phase, connected);
        // หมวกกับค้อนอยู่ติดตัว จึงต้องต่ำลงพร้อมหัวที่ยุบ ไม่ใช่ค้างอยู่ที่เดิม
        // เลื่อนอย่างเดียวไม่ยุบตาม: หมวกแข็งและค้อนเป็นเหล็ก จะแบนไปกับตัวไม่ได้
        float prop_dy = dy + (m->strike ? FOOT_Y * squash : 0.0f);
        // ลูกโลกลอยนิ่งอยู่กับที่ ตัวเด้งผ่านมันไป — ใหญ่และคร่อมหัวอยู่แล้ว
        // ถ้าเด้งตามตัวด้วยจะอ่านเป็นก้อนที่ติดหัว ไม่ใช่ลูกโลกที่ลอยอยู่
        if (STATES[state].prop == CT_PROP_GLOBE) prop_dy = 0.0f;
        ct_rects_move_from(out, prop_from, dx, prop_dy);
    }

    // ท่าที่มีของประกอบเยอะจนแน่นช่อง — ย่อทั้งฉากโดยยึดฝ่าเท้าและกึ่งกลางลำตัว
    // ย่อพร้อมกันทั้งชุด สัดส่วนภายในจึงไม่เพี้ยน
    float k = state_scale(state);
    if (k != 1.0f) ct_rects_scale_from(out, 0, k, k, CT_HEAD_CX, FOOT_Y);
}

// --- จัดกึ่งกลาง ------------------------------------------------------------
// กรอบจริงของแต่ละสถานะ รวมทุกเฟรมของอนิเมชัน
// ท่าที่ไม่มี prop ถือจะแคบกว่าท่าที่มี ถ้าใช้กรอบรวมชุดเดียวตัวละครจะเอียงไปทางซ้าย
static float s_center_dx[CT_STATE_COUNT];

void ct_mascot_init(void)
{
    ct_rects_t frame;
    for (int s = 0; s < CT_STATE_COUNT; s++) {
        float x0 = 1e9f, x1 = -1e9f;
        for (int i = 0; i < 12; i++) {
            ct_mascot_build(&frame, (ct_state_t)s, i / 12.0f, true, 0);
            float fx0, fy0, fx1, fy1;
            ct_rects_bounds(&frame, &fx0, &fy0, &fx1, &fy1);
            if (fx0 < x0) x0 = fx0;
            if (fx1 > x1) x1 = fx1;
        }
        s_center_dx[s] = (CT_BOX_X0 + CT_BOX_X1) / 2.0f - (x0 + x1) / 2.0f;
    }
}

void ct_mascot_build_centered(ct_rects_t *out, ct_state_t state, float phase, bool connected,
                              int cycle)
{
    if (state < 0 || state >= CT_STATE_COUNT) state = CT_STATE_IDLE;
    ct_mascot_build(out, state, phase, connected, cycle);
    ct_rects_move_from(out, 0, s_center_dx[state], 0.0f);
}
