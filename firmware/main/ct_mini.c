#include "ct_mini.h"

#include "ct_mascot.h"
#include "ct_paint.h"
#include "ct_rects.h"
#include "layout.h"

// หนึ่งลูปอนิเมชันยาวเท่าไร (ms) — ค่าเดียวกับหน้ามาสคอต
#define LOOP_MS 1000

// ทุกหน้ายกเว้นหน้ามาสคอตพกได้หน้าละหนึ่งใบ
#define MAX_ATTACHED (CT_PAGE_KIND_COUNT - 1)

static const ct_snapshot_t *s_mascot;
static bool s_connected;

static lv_obj_t *s_attached[MAX_ATTACHED];
static int s_count;

static float s_phase;
static int s_cycle;

// rect list ชุดเดิมที่ย่อลงผ่าน ct_rects_scale_from() ไม่มีอาร์ตใหม่ ไม่มีท้องฟ้า
// ไม่มี prop ที่ต้องเว้นที่ให้
//
// ท่าของแต่ละ session ถูกหน่วงด้วย Timings.minPose ที่ daemon มาแล้ว ที่นี่จึงไม่หน่วงซ้ำ
// สิ่งที่กระโดดได้ทันทีคือตอน session *คนละตัว* ขึ้นมาเป็นตัวนำ ซึ่งเป็นข้อยกเว้นเดียวกับ
// ที่ daemon มีอยู่แล้ว (priority สูงกว่าแทรกได้ทันที) — การรออนุญาตที่รอห้าวินาทีก่อน
// จะขึ้นจอคือการเตือนที่มาช้าโดยไม่มีเหตุผล
static void mini_draw_cb(lv_event_t *e)
{
    // ไม่มี Mac = ไม่มีมาสคอต ซึ่งต่างจากมาสคอตที่หลับ (= ไม่มี session)
    // สองสถานะนี้ต้องแยกออกจากกัน ไม่งั้นจอเงียบสองแบบดูเหมือนกัน
    if (!s_connected) return;

    lv_obj_t *obj = lv_event_get_target_obj(e);
    lv_layer_t *layer = lv_event_get_layer(e);
    lv_area_t coords;
    lv_obj_get_coords(obj, &coords);

    ct_rects_t rects;
    ct_mascot_build_centered(&rects, ct_model_lead_state(s_mascot), s_phase, true, s_cycle);
    const float scale = CT_PAGE_MINI_UNIT_PX / CT_SLOTS_UNIT_PX;
    ct_rects_scale_from(&rects, 0, scale, scale, 0.0f, 0.0f);

    // ฝ่าเท้าเกาะขอบล่างของผืน ไม่ใช่ขอบบน — ตัวที่กระโดดต้องกระโดดขึ้น
    float px = CT_SLOTS_UNIT_PX;
    float oy = coords.y2 + 1 - CT_BOX_Y1 * scale * px;
    float ox = coords.x1 - CT_BOX_X0 * scale * px;
    ct_paint_rects(layer, &rects, ox, oy, px);
}

void ct_mini_init(const ct_snapshot_t *mascot) { s_mascot = mascot; }

lv_obj_t *ct_mini_attach(lv_obj_t *parent)
{
    int w = (int)((CT_BOX_X1 - CT_BOX_X0) * CT_PAGE_MINI_UNIT_PX) + 1;
    int h = (int)((CT_BOX_Y1 - CT_BOX_Y0) * CT_PAGE_MINI_UNIT_PX) + 1;

    lv_obj_t *obj = lv_obj_create(parent);
    lv_obj_remove_style_all(obj);
    lv_obj_set_size(obj, w, h);
    lv_obj_set_pos(obj, CT_SCREEN_WIDTH - CT_PAGE_MINI_RIGHT - w, CT_PAGE_MINI_BOTTOM_Y - h);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(obj, mini_draw_cb, LV_EVENT_DRAW_MAIN, NULL);

    // เพดานเท่ากับจำนวนหน้าพอดี หน้าละใบ — ใบที่เกินมาคือหน้าที่ attach สองครั้ง ซึ่งเป็นบั๊ก
    // ที่เห็นได้ทันทีบนจอ (มาสคอตสองตัวซ้อนกัน) ไม่ใช่สิ่งที่ต้องรายงาน
    if (s_count < MAX_ATTACHED) s_attached[s_count++] = obj;
    return obj;
}

// ผืนของหน้าที่ถูกซ่อนอยู่ก็ถูกสั่งวาดใหม่ด้วย เพราะ LVGL ไม่วาดของที่ซ่อนอยู่จริงๆ อยู่แล้ว
// การไล่ดูว่าหน้าไหนแสดงอยู่ที่นี่แปลว่า `ct_mini` ต้องรู้จักตัวโฮสต์ ซึ่งแพงกว่าที่ประหยัดได้
static void invalidate_all(void)
{
    for (int i = 0; i < s_count; i++) lv_obj_invalidate(s_attached[i]);
}

void ct_mini_set_connected(bool connected)
{
    if (connected == s_connected) return;
    s_connected = connected;
    invalidate_all();
}

void ct_mini_tick(int elapsed_ms)
{
    s_phase += (float)elapsed_ms / (float)LOOP_MS;
    while (s_phase >= 1.0f) {
        s_phase -= 1.0f;
        s_cycle++;
    }
    invalidate_all();
}
