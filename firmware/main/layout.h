// สร้างอัตโนมัติจาก tools/layout.toml — ห้ามแก้ไฟล์นี้ด้วยมือ
// แก้ที่ layout.toml แล้วรัน: python3 tools/export_layout.py
#pragma once

#define CT_SCREEN_WIDTH              320
#define CT_SCREEN_HEIGHT             240

#define CT_TOPBAR_HEIGHT             22

#define CT_SLOTS_COUNT               4
#define CT_SLOTS_WIDTH               80
#define CT_SLOTS_TOP                 22
#define CT_SLOTS_HEIGHT              86
#define CT_SLOTS_UNIT_PX             3
#define CT_SLOTS_BASELINE_PAD        19

#define CT_CARD_TOP                  112
#define CT_CARD_HEIGHT               128
#define CT_CARD_PAD                  6

#define CT_USAGE_ROW_H               56
#define CT_USAGE_GAP                 4
#define CT_USAGE_BAR_H               7
#define CT_USAGE_SESSION_WINDOW      18000
#define CT_USAGE_WEEKLY_WINDOW       604800
#define CT_USAGE_WARN_PCT            60
#define CT_USAGE_CRIT_PCT            85

#define CT_STROLL_SPEED_PX_S         34
#define CT_STROLL_PAUSE_S            2.5f
#define CT_STROLL_PAD_PX             76

#define CT_MASCOT_GRID_W             16
#define CT_MASCOT_GRID_H             11.2f
#define CT_MASCOT_OUTLINE            0.34f

// กรอบวาดมาสคอตรวม prop (หน่วย unit) — มาจาก tools/gen/props.py
#define CT_BOX_X0                    -0.5f
#define CT_BOX_X1                    22.0f
#define CT_BOX_Y0                    -5.6f
#define CT_BOX_Y1                    11.2f

// จานสีเป็น RGB565 ตามที่แผงจอกินจริง
#define CT_COL_BG                    0x1081
#define CT_COL_BG_SLOT               0x18A2
#define CT_COL_CLAY                  0xDBAA
#define CT_COL_CLAY_DARK             0xAAA7
#define CT_COL_CLAY_SLEEP            0x7A26
#define CT_COL_GRAY                  0x5AEB
#define CT_COL_GRAY_DARK             0x39E7
#define CT_COL_INK                   0x10A1
#define CT_COL_OUTLINE               0xFFFF
#define CT_COL_TEXT                  0xEF1B
#define CT_COL_TEXT_DIM              0x8C0F
#define CT_COL_ACCENT                0xEDC9
#define CT_COL_ALERT                 0xDAA9
#define CT_COL_GOOD                  0x5D4B

// visual state — daemon ส่งค่าพวกนี้มาบน BLE ห้ามเรียงใหม่
typedef enum {
    CT_STATE_IDLE         = 0,
    CT_STATE_READING      = 1,
    CT_STATE_WRITING      = 2,
    CT_STATE_BUILDING     = 3,
    CT_STATE_SEARCHING    = 4,
    CT_STATE_THINKING     = 5,
    CT_STATE_WAITING      = 6,
    CT_STATE_SLEEPING     = 7,
    CT_STATE_ALERT        = 8,
    CT_STATE_CELEBRATE    = 9,
    CT_STATE_ERROR        = 10,
    CT_STATE_ENTERING     = 11,
    CT_STATE_LEAVING      = 12,
    CT_STATE_CONDUCTING   = 13,
    CT_STATE_BEACON       = 14,
    CT_STATE_COUNT             = 15,
} ct_state_t;

static const char *const ct_state_names[CT_STATE_COUNT] = {
    "idle",
    "reading",
    "writing",
    "building",
    "searching",
    "thinking",
    "waiting",
    "sleeping",
    "alert",
    "celebrate",
    "error",
    "entering",
    "leaving",
    "conducting",
    "beacon",
};
