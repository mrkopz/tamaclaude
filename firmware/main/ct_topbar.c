#include "ct_topbar.h"

#include "ct_color.h"
#include "ct_fonts.h"
#include "ct_ui.h"
#include "layout.h"
#include "lvgl.h"

// แถบโควตาย่อ — ตรงกับ tools/gen/topbar.py:draw
#define USAGE_TOP_W 34
#define USAGE_TOP_H 6

// ทุกอย่างที่เกาะขอบขวาของแถบเริ่มนับจากตรงนี้ ไม่ใช่จากขอบจอ — ไอคอนลิงก์จองที่
// ขวาสุดไว้ถาวร ค่าคงที่ตัวเดียวจึงต้องเลื่อนนาฬิกา "+N" และแถบโควตาไปพร้อมกัน
#define TOPBAR_RIGHT (6 + CT_TOPBAR_LINK_ICON_W + CT_TOPBAR_LINK_ICON_GAP)

// ความกว้างที่แต่ละชิ้นจองไว้ก่อนส่งต่อให้ชิ้นถัดไปทางซ้าย — ต้องตรงกับ `right -= N`
// ใน tools/gen/topbar.py ทีละบรรทัด
#define CLOCK_W 38
#define OVERFLOW_W 26
#define USAGE_PCT_W 30

// ไอคอนลิงก์เป็นรายการสี่เหลี่ยมเหมือนของอื่นทั้งจอ ไม่ใช่ glyph จากฟอนต์ —
// ต้องตรงกับ tools/gen/topbar.py:_ICON_* เป๊ะทั้งพิกัดและสี
typedef struct {
    uint8_t x, y, w, h;
} icon_rect_t;

// BLE = แท่งไต่ขึ้น (ทางหลัก) · WiFi = คลื่นซ้อน (ทางสำรอง) · ขาด = ขีดเดียวจางๆ
// สามรูปทรงคนละวงศ์ ไม่ใช่รูปเดียวคนละสี — จอนี้ถูกมองจากอีกฝั่งห้องเป็นหลัก
static const icon_rect_t ICON_BLE[] = {{0, 6, 3, 3}, {4, 3, 3, 6}, {8, 0, 3, 9}};
static const icon_rect_t ICON_WIFI[] = {{0, 0, 11, 2}, {2, 3, 7, 2}, {4, 6, 3, 3}};
static const icon_rect_t ICON_NONE[] = {{1, 4, 9, 2}};
#define LINK_ICON_PARTS 3

static const ct_snapshot_t *s_frame;
static bool s_connected;
static ct_page_kind_t s_page = CT_PAGE_MASCOT;

static lv_obj_t *s_dot, *s_link, *s_clock, *s_overflow, *s_usage_pct;
static lv_obj_t *s_link_icon[LINK_ICON_PARTS];
static lv_obj_t *s_usage_track, *s_usage_fill;

static lv_obj_t *plain_obj(lv_obj_t *parent, int w, int h)
{
    lv_obj_t *o = lv_obj_create(parent);
    lv_obj_remove_style_all(o);
    lv_obj_set_size(o, w, h);
    lv_obj_remove_flag(o, LV_OBJ_FLAG_SCROLLABLE);
    return o;
}

static lv_obj_t *plain_label(lv_obj_t *parent, const lv_font_t *font, uint16_t color)
{
    lv_obj_t *l = lv_label_create(parent);
    lv_obj_set_style_text_font(l, font, 0);
    lv_obj_set_style_text_color(l, ct_color(color), 0);
    lv_label_set_text(l, "");
    return l;
}

static void show(lv_obj_t *o, bool visible)
{
    if (visible) {
        lv_obj_remove_flag(o, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(o, LV_OBJ_FLAG_HIDDEN);
    }
}

// กติกาที่ต้องเป็นจริงพร้อมกันกับ tools/gen/topbar.py: แถบไม่พูดซ้ำสิ่งที่หน้านั้นแสดง
// ใหญ่กว่าอยู่แล้ว — หน้ามาสคอตตอบเองว่าตอนนี้มันแสดงอะไรอยู่ (`ct_ui_shows_*`)
// ส่วนหน้าอื่นไม่เคยแสดงเวลาหรือโควตาเอง จึงได้ครบตลอด
static bool page_shows_clock(void)
{
    return s_page == CT_PAGE_MASCOT && ct_ui_shows_clock();
}

static bool page_shows_usage(void)
{
    return s_page == CT_PAGE_MASCOT && ct_ui_shows_usage();
}

void ct_topbar_init(lv_obj_t *scr, const ct_snapshot_t *mascot)
{
    s_frame = mascot;
    ct_fonts_init();  // ป้ายถือ pointer ไปยังฟอนต์ — ต้องพร้อมก่อนป้ายใบแรก

    lv_obj_t *bar = plain_obj(scr, CT_SCREEN_WIDTH, CT_TOPBAR_HEIGHT);
    lv_obj_set_pos(bar, 0, 0);
    lv_obj_set_style_bg_color(bar, ct_color(CT_COL_BG_SLOT), 0);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, 0);

    s_dot = plain_obj(bar, 6, 6);
    lv_obj_set_pos(s_dot, 6, CT_TOPBAR_HEIGHT / 2 - 3);
    lv_obj_set_style_bg_opa(s_dot, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(s_dot, ct_color(CT_COL_GRAY), 0);

    s_link = plain_label(bar, &lv_font_montserrat_12, CT_COL_TEXT_DIM);
    lv_obj_align(s_link, LV_ALIGN_LEFT_MID, 17, 0);
    lv_label_set_text(s_link, "no link");

    // ไอคอนลิงก์: สามชิ้นพอสำหรับทุกรูปทรง ชิ้นที่เกินก็ซ่อนไป — สร้างครั้งเดียวแล้ว
    // ขยับ ไม่ใช่สร้าง/ลบทุกครั้งที่ลิงก์เปลี่ยน ซึ่งบนจอที่กะพริบอยู่แล้วจะเห็นเป็นสะดุด
    for (int i = 0; i < LINK_ICON_PARTS; i++) {
        s_link_icon[i] = plain_obj(bar, 1, 1);
        lv_obj_set_style_bg_opa(s_link_icon[i], LV_OPA_COVER, 0);
        lv_obj_add_flag(s_link_icon[i], LV_OBJ_FLAG_HIDDEN);
    }

    s_clock = plain_label(bar, &lv_font_montserrat_12, CT_COL_TEXT);
    s_overflow = plain_label(bar, &lv_font_montserrat_12, CT_COL_ACCENT);

    // โควตาบนแถบไม่มีป้ายกำกับ ("5h") เพราะมีค่าเดียว ไม่ต้องบอกว่าตัวไหน
    // เอาพื้นที่นั้นไปทำแถบสั้นแทน ซึ่งเหลือบแล้วรู้ทันทีโดยไม่ต้องอ่านตัวเลข
    s_usage_pct = plain_label(bar, &lv_font_montserrat_12, CT_COL_GOOD);
    lv_obj_add_flag(s_usage_pct, LV_OBJ_FLAG_HIDDEN);

    // กรอบขาวรอบราง — พื้นรางสีเดียวกับพื้นหลังจอ ทำให้ส่วนที่ยังไม่ถูกใช้กลืนหาย
    // เห็นแต่ "ใช้ไปเท่าไร" ไม่เห็น "เหลือเท่าไร" กรอบตีขอบให้รู้ความยาวเต็ม
    s_usage_track = plain_obj(bar, USAGE_TOP_W + 2, USAGE_TOP_H + 2);
    lv_obj_set_style_bg_color(s_usage_track, ct_color(CT_COL_BG), 0);
    lv_obj_set_style_bg_opa(s_usage_track, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(s_usage_track, 1, 0);
    lv_obj_set_style_border_color(s_usage_track, ct_color(CT_COL_OUTLINE), 0);
    lv_obj_set_style_border_opa(s_usage_track, LV_OPA_COVER, 0);
    lv_obj_add_flag(s_usage_track, LV_OBJ_FLAG_HIDDEN);

    s_usage_fill = plain_obj(s_usage_track, USAGE_TOP_W, USAGE_TOP_H);
    lv_obj_set_style_bg_opa(s_usage_fill, LV_OPA_COVER, 0);
    lv_obj_set_pos(s_usage_fill, 0, 0);

    ct_topbar_redraw();
}

void ct_topbar_set_page(ct_page_kind_t kind)
{
    s_page = kind;
    ct_topbar_redraw();
}

void ct_topbar_redraw(void)
{
    // ป้ายซ้ายบอกว่ากำลังดูหน้าไหน — ยกเว้นตอนหลุด ซึ่งเป็นสิ่งเดียวบนแถบที่ต้องอ่าน
    // เป็น *คำ* จุดเทากับไอคอนขีดเดียวเป็นสัญญาณเงียบเกินกว่าจะแบกเรื่องนี้คนเดียว
    // (ตรงกับ tools/gen/topbar.py:draw)
    lv_label_set_text(s_link, s_connected ? ct_page_labels[s_page] : "no link");

    // ชิ้นที่ถูกซ่อนต้องไม่ทิ้งช่องว่างไว้ — ชิ้นถัดไปเลื่อนมาแทนที่ ไม่ใช่อยู่พิกัดตายตัว
    // (หน้ามาสคอตตอน idle ซ่อนนาฬิกาบนแถบ แล้วโควตาต้องมานั่งตรงนั้น)
    int right = TOPBAR_RIGHT;

    bool clock_shown = !page_shows_clock();
    if (clock_shown) {
        lv_label_set_text(s_clock, s_frame->clock);
        // เลขที่ค้างเป็นเทา ไม่ใช่ "--:--" — เทา = ค้าง ไม่ใช่หาย เหมือนมาสคอตที่หลุด
        lv_obj_set_style_text_color(s_clock,
                                    ct_color(s_connected ? CT_COL_TEXT : CT_COL_GRAY), 0);
        lv_obj_align(s_clock, LV_ALIGN_RIGHT_MID, -right, 0);
        right += CLOCK_W;
    }
    show(s_clock, clock_shown);

    bool overflow_shown = s_frame->overflow > 0;
    if (overflow_shown) {
        lv_label_set_text_fmt(s_overflow, "+%d", s_frame->overflow);
        lv_obj_align(s_overflow, LV_ALIGN_RIGHT_MID, -right, 0);
        right += OVERFLOW_W;
    }
    show(s_overflow, overflow_shown);

    // หลุดลิงก์แล้วโควตาหายทั้งชุด (ไม่ใช่แค่หรี่เหมือนนาฬิกา): เปอร์เซ็นต์ที่ค้างอ่านผิด
    // เป็นเงินได้ ส่วนเวลาที่ผิดรู้ทันที — ตรงกับ `usage_shown` ใน ct_ui.c
    bool usage_shown = s_connected && s_frame->has_usage && !page_shows_usage();
    show(s_usage_pct, usage_shown);
    show(s_usage_track, usage_shown);
    if (!usage_shown) return;

    // หน้าต่าง 5 ชม. เท่านั้น — ตัวที่ขยับเร็วพอจะเปลี่ยนการตัดสินใจภายในวันเดียว
    const ct_usage_t *u = &s_frame->usage[0];
    uint16_t col = ct_ui_usage_color(u->percent);
    if (u->percent < 0) {
        lv_label_set_text(s_usage_pct, "--%");
    } else {
        lv_label_set_text_fmt(s_usage_pct, "%d%%", u->percent);
    }
    lv_obj_set_style_text_color(s_usage_pct, ct_color(col), 0);
    lv_obj_align(s_usage_pct, LV_ALIGN_RIGHT_MID, -right, 0);
    right += USAGE_PCT_W;

    // align จัดที่ *ขอบขวา* ของ track ให้เอง — ไม่ต้องหักความกว้างแถบออกอีก
    // (ฝั่ง Pillow ต้องหักเองเพราะวาดจากมุมซ้ายบน) ตรงกับ tools/gen/topbar.py
    lv_obj_align(s_usage_track, LV_ALIGN_RIGHT_MID, -right, 0);

    // เปอร์เซ็นต์ที่ไม่รู้ = แถบว่าง ไม่ใช่แถบศูนย์ที่ดูเหมือนข้อมูลจริง
    int pct = u->percent > 100 ? 100 : u->percent;
    int w = pct < 0 ? 0 : (USAGE_TOP_W * pct + 50) / 100;
    show(s_usage_fill, w > 0);
    if (w > 0) {
        lv_obj_set_width(s_usage_fill, w);
        lv_obj_set_style_bg_color(s_usage_fill, ct_color(col), 0);
    }
}

void ct_topbar_set_connected(bool connected)
{
    if (connected == s_connected) return;
    s_connected = connected;
    lv_obj_set_style_bg_color(s_dot, ct_color(connected ? CT_COL_GOOD : CT_COL_GRAY), 0);
    // สีของป้ายตอบคนละคำถามกับข้อความของมัน: ข้อความบอกว่าดูหน้าไหนอยู่ สีบอกว่า
    // ตัวเลขบนจอยังสดไหม
    lv_obj_set_style_text_color(s_link,
                                ct_color(connected ? CT_COL_TEXT : CT_COL_TEXT_DIM), 0);
    ct_topbar_redraw();
}

void ct_topbar_set_link(bool ble, bool wifi)
{
    const icon_rect_t *parts = ICON_NONE;
    int count = 1;
    uint16_t col = CT_COL_TEXT_DIM;
    if (ble) {
        parts = ICON_BLE;
        count = 3;
        col = CT_COL_GOOD;
    } else if (wifi) {
        parts = ICON_WIFI;
        count = 3;
        col = CT_COL_ACCENT;
    }

    const int x0 = CT_SCREEN_WIDTH - 6 - CT_TOPBAR_LINK_ICON_W;
    const int y0 = (CT_TOPBAR_HEIGHT - CT_TOPBAR_LINK_ICON_H) / 2;
    for (int i = 0; i < LINK_ICON_PARTS; i++) {
        if (i >= count) {
            lv_obj_add_flag(s_link_icon[i], LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        lv_obj_set_size(s_link_icon[i], parts[i].w, parts[i].h);
        lv_obj_set_pos(s_link_icon[i], x0 + parts[i].x, y0 + parts[i].y);
        lv_obj_set_style_bg_color(s_link_icon[i], ct_color(col), 0);
        lv_obj_remove_flag(s_link_icon[i], LV_OBJ_FLAG_HIDDEN);
    }
}
