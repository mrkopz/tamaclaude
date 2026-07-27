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
#define NUB_H 1.9f
#define NUB_W 1.0f
#define LEG_TOP 8.0f
#define LEG_H 3.2f
#define EYE_L 3.36f
#define EYE_R 10.64f
#define EYE_Y 2.10f
#define EYE_S 2.0f

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
    bool blink;    // ตาลืมเท่านั้นที่กะพริบได้
    float sink;    // >0 = จมลงดินตามความคืบหน้าของ phase (ท่ามุดหาย)
} mood_t;

typedef enum {
    MOOD_IDLE, MOOD_WORKING, MOOD_WALKING, MOOD_WAITING, MOOD_SLEEPING,
    MOOD_ALERT, MOOD_CELEBRATE, MOOD_ERROR, MOOD_ENTERING, MOOD_LEAVING,
    MOOD_COUNT,
} mood_id_t;

static const mood_t MOODS[MOOD_COUNT] = {
    [MOOD_IDLE]      = {EYE_OPEN,   GAIT_STAND, 0.00f, 0.20f, 1.0f, 0.00f, 0.00f, true,  0.0f},
    [MOOD_WORKING]   = {EYE_FOCUS,  GAIT_STAND, 0.03f, 0.15f, 2.4f, 0.00f, 0.00f, true,  0.0f},
    [MOOD_WALKING]   = {EYE_OPEN,   GAIT_WALK,  0.00f, 0.22f, 2.0f, 0.00f, 0.00f, true,  0.0f},
    [MOOD_WAITING]   = {EYE_OPEN,   GAIT_STAND, 0.00f, 0.28f, 0.7f, 0.00f, 0.40f, true,  0.0f},
    [MOOD_SLEEPING]  = {EYE_SLEEP,  GAIT_SIT,   0.10f, 0.10f, 0.35f, 0.00f, 0.00f, false, 0.0f},
    [MOOD_ALERT]     = {EYE_WIDE,   GAIT_STAND, 0.00f, 0.48f, 3.2f, 0.20f, 0.00f, false, 0.0f},
    [MOOD_CELEBRATE] = {EYE_HAPPY,  GAIT_STAND, -0.05f, 0.88f, 2.6f, 0.00f, 0.00f, false, 0.0f},
    [MOOD_ERROR]     = {EYE_DEAD,   GAIT_SIT,   0.12f, 0.00f, 1.0f, 0.08f, 0.00f, false, 0.0f},
    // ท่าเปลี่ยนผ่าน — phase ทำหน้าที่เป็นความคืบหน้า 0->1 ไม่ใช่ลูปวน
    [MOOD_ENTERING]  = {EYE_OPEN,   GAIT_WALK,  0.00f, 0.30f, 4.0f, 0.00f, 0.00f, true,  0.0f},
    [MOOD_LEAVING]   = {EYE_SQUINT, GAIT_SIT,   0.30f, 0.00f, 1.0f, 0.00f, 0.00f, false, 1.0f},
};

// visual state = mood + prop — ต้องตรงกับ STATES ใน tools/gen/mascot.py
static const struct {
    mood_id_t mood;
    ct_prop_t prop;
} STATES[CT_STATE_COUNT] = {
    [CT_STATE_IDLE]      = {MOOD_IDLE,      CT_PROP_NONE},
    [CT_STATE_READING]   = {MOOD_WORKING,   CT_PROP_MAGNIFIER},
    [CT_STATE_WRITING]   = {MOOD_WORKING,   CT_PROP_PENCIL},
    [CT_STATE_BUILDING]  = {MOOD_WORKING,   CT_PROP_HAMMER},
    [CT_STATE_SEARCHING] = {MOOD_WORKING,   CT_PROP_GLOBE},
    [CT_STATE_THINKING]  = {MOOD_IDLE,      CT_PROP_DOTS},
    [CT_STATE_WAITING]   = {MOOD_WAITING,   CT_PROP_QUERY},
    [CT_STATE_SLEEPING]  = {MOOD_SLEEPING,  CT_PROP_ZZZ},
    [CT_STATE_ALERT]     = {MOOD_ALERT,     CT_PROP_BANG},
    [CT_STATE_CELEBRATE] = {MOOD_CELEBRATE, CT_PROP_SPARKLE},
    [CT_STATE_ERROR]     = {MOOD_ERROR,     CT_PROP_NONE},
    [CT_STATE_ENTERING]  = {MOOD_ENTERING,  CT_PROP_NONE},
    [CT_STATE_LEAVING]   = {MOOD_LEAVING,   CT_PROP_NONE},
};

// --- ตา ---------------------------------------------------------------------
// ตาหนึ่งข้าง กล่องฐาน EYE_S x EYE_S ที่ (x, EYE_Y) — ทุกค่าอิงสัดส่วน ไม่ฝังตัวเลขดิบ
static void eye(ct_rects_t *o, float x, eye_t kind, float look, uint16_t ink)
{
    const float s = EYE_S, y = EYE_Y;
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
// squash > 0 = เตี้ยลงกว้างขึ้น (ยึดฝ่าเท้าเป็นหลัก)
static void body(ct_rects_t *o, float squash, uint16_t color)
{
    float nh = BODY_H * (1.0f - squash);
    float nw = BODY_W * (1.0f + squash * 0.45f);
    float nx = BODY_X - (nw - BODY_W) / 2.0f;
    float ny = BODY_Y + (BODY_H - nh);
    float ncx = nx + nw;
    float nub_dy = (NUB_Y - BODY_Y) * (nh / BODY_H);
    ct_rects_add(o, nx, ny, nw, nh, color);
    ct_rects_add(o, nx - NUB_W, ny + nub_dy, NUB_W, NUB_H, color);
    ct_rects_add(o, ncx, ny + nub_dy, NUB_W, NUB_H, color);
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

    float dy = -fabsf(sinf(phase * (float)M_PI * m->bob_hz)) * m->bob;
    float dx = sinf(phase * (float)M_PI * 12.0f) * m->shake;

    // ท่ามุดหาย: ยิ่ง phase เดินหน้า ยิ่งแบนลงติดพื้นและขาหด
    float squash = m->squash + m->sink * phase * 0.60f;

    ct_rects_t silhouette;
    ct_rects_reset(&silhouette);
    body(&silhouette, squash, body_c);
    legs(&silhouette, m->gait, phase, body_c, m->sink * phase * LEG_H * 0.9f);
    ct_rects_move_from(&silhouette, 0, dx, dy);

    eye_t eye_kind = m->eye;
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

    // ตาเลื่อนตามลำตัวที่ถูก squash
    int eyes_from = out->count;
    float look = m->look * sinf(phase * (float)M_PI * 2.0f);
    eye(out, EYE_L, eye_kind, look, ink);
    eye(out, EYE_R, eye_kind, look, ink);
    ct_rects_move_from(out, eyes_from, dx, dy + BODY_H * squash);

    if (STATES[state].prop != CT_PROP_NONE) {
        int prop_from = out->count;
        ct_prop_build(out, STATES[state].prop, phase, connected);
        ct_rects_move_from(out, prop_from, dx, dy);
    }
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
