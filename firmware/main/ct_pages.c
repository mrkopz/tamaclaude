#include "ct_pages.h"

#include <stdio.h>

#include "ct_color.h"
#include "ct_fonts.h"
#include "ct_ui.h"
#include "ct_weather.h"
#include "ct_weather_ui.h"
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
static ct_weather_t s_weather;

// เศษเวลาที่ยังไม่ครบวินาที — นาฬิกาของหน้าเดินด้วยเวลาจริง ไม่ใช่ด้วยจำนวนเฟรม
static int s_since_second;
// นาฬิกาของ page rotation อยู่บนบอร์ด ไม่ใช่บน Mac — ถ้า Mac เป็นคนสั่งเปลี่ยนหน้า
// Mac ที่หลับก็เท่ากับจอค้างหน้าเดียวทั้งคืน
static int s_since_turn;

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

    // ฟอนต์ต้องพร้อมก่อนป้ายใบแรกของหน้าไหนก็ตาม — ป้ายถือ pointer ไปยังฟอนต์พวกนั้น
    ct_fonts_init();

    // เฟรมที่ยังไม่เคยได้ข้อมูลคือเฟรมว่าง ไม่ใช่หน่วยความจำที่ไม่ได้ตั้งค่า —
    // หน้ามาสคอตวาดสภาพนี้เป็นนาฬิกาตั้งโต๊ะอยู่แล้ว ส่วนหน้าอื่นมีหน้าตาของตัวเอง
    ct_model_clear(&s_mascot);
    ct_ui_init(s_pages[CT_PAGE_MASCOT].root, &s_mascot);

    ct_weather_ui_init(s_pages[CT_PAGE_WEATHER].root, &s_weather,
                       &s_pages[CT_PAGE_WEATHER].has_frame, &s_mascot);

    // หน้าที่แสดงอยู่คือหน้าเดียวที่ไม่ถูกซ่อน — การเปลี่ยนหน้าคือการย้ายธงใบนี้
    lv_obj_remove_flag(s_pages[s_active].root, LV_OBJ_FLAG_HIDDEN);
}

void ct_pages_set_snapshot(const ct_snapshot_t *snap)
{
    s_mascot = *snap;
    s_pages[CT_PAGE_MASCOT].has_frame = true;
    // เฟรมของหน้าที่ไม่ได้แสดงอยู่ก็เก็บไว้เหมือนกัน แค่ไม่มีอะไรให้วาด (ADR-0002)
    if (s_active == CT_PAGE_MASCOT) ct_ui_redraw();
    // มาสคอตจิ๋วบนหน้าอื่นอ่าน snapshot ก้อนเดียวกันนี้ — pose ที่รออนุญาตอยู่ต้องไม่
    // หายไปเพียงเพราะผู้ใช้กำลังดูหน้าอื่น
    if (s_active == CT_PAGE_WEATHER) ct_weather_ui_redraw();
}

bool ct_pages_set_frame(ct_page_kind_t kind, const char *json, int len)
{
    switch (kind) {
        case CT_PAGE_WEATHER:
            if (!ct_weather_parse(json, len, &s_weather)) return false;
            s_pages[CT_PAGE_WEATHER].has_frame = true;
            if (s_active == CT_PAGE_WEATHER) ct_weather_ui_redraw();
            return true;
        default:
            // หน้ามาสคอตไม่เดินทางมาทางนี้ (เฟรมของมันไม่มีคีย์ `g`) และชนิดที่ firmware
            // ยังไม่รู้จักคือ daemon ที่ใหม่กว่า — ทิ้งเฟรมไป ไม่ใช่วาดมั่ว
            return false;
    }
}

void ct_pages_forget(ct_page_kind_t kind)
{
    if (kind <= CT_PAGE_MASCOT || kind >= CT_PAGE_KIND_COUNT) return;  // มาสคอตปิดไม่ได้
    s_pages[kind].has_frame = false;
    if (kind == CT_PAGE_WEATHER) {
        ct_weather_t empty = {0};
        empty.unit = 'C';
        s_weather = empty;
    }
    // หน้าที่เพิ่งถูกถอนออกจากรอบอาจเป็นหน้าที่กำลังแสดงอยู่ — กลับไปหน้ามาสคอตทันที
    // ดีกว่าค้างอยู่บนหน้าที่เพิ่งกลายเป็น "ยังไม่เคยได้ข้อมูล"
    if (s_active == kind) {
        lv_obj_add_flag(s_pages[s_active].root, LV_OBJ_FLAG_HIDDEN);
        s_active = CT_PAGE_MASCOT;
        lv_obj_remove_flag(s_pages[s_active].root, LV_OBJ_FLAG_HIDDEN);
        s_since_turn = 0;
        ct_ui_redraw();
    }
}

int ct_pages_capability_json(char *out, int size)
{
    // ประกาศเป็นความสามารถ ไม่ใช่เลขเวอร์ชัน (ADR-0006) — แอปใหม่กับ firmware เก่า
    // เป็นสภาพปกติ ไม่ใช่กรณีขอบ
    //
    // นับความยาวจากสิ่งที่ *เขียนลงไปจริง* ไม่ใช่จากค่าที่ snprintf คืน: ค่าที่มันคืนคือ
    // ความยาวที่ข้อความจะมีถ้าที่พอ ตอนถูกตัดมันจึงโตกว่าที่เขียนจริง แล้วผู้เรียกจะส่ง
    // ไบต์ที่ไม่เคยถูกเขียนออกไปบนสาย
    if (size <= 0) return 0;
    int n = snprintf(out, size, "{\"t\":\"cap\",\"p\":[");
    if (n < 0 || n >= size) return 0;
    for (int i = 0; i < CT_PAGE_KIND_COUNT; i++) {
        int wrote = snprintf(out + n, size - n, i ? ",%d" : "%d", i);
        if (wrote < 0 || wrote >= size - n) return n;  // ที่ไม่พอ = ตัดตรงที่ยังถูกต้อง
        n += wrote;
    }
    int wrote = snprintf(out + n, size - n, "]}");
    if (wrote < 0 || wrote >= size - n) return n;
    return n + wrote;
}

void ct_pages_set_connected(bool connected)
{
    ct_ui_set_connected(connected);
    ct_weather_ui_set_connected(connected);
}

void ct_pages_set_link(bool ble, bool wifi, const char *ip)
{
    ct_ui_set_link(ble, wifi, ip);
}

// หน้าที่มีสิทธิ์อยู่ในรอบ — หน้าที่ยังไม่เคยได้ข้อมูลไม่ถูกหมุนไปหา
//
// หน้ามาสคอตอยู่ในรอบเสมอแม้ยังไม่เคยได้ snapshot: มันมีสภาพ "ยังไม่ได้คุยกับ Mac"
// เป็นของตัวเอง (นาฬิกาตั้งโต๊ะสีเทา) ซึ่งเป็นสิ่งที่ผู้ใช้ต้องเห็น ไม่ใช่สิ่งที่ต้องซ่อน
static bool in_rotation(ct_page_kind_t kind)
{
    return kind == CT_PAGE_MASCOT || s_pages[kind].has_frame;
}

static void turn_page(void)
{
    ct_page_kind_t next = s_active;
    for (int i = 1; i < CT_PAGE_KIND_COUNT; i++) {
        ct_page_kind_t candidate = (ct_page_kind_t)((s_active + i) % CT_PAGE_KIND_COUNT);
        if (in_rotation(candidate)) {
            next = candidate;
            break;
        }
    }
    if (next == s_active) return;  // มีหน้าเดียวที่พร้อมแสดง = ไม่มีอะไรให้หมุน

    lv_obj_add_flag(s_pages[s_active].root, LV_OBJ_FLAG_HIDDEN);
    s_active = next;
    lv_obj_remove_flag(s_pages[s_active].root, LV_OBJ_FLAG_HIDDEN);

    // หน้าที่เพิ่งขึ้นมาถือของที่อาจเก่ากว่าตอนที่มันถูกซ่อนไป — วาดใหม่ทั้งใบก่อนเสมอ
    if (s_active == CT_PAGE_MASCOT) {
        ct_ui_redraw();
    } else if (s_active == CT_PAGE_WEATHER) {
        ct_weather_ui_redraw();
    }
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
    // อายุข้อมูลเดินด้วยเหตุผลเดียวกัน และเป็นเหตุผลที่เฟรมพก *อายุ* มา ไม่ใช่เวลาสัมบูรณ์:
    // บอร์ดไม่มีนาฬิกาที่ตั้งเวลาไว้ แต่นับต่อจากเลขที่ได้มาได้เสมอ
    if (second_passed && s_pages[CT_PAGE_WEATHER].has_frame) {
        ct_weather_tick(&s_weather, 1);
        if (s_active == CT_PAGE_WEATHER) ct_weather_ui_redraw_age();
    }

    // อนิเมชันเดินเฉพาะหน้าที่แสดงอยู่ และเดินด้วยเวลาก้อนเดียวกับนาฬิกาข้างบน
    if (s_active == CT_PAGE_MASCOT) {
        ct_ui_tick(elapsed_ms);
    } else if (s_active == CT_PAGE_WEATHER) {
        ct_weather_ui_tick(elapsed_ms);
    }

    s_since_turn += elapsed_ms;
    if (s_since_turn >= CT_ROTATION_SECONDS * 1000) {
        s_since_turn = 0;
        turn_page();
    }
}
