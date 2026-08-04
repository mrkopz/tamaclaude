#include "ct_calendar_ui.h"

#include "ct_age.h"
#include "ct_color.h"
#include "ct_fonts.h"
#include "ct_mini.h"
#include "layout.h"

static const ct_calendar_t *s_frame;
static const bool *s_has_frame;
static bool s_connected;

typedef struct {
    lv_obj_t *time;
    lv_obj_t *day;
    lv_obj_t *title;
} ct_calendar_row_ui_t;

static ct_calendar_row_ui_t s_rows[CT_CALENDAR_ROWS];
static lv_obj_t *s_age;
static lv_obj_t *s_empty;
static lv_obj_t *s_empty_sub;

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

static lv_obj_t *label(lv_obj_t *parent, const lv_font_t *font, uint16_t color, int x, int y)
{
    lv_obj_t *l = lv_label_create(parent);
    lv_obj_set_style_text_font(l, font, 0);
    lv_obj_set_style_text_color(l, ct_color(color), 0);
    lv_label_set_text(l, "");
    lv_obj_set_pos(l, x, y);
    return l;
}

void ct_calendar_ui_init(lv_obj_t *parent, const ct_calendar_t *frame, const bool *has_frame)
{
    s_frame = frame;
    s_has_frame = has_frame;

    _Static_assert(CT_CALENDAR_TIME_FONT == 24, "layout.toml and the font here must agree");

    for (int i = 0; i < CT_CALENDAR_ROWS; i++) {
        int top = CT_CALENDAR_ROW_Y + i * CT_CALENDAR_ROW_H;
        ct_calendar_row_ui_t *row = &s_rows[i];
        // เวลาชิดซ้ายไม่ใช่ชิดขวา: "all day" ที่ยาวกว่า HH:MM ต้องเริ่มที่เดิม
        row->time = label(parent, &lv_font_montserrat_24, CT_COL_TEXT, CT_CALENDAR_TIME_X,
                          top + CT_CALENDAR_TIME_DY);
        row->day = label(parent, ct_font_text_12(), CT_COL_TEXT_DIM, CT_CALENDAR_DAY_X,
                         top + CT_CALENDAR_DAY_DY);
        lv_obj_set_width(row->day, CT_CALENDAR_DAY_W);

        row->title = label(parent, ct_font_text_14(), CT_COL_TEXT, CT_CALENDAR_TITLE_X,
                           top + CT_CALENDAR_TITLE_DY);
        lv_obj_set_width(row->title, CT_CALENDAR_TITLE_W);
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

    ct_calendar_ui_redraw();
}

void ct_calendar_ui_redraw(void)
{
    bool have = *s_has_frame;
    // นัดจะขึ้นจอได้ก็ต่อเมื่อหน้านี้บอกว่ามันมีนัดจริง — สภาพอื่นทั้งหมดเป็นข้อความ
    int count = (have && s_frame->state == CT_CAL_OK) ? s_frame->count : 0;

    for (int i = 0; i < CT_CALENDAR_ROWS; i++) {
        ct_calendar_row_ui_t *row = &s_rows[i];
        // แถวที่ไม่มีนัดคือแถวที่ไม่มีอยู่ ไม่ใช่แถวที่มีขีดคั่น — นัดเดียวต้องดูเหมือน
        // นัดเดียว ไม่ใช่สี่นัดที่หายไปสาม (กติกาเดียวกับหน้าคริปโต)
        if (i >= count) {
            lv_obj_add_flag(row->time, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(row->day, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(row->title, LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        lv_obj_remove_flag(row->time, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(row->day, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(row->title, LV_OBJ_FLAG_HIDDEN);

        const ct_calendar_row_t *data = &s_frame->rows[i];
        lv_label_set_text(row->time, data->time);
        lv_label_set_text(row->day, data->day);
        lv_label_set_text(row->title, data->title);

        // นัดที่ไม่มีใครรับรองแล้วเป็นเทา เหมือนราคาบนหน้าคริปโต — ยังอ่านได้ แต่ต้อง
        // ไม่อ่านว่าเป็นของตอนนี้
        uint16_t tone = s_connected ? CT_COL_TEXT : CT_COL_GRAY;
        lv_obj_set_style_text_color(row->time, ct_color(tone), 0);
        lv_obj_set_style_text_color(row->title, ct_color(tone), 0);
        lv_obj_set_style_text_color(
            row->day, ct_color(s_connected ? CT_COL_TEXT_DIM : CT_COL_GRAY), 0);
    }

    if (count > 0) {
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
    ct_calendar_ui_redraw_age();
}

void ct_calendar_ui_redraw_age(void)
{
    if (!*s_has_frame) {
        lv_obj_add_flag(s_age, LV_OBJ_FLAG_HIDDEN);
        return;
    }
    lv_obj_remove_flag(s_age, LV_OBJ_FLAG_HIDDEN);
    ct_age_show(s_age, s_frame->age, CT_CALENDAR_REFRESH_S);
}

void ct_calendar_ui_set_connected(bool connected)
{
    if (connected == s_connected) return;
    s_connected = connected;
    // สีถูก *ผลัก* ลงป้าย ไม่ได้ถูกอ่านตอนวาด — วาดใหม่ทั้งใบคือทางเดียวที่ทำให้
    // ทุกแถวเปลี่ยนพร้อมกัน (กติกาเดียวกับหน้าคริปโต)
    ct_calendar_ui_redraw();
}
