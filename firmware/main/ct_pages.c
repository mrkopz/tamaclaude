#include "ct_pages.h"

#include "ct_color.h"
#include "ct_ui.h"
#include "layout.h"
#include "lvgl.h"

// สิ่งที่ทุกหน้ามีเหมือนกัน — ส่วนตัว page frame เองมีรูปร่างต่างกันตามชนิด (ADR-0003)
// จึงเก็บแยกเป็นตัวแปรของแต่ละหน้า ไม่ใช่ union ที่มีสมาชิกเดียว
typedef struct {
    lv_obj_t *root;  // ทุก widget ของหน้าอยู่ใต้ตัวนี้ — ซ่อนทั้งหน้าด้วยการซ่อนตัวเดียว
    bool has_frame;
} ct_page_t;

static ct_page_t s_pages[CT_PAGE_KIND_COUNT];
static ct_page_kind_t s_active = CT_PAGE_MASCOT;

// page frame ของหน้ามาสคอต — `Snapshot` เดิมทั้งดุ้น ไม่ได้ถูกแตะเพราะมีหลายหน้า
static ct_snapshot_t s_mascot;

// เศษเวลาที่ยังไม่ครบวินาที — นาฬิกาของหน้าเดินด้วยเวลาจริง ไม่ใช่ด้วยจำนวนเฟรม
static int s_since_second;

// ผืนเต็มจอไร้ style: พิกัดของลูกจึงเท่ากับพิกัดบนจอ และการเปลี่ยนหน้าไม่ต้องแตะ widget ใด
static lv_obj_t *make_root(lv_obj_t *scr)
{
    lv_obj_t *root = lv_obj_create(scr);
    lv_obj_remove_style_all(root);
    lv_obj_set_size(root, CT_SCREEN_WIDTH, CT_SCREEN_HEIGHT);
    lv_obj_set_pos(root, 0, 0);
    lv_obj_remove_flag(root, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(root, LV_OBJ_FLAG_HIDDEN);
    return root;
}

void ct_pages_init(void)
{
    lv_obj_t *scr = lv_screen_active();
    lv_obj_remove_style_all(scr);
    lv_obj_set_style_bg_color(scr, ct_color(CT_COL_BG), 0);
    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);
    lv_obj_remove_flag(scr, LV_OBJ_FLAG_SCROLLABLE);

    for (int i = 0; i < CT_PAGE_KIND_COUNT; i++) {
        s_pages[i].root = make_root(scr);
        s_pages[i].has_frame = false;
    }

    // เฟรมที่ยังไม่เคยได้ข้อมูลคือเฟรมว่าง ไม่ใช่หน่วยความจำที่ไม่ได้ตั้งค่า —
    // หน้ามาสคอตวาดสภาพนี้เป็นนาฬิกาตั้งโต๊ะอยู่แล้ว
    ct_model_clear(&s_mascot);
    ct_ui_init(s_pages[CT_PAGE_MASCOT].root, &s_mascot);

    // หน้าที่แสดงอยู่คือหน้าเดียวที่ไม่ถูกซ่อน — การเปลี่ยนหน้าคือการย้ายธงใบนี้
    lv_obj_remove_flag(s_pages[s_active].root, LV_OBJ_FLAG_HIDDEN);
}

void ct_pages_set_snapshot(const ct_snapshot_t *snap)
{
    s_mascot = *snap;
    s_pages[CT_PAGE_MASCOT].has_frame = true;
    // เฟรมของหน้าที่ไม่ได้แสดงอยู่ก็เก็บไว้เหมือนกัน แค่ไม่มีอะไรให้วาด (ADR-0002)
    if (s_active == CT_PAGE_MASCOT) ct_ui_redraw();
}

void ct_pages_set_connected(bool connected) { ct_ui_set_connected(connected); }

void ct_pages_set_link(bool ble, bool wifi, const char *ip)
{
    ct_ui_set_link(ble, wifi, ip);
}

void ct_pages_tick(int elapsed_ms)
{
    bool second_passed = false;
    s_since_second += elapsed_ms;
    while (s_since_second >= 1000) {
        s_since_second -= 1000;
        second_passed = true;
    }

    // countdown เดินด้วยนาฬิกาของบอร์ดเอง ไม่ใช่ตามจังหวะที่ snapshot มาถึง — เวลารีเซ็ต
    // เป็นค่าสัมบูรณ์ ลิงก์หลุดแล้วตัวเลขนี้ยังจริง ส่วนเปอร์เซ็นต์หยุดนิ่ง (ซึ่งถูก มันหยุดจริง)
    // เดินที่โฮสต์เพราะเวลาของหน้าที่ไม่ได้แสดงอยู่ก็ต้องเดินเหมือนกัน
    if (second_passed && s_pages[CT_PAGE_MASCOT].has_frame) {
        ct_model_tick_usage(&s_mascot, 1);
        if (s_active == CT_PAGE_MASCOT) ct_ui_redraw_usage();
    }

    // อนิเมชันเดินเฉพาะหน้าที่แสดงอยู่ และเดินด้วยเวลาก้อนเดียวกับนาฬิกาข้างบน
    if (s_active == CT_PAGE_MASCOT) ct_ui_tick(elapsed_ms);
}
