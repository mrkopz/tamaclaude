#include "ct_calendar_ui.h"

#include <math.h>
#include <stdio.h>

#include "ct_age.h"
#include "ct_color.h"
#include "ct_fonts.h"
#include "ct_mini.h"
#include "ct_sky.h"
#include "layout.h"

static const ct_calendar_t *s_frame;
static const bool *s_has_frame;
static const ct_snapshot_t *s_mascot;
static bool s_connected;

typedef struct {
    lv_obj_t *time;
    lv_obj_t *day;
    lv_obj_t *title;
} ct_calendar_row_ui_t;

static ct_calendar_row_ui_t s_rows[CT_CALENDAR_LIST_ROWS];
// นัดถัดไป — การ์ดใบเดียวของหน้า ภาษาเดียวกับการ์ด session หน้ามาสคอต
static lv_obj_t *s_hero_box;
static lv_obj_t *s_hero_time;
static lv_obj_t *s_hero_day;
static lv_obj_t *s_hero_sub;
static lv_obj_t *s_hero_title;
// ช่วงเวลาที่พื้นการ์ดใบนี้ใช้อยู่ — เก็บไว้เพราะตัวนับถอยหลังวาดใหม่ทุกวินาทีคนละทาง
// กับตัวการ์ด และมันต้องใช้สีเน้นของช่วงเดียวกัน ไม่ใช่สีดินตายตัว
static ct_sky_phase_t s_card_phase = CT_SKY_NONE;
// องค์ประกอบของฟ้าในการ์ด — เป็น *ลูก* ของกล่องการ์ด ไม่ใช่พี่น้องของมัน จึงถูกตัดที่ขอบ
// การ์ดให้เอง (ดวงจมขอบบน) และอยู่ใต้ตัวหนังสือเสมอ เพราะ LVGL วาดลูกก่อนพี่น้องที่สร้างทีหลัง
static lv_obj_t *s_card_disc;
static lv_obj_t *s_card_stars[CT_CALENDAR_CARD_STARS_COUNT];
// ก้อนละสองชิ้น: แท่งมนกับก้อนบนเยื้องซ้าย — รูปเดียวกับเมฆหน้ามาสคอต
static lv_obj_t *s_card_clouds[CT_CALENDAR_CARD_CLOUDS_COUNT][2];
// เส้นตั้งที่กั้นคอลัมน์เวลากับคอลัมน์ชื่อของแถวใต้การ์ด
static lv_obj_t *s_spine;
static lv_obj_t *s_age;
static lv_obj_t *s_empty;
static lv_obj_t *s_empty_sub;
static lv_obj_t *s_date;
static lv_obj_t *s_date_sub;

// สองบรรทัดของทุกสภาพที่ไม่มีนัดให้แสดง — บรรทัดบนบอกว่าเกิดอะไร บรรทัดล่างบอกว่า
// ต้องทำอะไรต่อ หน้าที่บอกแต่ปัญหาโดยไม่บอกทางออกอ่านเหมือนอุปกรณ์พัง
// ต้องตรงกับ MESSAGES ใน tools/gen/calendar.py
static void empty_lines(ct_calendar_state_t state, const char **head, const char **sub)
{
    switch (state) {
        case CT_CAL_EMPTY:
            *head = "No events";
            *sub = "nothing in the next 7 days";
            return;
        case CT_CAL_NEEDS_ACCESS:
            *head = "Calendar not allowed";
            *sub = "allow it in System Settings > Privacy";
            return;
        case CT_CAL_NOT_ASKED:
            // ยังไม่เคยถูกถาม — System Settings ยังไม่มีแถวของ TamaClaude ให้กดด้วยซ้ำ
            // ก้าวถัดไปคือปุ่มในแอป ไม่ใช่ที่นั่น
            *head = "Calendar not set up";
            *sub = "allow it from the mac app";
            return;
        default:
            // รวมทั้งหน้าที่ยังไม่เคยได้เฟรมเลย — ผู้ใช้ที่เพิ่งเปิดหน้านี้ยังไม่ได้ติ๊ก
            // ปฏิทินสักใบอยู่แล้ว ประโยคนี้จึงเป็นก้าวถัดไปที่ถูกต้องเสมอ
            *head = "No calendars picked";
            *sub = "pick calendars in the mac app";
            return;
    }
}

// หน้านี้กำลังเป็นปฏิทินตั้งโต๊ะอยู่ไหม — ต้องตรงกับ `shows_big_date` ใน tools/gen/calendar.py
//
// เฉพาะสัปดาห์ที่ว่างจริงเท่านั้น สภาพที่ผิด (ไม่ได้สิทธิ์ · ยังไม่เลือกปฏิทิน) ต้องอ่านเป็น
// คำสั่งให้ไปทำอะไรต่อ วันที่ตัวใหญ่บนหน้าแบบนั้นจะกลายเป็นเครื่องประดับที่กลบคำสั่ง
// วันที่ว่างเปล่า = ยังไม่เคยได้ snapshot เลย ซึ่งต้องถอยกลับไปสองบรรทัดเดิม ไม่ใช่โชว์
// ช่องว่างตัวใหญ่กลางจอ
static bool shows_big_date(void)
{
    return *s_has_frame && s_frame->state == CT_CAL_EMPTY && s_mascot->date[0] != '\0';
}

// ขอบบนของบล็อกชื่อนัดบนการ์ด เมื่อชื่อกิน `lines` บรรทัด
// ต้องตรงกับ hero_title_top() ใน tools/gen/calendar.py
//
// ชื่อบรรทัดเดียวถูกดันลงมากึ่งกลางที่ว่างที่เหลือ ไม่ใช่ชิดบน — ครึ่งล่างของการ์ดที่ว่าง
// เปล่าอ่านเป็นการ์ดที่โหลดไม่ครบ ส่วนการ์ดที่สูงไม่เท่ากันตามความยาวชื่อจะดันแถวล่าง
// ขึ้นลงทุกครั้งที่เฟรมใหม่มา
static int hero_title_top(int lines)
{
    return CT_CALENDAR_HERO_TITLE_DY
           + (CT_CALENDAR_HERO_TITLE_LINES - lines) * CT_CALENDAR_HERO_TITLE_LINE_H / 2;
}

// พื้นการ์ดตามช่วงเวลาของนัด — ต้องตรงกับ CARD ใน tools/gen/calendar.py
// ครบชุดต่อหนึ่งช่วง ไม่ใช่พื้นอย่างเดียว: ใบกลางวันพื้นสว่าง ตัวหนังสือทั้งใบต้องกลับขั้ว
static const uint16_t CARD_FILL[CT_SKY_PHASE_COUNT] = {
    CT_COL_CAL_SKY_NIGHT, CT_COL_CAL_SKY_DAWN, CT_COL_CAL_SKY_DAY, CT_COL_CAL_SKY_DUSK};
static const uint16_t CARD_EDGE[CT_SKY_PHASE_COUNT] = {
    CT_COL_CAL_EDGE_NIGHT, CT_COL_CAL_EDGE_DAWN, CT_COL_CAL_EDGE_DAY, CT_COL_CAL_EDGE_DUSK};
static const uint16_t CARD_TEXT[CT_SKY_PHASE_COUNT] = {CT_COL_TEXT, CT_COL_TEXT, CT_COL_INK,
                                                       CT_COL_TEXT};
static const uint16_t CARD_DIM[CT_SKY_PHASE_COUNT] = {CT_COL_CAL_DIM, CT_COL_CAL_DIM,
                                                      CT_COL_INK_DIM, CT_COL_CAL_DIM};
static const uint16_t CARD_ACCENT[CT_SKY_PHASE_COUNT] = {
    CT_COL_CAL_ACCENT, CT_COL_CAL_ACCENT, CT_COL_CAL_INK_ACCENT, CT_COL_CAL_ACCENT};
// ก้นการ์ด (ฟ้าจางลงเข้าหาขอบฟ้า) · ดาวกับเมฆ · ดวง
static const uint16_t CARD_LO[CT_SKY_PHASE_COUNT] = {CT_COL_CAL_LO_NIGHT, CT_COL_CAL_LO_DAWN,
                                                     CT_COL_CAL_LO_DAY, CT_COL_CAL_LO_DUSK};
static const uint16_t CARD_GLOW[CT_SKY_PHASE_COUNT] = {
    CT_COL_CAL_GLOW_NIGHT, CT_COL_CAL_GLOW_DAWN, CT_COL_CAL_GLOW_DAY, CT_COL_CAL_GLOW_DUSK};
static const uint16_t CARD_DISC[CT_SKY_PHASE_COUNT] = {
    CT_COL_CAL_DISC_NIGHT, CT_COL_CAL_DISC_DAWN, CT_COL_CAL_DISC_DAY, CT_COL_CAL_DISC_DUSK};

// ช่วงเวลาที่พื้นการ์ดต้องใช้ — CT_SKY_NONE = ไม่มีฉาก ใช้พื้นการ์ดกลางเดิม
// ต้องตรงกับ card_phase() ใน tools/gen/calendar.py
//
// เวลาของ *นัด* ก่อน ไม่ใช่เวลาตอนนี้ — การ์ดคือช่องหน้าต่างที่มองไปยังชั่วโมงที่นัดจะเกิด
// นัดทั้งวันไม่มีชั่วโมงให้ดู ("all day" อ่านเป็นเวลาไม่ได้) จึงตกไปใช้นาฬิกาบนแถบบน
// ส่วนหลุดลิงก์แล้วไม่มีฉากเลย กติกาเดียวกับฟ้าหน้ามาสคอต
static ct_sky_phase_t card_phase(const ct_calendar_row_t *first)
{
    if (!s_connected) return CT_SKY_NONE;
    float h = ct_clock_hours(first->time);
    if (h < 0.0f) h = ct_clock_hours(s_mascot->clock);
    return h < 0.0f ? CT_SKY_NONE : ct_sky_phase_at(h);
}

// ก้นสันเวลาของ `rows` แถว — ต้องตรงกับ spine_bottom() ใน tools/gen/calendar.py
static int spine_bottom(int rows)
{
    return CT_CALENDAR_ROW_Y + rows * CT_CALENDAR_ROW_H - CT_CALENDAR_SPINE_PAD;
}

// นาทีที่เหลือ -> บรรทัดขวาของการ์ด · คืน false เมื่อไม่มีอะไรให้นับ (นัดทั้งวัน)
// ต้องตรงกับ countdown_text() ใน tools/gen/calendar.py
//
// "09:30" ต้องเอาไปลบกับนาฬิกาในหัวก่อนถึงจะรู้ว่าต้องลุกตอนไหน ส่วน "in 42 min" ไม่ต้อง
static bool countdown_text(const ct_calendar_t *c, char *buf, size_t cap)
{
    if (!c->has_mins) return false;
    // เฟรมมาทุก 5 นาที ตัวเลขในเฟรมจึงเก่าเท่าอายุของมัน — หักออกก่อนเสมอ
    int mins = c->mins - c->age / 60;
    // ไกลเกินครึ่งวันแล้วเลิกนับ บอกชื่อวันแทน — ไม่มีใครวางแผนด้วยหน่วย "in 24h 50m"
    if (mins > CT_CALENDAR_COUNTDOWN_MAX_MIN) return false;
    if (mins <= 0) {
        snprintf(buf, cap, "now");
    } else if (mins < 60) {
        snprintf(buf, cap, "in %d min", mins);
    } else {
        snprintf(buf, cap, "in %dh %02dm", mins / 60, mins % 60);
    }
    return true;
}

// ช่องขวาของการ์ด — ตัวนับถอยหลัง หรือ false เมื่อไม่มีอะไรจะนับ
// ต้องตรงกับ hero_sub() ใน tools/gen/calendar.py
//
// ตัวนับถอยหลังเป็นคำกล่าวเกี่ยวกับ *ตอนนี้* ท่อที่หยุดเดินพูดแบบนั้นไม่ได้: เฟรมที่ค้าง
// มาห้าสิบนาทีจะนับจนถึง "now" เองแล้วค้างอยู่ตรงนั้น ซึ่งอ่านว่านัดกำลังเริ่มทั้งที่ไม่มี
// ใครรู้ · ช่องนี้จึงว่างได้ ต่างจากชื่อวันซึ่งจริงเสมอและอยู่ติดเวลาตลอด (ADR-0002)
static bool hero_sub(const ct_calendar_t *c, char *buf, size_t cap)
{
    if (!s_connected || ct_age_is_stale(c->age, CT_CALENDAR_REFRESH_S)) return false;
    return countdown_text(c, buf, cap);
}

static lv_obj_t *box(lv_obj_t *parent, uint16_t color, int x, int y, int w, int h)
{
    lv_obj_t *o = lv_obj_create(parent);
    lv_obj_remove_style_all(o);
    lv_obj_set_pos(o, x, y);
    lv_obj_set_size(o, w, h);
    lv_obj_set_style_bg_color(o, ct_color(color), 0);
    lv_obj_set_style_bg_opa(o, LV_OPA_COVER, 0);
    return o;
}

static lv_obj_t *label(lv_obj_t *parent, const lv_font_t *font, uint16_t color, int x, int y)
{
    lv_obj_t *l = lv_label_create(parent);
    lv_obj_set_style_text_font(l, font, 0);
    lv_obj_set_style_text_color(l, ct_color(color), 0);
    lv_label_set_text(l, "");
    ct_label_set_pos(l, x, y);
    return l;
}

void ct_calendar_ui_init(lv_obj_t *parent, const ct_calendar_t *frame, const bool *has_frame,
                         const ct_snapshot_t *mascot)
{
    s_frame = frame;
    s_has_frame = has_frame;
    s_mascot = mascot;

    _Static_assert(CT_CALENDAR_HERO_TIME_FONT == 24,
                   "layout.toml and the font here must agree");
    _Static_assert(CT_CALENDAR_DATE_FONT == 48, "layout.toml and the font here must agree");
    // แถวล่างใช้ฟอนต์ไทยล้วน ไม่ใช่ montserrat — ค่าที่ layout.toml ตั้งไว้ต้องเป็น
    // ขนาดที่ ct_font_text_* มีจริง ไม่งั้นภาพบน preview จะเป็นคนละขนาดกับบนบอร์ด
    _Static_assert(CT_CALENDAR_TIME_FONT == 14, "layout.toml and the font here must agree");
    _Static_assert(CT_CALENDAR_DAY_FONT == 12, "layout.toml and the font here must agree");
    _Static_assert(CT_CALENDAR_TITLE_FONT == 12, "layout.toml and the font here must agree");

    // การ์ดก่อนแถว แล้วค่อยข้อความ — LVGL วางทับตามลำดับที่สร้าง พื้นที่สร้างทีหลัง
    // จะกลบตัวอักษรที่สร้างก่อน
    s_hero_box = box(parent, CT_COL_BG_SLOT, CT_CALENDAR_HERO_PAD, CT_CALENDAR_HERO_Y,
                     CT_SCREEN_WIDTH - CT_CALENDAR_HERO_PAD * 2, CT_CALENDAR_HERO_H);
    s_spine = box(parent, CT_COL_GRAY_DARK, CT_CALENDAR_SPINE_X, CT_CALENDAR_SPINE_TOP,
                  CT_CALENDAR_SPINE_W, spine_bottom(CT_CALENDAR_LIST_ROWS)
                                           - CT_CALENDAR_SPINE_TOP);

    // ฉากในการ์ดสร้างทันทีหลังกล่อง และเป็นลูกของมัน — สีมาทีหลังตอน redraw
    // ตำแหน่งทั้งหมดวัดจากมุมซ้ายบนของการ์ด ซึ่งเป็นระบบพิกัดของลูกอยู่แล้ว
    {
        int r = CT_CALENDAR_CARD_DISC_R;
        s_card_disc = box(s_hero_box, CT_COL_CAL_DISC_DAY, CT_CALENDAR_CARD_DISC_X - r,
                          CT_CALENDAR_CARD_DISC_Y - r, r * 2 + 1, r * 2 + 1);
        lv_obj_set_style_radius(s_card_disc, LV_RADIUS_CIRCLE, 0);
        for (int i = 0; i < CT_CALENDAR_CARD_STARS_COUNT; i++) {
            s_card_stars[i] = box(s_hero_box, CT_COL_CAL_GLOW_NIGHT,
                                  ct_calendar_card_stars[i][0], ct_calendar_card_stars[i][1],
                                  CT_CALENDAR_CARD_STAR_PX, CT_CALENDAR_CARD_STAR_PX);
        }
        for (int i = 0; i < CT_CALENDAR_CARD_CLOUDS_COUNT; i++) {
            int x = ct_calendar_card_clouds[i][0], y = ct_calendar_card_clouds[i][1];
            int w = ct_calendar_card_clouds[i][2];
            s_card_clouds[i][0] = box(s_hero_box, CT_COL_CAL_GLOW_DAY, x, y, w + 1,
                                      CT_CALENDAR_CARD_CLOUD_H);
            int bx = (int)lroundf(x + w * 0.25f), bw = (int)lroundf(w * 0.45f);
            s_card_clouds[i][1] = box(s_hero_box, CT_COL_CAL_GLOW_DAY, bx, y - 4, bw + 1,
                                      CT_CALENDAR_CARD_CLOUD_H);
            for (int j = 0; j < 2; j++) {
                lv_obj_set_style_radius(s_card_clouds[i][j], CT_CALENDAR_CARD_CLOUD_R, 0);
            }
        }
    }

    s_hero_time = label(parent, &lv_font_montserrat_24, CT_COL_TEXT, CT_CALENDAR_HERO_TIME_X,
                        CT_CALENDAR_HERO_Y + CT_CALENDAR_HERO_TIME_DY);
    // ชื่อวันติดเวลาและอยู่ตลอด — เวลาที่ไม่มีวันกำกับอ่านเป็นวันนี้เสมอ
    s_hero_day = label(parent, ct_font_text_14(), CT_COL_TEXT_DIM, CT_CALENDAR_HERO_DAY_X,
                       CT_CALENDAR_HERO_Y + CT_CALENDAR_HERO_SUB_DY);
    lv_obj_set_width(s_hero_day, CT_CALENDAR_HERO_DAY_W);
    // ชิดขวาด้วยกล่องกว้างคงที่ ไม่ใช่ align หลังตั้งข้อความ — ความกว้างของ "in 42 min"
    // กับ "Tomorrow" ไม่เท่ากัน และขอบขวาต้องนิ่งทุกครั้งที่ตัวเลขเดิน
    s_hero_sub = label(parent, ct_font_text_14(), CT_COL_CLAY,
                       CT_SCREEN_WIDTH - CT_CALENDAR_HERO_SUB_RIGHT - CT_CALENDAR_HERO_SUB_W,
                       CT_CALENDAR_HERO_Y + CT_CALENDAR_HERO_SUB_DY);
    lv_obj_set_width(s_hero_sub, CT_CALENDAR_HERO_SUB_W);
    lv_obj_set_style_text_align(s_hero_sub, LV_TEXT_ALIGN_RIGHT, 0);

    // ป้ายเดียวสองบรรทัด ไม่ใช่สองป้าย — LVGL ตัดคำเองด้วยกติกาเดียวกับ screen.wrap()
    // ฝั่ง preview · ความสูงปล่อยให้โตตามเนื้อหา แล้ววัดกลับมาว่ากินกี่บรรทัดเพื่อจัด
    // บล็อกให้อยู่กึ่งกลางการ์ด (ดู hero_title_top)
    s_hero_title = label(parent, ct_font_text_14(), CT_COL_TEXT, CT_CALENDAR_HERO_TITLE_X,
                         CT_CALENDAR_HERO_Y + CT_CALENDAR_HERO_TITLE_DY);
    lv_obj_set_width(s_hero_title, CT_CALENDAR_HERO_TITLE_W);
    lv_obj_set_height(s_hero_title, LV_SIZE_CONTENT);
    lv_label_set_long_mode(s_hero_title, LV_LABEL_LONG_WRAP);

    for (int i = 0; i < CT_CALENDAR_LIST_ROWS; i++) {
        int top = CT_CALENDAR_ROW_Y + i * CT_CALENDAR_ROW_H;
        ct_calendar_row_ui_t *row = &s_rows[i];
        // เวลาชิดซ้ายไม่ใช่ชิดขวา: "all day" ที่ยาวกว่า HH:MM ต้องเริ่มที่เดิม
        row->time = label(parent, ct_font_text_14(), CT_COL_TEXT, CT_CALENDAR_TIME_X,
                          top + CT_CALENDAR_TIME_DY);
        lv_obj_set_width(row->time, CT_CALENDAR_TIME_W);
        // ชื่อวันอยู่ใต้เวลาในคอลัมน์เดียวกัน (ดู layout.toml) — ทั้งคู่เป็นละตินล้วน
        // จึงกองสองชั้นในแถวสูง 37 ได้โดยไม่มีวรรณยุกต์ไทยที่ต้องกันที่ไว้ให้
        row->day = label(parent, ct_font_text_12(), CT_COL_TEXT_DIM, CT_CALENDAR_DAY_X,
                         top + CT_CALENDAR_DAY_DY);
        lv_obj_set_width(row->day, CT_CALENDAR_DAY_W);
        // ป้ายที่มีความกว้างคงที่จะ *ขึ้นบรรทัดใหม่* เองถ้าเนื้อหาล้น ซึ่งกินแถวถัดไป —
        // เคยเกิดจริงกับ "Tomorrow" ที่ช่องกว้าง 52 · ทั้งสองช่องนี้สูงหนึ่งบรรทัดตายตัว
        // ตามเลย์เอาต์ ตัดท้ายทิ้งจึงเป็นทางเดียวที่เหลือ (เหมือนที่ preview ทำ)
        lv_obj_set_height(row->time, lv_font_get_line_height(ct_font_text_14()));
        lv_obj_set_height(row->day, lv_font_get_line_height(ct_font_text_12()));
        lv_label_set_long_mode(row->time, LV_LABEL_LONG_DOT);
        lv_label_set_long_mode(row->day, LV_LABEL_LONG_DOT);

        row->title = label(parent, ct_font_text_12(), CT_COL_TEXT, CT_CALENDAR_TITLE_X,
                           top + CT_CALENDAR_TITLE_DY);
        lv_obj_set_width(row->title, CT_CALENDAR_TITLE_W);
        lv_obj_set_height(row->title, lv_font_get_line_height(ct_font_text_12()));
        // Mac ตัดชื่อมาให้พอดีคอลัมน์แล้ว (`CalendarFrame.titleLimit`) — อันนี้เป็น
        // ตาข่ายรับ ไม่ใช่ตัวตัดหลัก ฟอนต์ที่กว้างกว่าที่วัดไว้ต้องไม่ล้นไปทับแถวอื่น
        lv_label_set_long_mode(row->title, LV_LABEL_LONG_DOT);
    }

    ct_mini_attach(parent);

    s_age = ct_age_label(parent);
    s_empty = label(parent, ct_font_text_14(), CT_COL_TEXT, CT_CALENDAR_TIME_X,
                    CT_CALENDAR_EMPTY_Y);
    s_empty_sub = label(parent, ct_font_text_12(), CT_COL_TEXT_DIM, CT_CALENDAR_TIME_X,
                        CT_CALENDAR_EMPTY_SUB_Y);

    // วันที่ตัวใหญ่กลางจอ — จัดกลางด้วย align ไม่ใช่พิกัดคงที่ เพราะความกว้างของข้อความ
    // เปลี่ยนทุกวัน ("Tue 4 Aug" กับ "Wed 24 Sep" ไม่เท่ากัน)
    // y ที่ตั้งไว้คือ *ขอบบน* ของบรรทัด ส่วนฝั่ง preview วัดจากกึ่งกลาง (ครึ่งหนึ่งของ
    // ฟอนต์ = 24 กับ 6) กติกาเดียวกับนาฬิกาตั้งโต๊ะบนหน้ามาสคอต
    s_date = lv_label_create(parent);
    lv_obj_set_style_text_font(s_date, &lv_font_montserrat_48, 0);
    lv_obj_set_style_text_color(s_date, ct_color(CT_COL_TEXT), 0);
    lv_label_set_text(s_date, "");
    lv_obj_align(s_date, LV_ALIGN_TOP_MID, 0, CT_CALENDAR_DATE_Y);
    s_date_sub = lv_label_create(parent);
    lv_obj_set_style_text_font(s_date_sub, ct_font_text_12(), 0);
    lv_obj_set_style_text_color(s_date_sub, ct_color(CT_COL_TEXT_DIM), 0);
    lv_label_set_text(s_date_sub, "");
    lv_obj_align(s_date_sub, LV_ALIGN_TOP_MID, 0,
                 CT_CALENDAR_DATE_SUB_Y - ct_font_rise(ct_font_text_12()));

    ct_calendar_ui_redraw();
}

// ตั้งชื่อนัดบนการ์ด แล้วจัดบล็อกให้อยู่กึ่งกลางที่ว่างตามจำนวนบรรทัดที่มันกินจริง
//
// จำนวนบรรทัดต้อง *วัด* ไม่ใช่คำนวณ — กติกาการตัดคำเป็นของ LVGL ส่วนฝั่ง preview มี
// พอร์ตของมันอยู่ที่ screen.wrap() การเขียนสูตรที่สามขึ้นมาที่นี่คือความจริงชุดที่สาม
static void set_hero_title(const char *title)
{
    const lv_font_t *font = ct_font_text_14();
    // บรรทัดเกาะกันแน่นกว่ากล่องฟอนต์ — ระยะหัวถึงหัวคือ 25 ส่วนกล่องคือ 28 (ดู layout.toml)
    // ทำด้วยระยะห่างติดลบ ไม่ใช่การบีบกล่อง: กล่องคือสิ่งที่วรรณยุกต์ซ้อนใช้อยู่จริง
    int font_h = lv_font_get_line_height(font);
    int pitch = CT_CALENDAR_HERO_TITLE_LINE_H;
    lv_obj_set_style_text_line_space(s_hero_title, pitch - font_h, 0);
    lv_label_set_long_mode(s_hero_title, LV_LABEL_LONG_WRAP);
    lv_obj_set_height(s_hero_title, LV_SIZE_CONTENT);
    lv_label_set_text(s_hero_title, title);
    lv_obj_update_layout(s_hero_title);

    // ความสูงของ n บรรทัดคือ font_h + (n-1)*pitch — บรรทัดแรกใช้กล่องเต็ม ที่เหลือใช้ระยะหัว
    int lines = (lv_obj_get_height(s_hero_title) - font_h + pitch) / pitch;
    if (lines < 1) lines = 1;
    if (lines > CT_CALENDAR_HERO_TITLE_LINES) {
        // ตาข่ายรับ: Mac ตัดมาให้พอดีสองบรรทัดแล้ว (`CalendarFrame.heroTitleLimit`)
        // ฟอนต์ที่กว้างกว่าที่วัดไว้ต้องไม่ล้นออกนอกการ์ดไปทับแถวล่าง
        lines = CT_CALENDAR_HERO_TITLE_LINES;
        lv_obj_set_height(s_hero_title, font_h + (lines - 1) * pitch);
        lv_label_set_long_mode(s_hero_title, LV_LABEL_LONG_DOT);
    }
    lv_obj_set_y(s_hero_title,
                 CT_CALENDAR_HERO_Y + hero_title_top(lines) - ct_font_rise(font));
}

// ดาว/เมฆ/ดวงของช่วงนี้ — ต้องตรงกับ _card_sky() ใน tools/gen/calendar.py
//
// กลางวันไม่มีดาว กลางคืนไม่มีเมฆ กติกาเดียวกับฉากหน้ามาสคอต · ไม่มีชิ้นไหนขยับ:
// ฉากที่เคลื่อนบนหน้าที่ไม่ได้เปลี่ยนทุกวินาทีอ่านเป็นจอค้างครึ่งหนึ่ง ไม่ใช่ของมีชีวิต
static void card_sky(ct_sky_phase_t phase)
{
    bool scene = phase != CT_SKY_NONE;
    bool stars = scene && phase != CT_SKY_DAY;
    bool clouds = scene && phase != CT_SKY_NIGHT;
    uint16_t glow = scene ? CARD_GLOW[phase] : 0;

    if (scene) lv_obj_set_style_bg_color(s_card_disc, ct_color(CARD_DISC[phase]), 0);
    if (scene) {
        lv_obj_remove_flag(s_card_disc, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(s_card_disc, LV_OBJ_FLAG_HIDDEN);
    }
    for (int i = 0; i < CT_CALENDAR_CARD_STARS_COUNT; i++) {
        if (stars) {
            lv_obj_set_style_bg_color(s_card_stars[i], ct_color(glow), 0);
            lv_obj_remove_flag(s_card_stars[i], LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_add_flag(s_card_stars[i], LV_OBJ_FLAG_HIDDEN);
        }
    }
    for (int i = 0; i < CT_CALENDAR_CARD_CLOUDS_COUNT; i++) {
        for (int j = 0; j < 2; j++) {
            if (clouds) {
                lv_obj_set_style_bg_color(s_card_clouds[i][j], ct_color(glow), 0);
                lv_obj_remove_flag(s_card_clouds[i][j], LV_OBJ_FLAG_HIDDEN);
            } else {
                lv_obj_add_flag(s_card_clouds[i][j], LV_OBJ_FLAG_HIDDEN);
            }
        }
    }
}

void ct_calendar_ui_redraw(void)
{
    bool have = *s_has_frame;
    // นัดจะขึ้นจอได้ก็ต่อเมื่อหน้านี้บอกว่ามันมีนัดจริง — สภาพอื่นทั้งหมดเป็นข้อความ
    int count = (have && s_frame->state == CT_CAL_OK) ? s_frame->count : 0;

    // นัดที่ไม่มีใครรับรองแล้วเป็นเทา เหมือนราคาบนหน้าคริปโต — ยังอ่านได้ แต่ต้อง
    // ไม่อ่านว่าเป็นของตอนนี้
    uint16_t tone = s_connected ? CT_COL_TEXT : CT_COL_GRAY;
    uint16_t dim = s_connected ? CT_COL_TEXT_DIM : CT_COL_GRAY;

    if (count > 0) {
        const ct_calendar_row_t *first = &s_frame->rows[0];
        lv_obj_remove_flag(s_hero_box, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s_hero_time, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s_hero_day, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s_hero_title, LV_OBJ_FLAG_HIDDEN);
        lv_label_set_text(s_hero_time, first->time);
        lv_label_set_text(s_hero_day, first->day);
        set_hero_title(first->title);
        // การ์ดที่มีฉากถือชุดสีของช่วงเวลาตัวเอง ไม่ใช่ชุดของหน้า — พื้นสว่างของใบกลางวัน
        // รับตัวหนังสือสีเดิมไม่ได้เลย (1.1:1)
        s_card_phase = card_phase(first);
        bool scene = s_card_phase != CT_SKY_NONE;
        lv_obj_set_style_bg_color(
            s_hero_box, ct_color(scene ? CARD_FILL[s_card_phase] : CT_COL_BG_SLOT), 0);
        // ฟ้าจางลงเข้าหาก้นการ์ดเสมอ ไม่ว่ากลางวันหรือกลางคืน — ขอบฟ้าคือที่ที่ฟ้าจางที่สุด
        lv_obj_set_style_bg_grad_dir(s_hero_box, scene ? LV_GRAD_DIR_VER : LV_GRAD_DIR_NONE, 0);
        if (scene) {
            lv_obj_set_style_bg_grad_color(s_hero_box, ct_color(CARD_LO[s_card_phase]), 0);
        }
        // ขอบ 1px คือสิ่งที่ทำให้ใบกลางคืนยังอ่านเป็นการ์ด ทั้งที่พื้นมันเข้มพอๆ กับพื้นจอ
        lv_obj_set_style_border_width(s_hero_box, scene ? 1 : 0, 0);
        if (scene) {
            lv_obj_set_style_border_color(s_hero_box, ct_color(CARD_EDGE[s_card_phase]), 0);
            lv_obj_set_style_border_opa(s_hero_box, LV_OPA_COVER, 0);
        }
        card_sky(s_card_phase);
        uint16_t hero_tone = scene ? CARD_TEXT[s_card_phase] : tone;
        uint16_t hero_dim = scene ? CARD_DIM[s_card_phase] : dim;
        lv_obj_set_style_text_color(s_hero_time, ct_color(hero_tone), 0);
        lv_obj_set_style_text_color(s_hero_day, ct_color(hero_dim), 0);
        lv_obj_set_style_text_color(s_hero_title, ct_color(hero_tone), 0);
        ct_calendar_ui_redraw_hero_sub();
    } else {
        lv_obj_add_flag(s_hero_box, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_hero_time, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_hero_day, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_hero_sub, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_hero_title, LV_OBJ_FLAG_HIDDEN);
    }

    // สันเวลาเป็นตัวกั้นคอลัมน์ ไม่ใช่ของประดับ — ไม่มีแถวใต้การ์ดก็ไม่มีอะไรให้กั้น
    // เส้นที่ยังอยู่ตอนมีนัดเดียวอ่านเป็นตารางที่แถวหายไป
    if (count > 1) {
        lv_obj_remove_flag(s_spine, LV_OBJ_FLAG_HIDDEN);
        // ยาวเท่าแถวที่มีอยู่จริง ไม่ใช่เท่าย่านที่กันไว้
        lv_obj_set_height(s_spine, spine_bottom(count - 1) - CT_CALENDAR_SPINE_TOP);
        lv_obj_set_style_bg_color(s_spine, ct_color(s_connected ? CT_COL_GRAY_DARK
                                                                : CT_COL_INK), 0);
    } else {
        lv_obj_add_flag(s_spine, LV_OBJ_FLAG_HIDDEN);
    }

    for (int i = 0; i < CT_CALENDAR_LIST_ROWS; i++) {
        ct_calendar_row_ui_t *row = &s_rows[i];
        // แถวที่ไม่มีนัดคือแถวที่ไม่มีอยู่ ไม่ใช่แถวที่มีขีดคั่น — นัดเดียวต้องดูเหมือน
        // นัดเดียว ไม่ใช่สามนัดที่หายไปสอง (กติกาเดียวกับหน้าคริปโต)
        if (i + 1 >= count) {
            lv_obj_add_flag(row->time, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(row->day, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(row->title, LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        lv_obj_remove_flag(row->time, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(row->day, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(row->title, LV_OBJ_FLAG_HIDDEN);

        // ทุกแถวบอกวันของตัวเอง — **กลับคำ** เคยซ่อนไว้ตอนวันไม่เปลี่ยนเพื่อไม่ให้
        // "Tomorrow" ขึ้นซ้ำ แล้วแถวที่ถูกซ่อนก็อ่านเป็น "ไม่มีวัน" ไม่ใช่ "วันเดียวกับข้างบน"
        // เวลาที่ไม่มีวันกำกับอ่านเป็นวันนี้เสมอ ซึ่งเป็นคำตอบที่ผิดได้ทั้งสัปดาห์
        const ct_calendar_row_t *data = &s_frame->rows[i + 1];
        lv_label_set_text(row->time, data->time);
        lv_label_set_text(row->day, data->day);
        lv_label_set_text(row->title, data->title);

        lv_obj_set_style_text_color(row->time, ct_color(tone), 0);
        lv_obj_set_style_text_color(row->title, ct_color(tone), 0);
        lv_obj_set_style_text_color(row->day, ct_color(dim), 0);
    }

    bool big = count == 0 && shows_big_date();
    if (count > 0 || big) {
        lv_obj_add_flag(s_empty, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_empty_sub, LV_OBJ_FLAG_HIDDEN);
    } else {
        const char *head = NULL;
        const char *sub = NULL;
        empty_lines(have ? s_frame->state : CT_CAL_NO_CALENDARS, &head, &sub);
        lv_label_set_text(s_empty, head);
        lv_label_set_text(s_empty_sub, sub);
        lv_obj_remove_flag(s_empty, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s_empty_sub, LV_OBJ_FLAG_HIDDEN);
    }

    if (big) {
        lv_label_set_text(s_date, s_mascot->date);
        // ตั้งข้อความแล้วต้องจัดกลางใหม่ — ความกว้างเพิ่งเปลี่ยนไปพร้อมกับวันที่
        lv_obj_align(s_date, LV_ALIGN_TOP_MID, 0, CT_CALENDAR_DATE_Y);
        // วันที่ที่ค้างเป็นเทาเหมือนนาฬิกา ไม่ใช่หายไป: มันเกือบถูกเสมอ และวันที่ผิด
        // รู้ทันที ต่างจากเปอร์เซ็นต์โควตาที่แถบบนซ่อนทิ้งตอนหลุดลิงก์
        lv_obj_set_style_text_color(s_date, ct_color(s_connected ? CT_COL_TEXT : CT_COL_GRAY),
                                    0);
        // บรรทัดล่างเป็นประโยคเดียวกับที่สภาพนี้เคยใช้ ไม่ใช่ข้อความใบใหม่ — เปลี่ยนคำ
        // ที่เดียวใน empty_lines() แล้วทั้งสองรูปแบบเปลี่ยนตาม
        const char *head = NULL;
        const char *sub = NULL;
        empty_lines(CT_CAL_EMPTY, &head, &sub);
        lv_label_set_text(s_date_sub, sub);
        lv_obj_align(s_date_sub, LV_ALIGN_TOP_MID, 0,
                 CT_CALENDAR_DATE_SUB_Y - ct_font_rise(ct_font_text_12()));
        lv_obj_remove_flag(s_date, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s_date_sub, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(s_date, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_date_sub, LV_OBJ_FLAG_HIDDEN);
    }
    ct_calendar_ui_redraw_age();
}

void ct_calendar_ui_redraw_hero_sub(void)
{
    if (!*s_has_frame || s_frame->state != CT_CAL_OK || s_frame->count == 0) return;
    char buf[24];
    if (!hero_sub(s_frame, buf, sizeof(buf))) {
        lv_obj_add_flag(s_hero_sub, LV_OBJ_FLAG_HIDDEN);
        return;
    }
    lv_label_set_text(s_hero_sub, buf);
    lv_obj_set_style_text_color(
        s_hero_sub,
        ct_color(s_card_phase == CT_SKY_NONE ? CT_COL_CLAY : CARD_ACCENT[s_card_phase]), 0);
    lv_obj_remove_flag(s_hero_sub, LV_OBJ_FLAG_HIDDEN);
}

void ct_calendar_ui_redraw_age(void)
{
    if (!*s_has_frame) {
        lv_obj_add_flag(s_age, LV_OBJ_FLAG_HIDDEN);
        return;
    }
    lv_obj_remove_flag(s_age, LV_OBJ_FLAG_HIDDEN);
    ct_age_show(s_age, s_frame->age, CT_CALENDAR_REFRESH_S);
    // ตัวนับถอยหลังเดินด้วยอายุข้อมูลตัวเดียวกัน — อัปเดตพร้อมกันเสมอ ไม่งั้นบรรทัดหนึ่ง
    // จะบอกว่า "updated 4m ago" ขณะที่อีกบรรทัดยังค้างที่ "in 42 min" ของสี่นาทีก่อน
    ct_calendar_ui_redraw_hero_sub();
}

void ct_calendar_ui_set_connected(bool connected)
{
    if (connected == s_connected) return;
    s_connected = connected;
    // สีถูก *ผลัก* ลงป้าย ไม่ได้ถูกอ่านตอนวาด — วาดใหม่ทั้งใบคือทางเดียวที่ทำให้
    // ทุกแถวเปลี่ยนพร้อมกัน (กติกาเดียวกับหน้าคริปโต)
    ct_calendar_ui_redraw();
}
