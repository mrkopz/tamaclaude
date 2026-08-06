#include "ct_weather_ui.h"

#include <math.h>
#include <stdint.h>

#include "ct_age.h"
#include "ct_footer.h"
#include "ct_color.h"
#include "ct_fonts.h"
#include "ct_mini.h"
#include "ct_paint.h"
#include "ct_rects.h"
#include "ct_sky.h"
#include "layout.h"

// หนึ่งลูปอนิเมชันยาวเท่าไร (ms) — ค่าเดียวกับ LOOP_MS ใน ct_ui.c
#define LOOP_MS 1000

static const ct_weather_t *s_frame;
static const bool *s_has_frame;
static const ct_snapshot_t *s_mascot;
static bool s_connected;

// จังหวะของฉาก — เรือนของหน้านี้เอง ไม่ใช่ของ ct_ui.c: สองหน้านี้ไม่เคยอยู่บนจอพร้อมกัน
// และเรือนที่เดินต่อขณะหน้านี้ถูกปัดออกไปก็ไม่มีใครเห็น · หยุดแล้วเดินต่อจากที่ค้างไว้
// คือสิ่งที่ถูก ไม่ใช่กระโดดไปตามเวลาที่หายไป — ไม่มีใครจำได้ว่าเมฆอยู่ตรงไหนเมื่อ 20
// วินาทีก่อน แต่ทุกคนเห็นถ้ามันกระตุกตอนหน้าเพิ่งขึ้น
static float s_phase = 0.0f;
static int s_cycle = 0;
static int s_cloud_shift = -1;  // เมฆเลื่อนไปกี่พิกเซลแล้ว ใช้ตัดสินว่าต้องวาดใหม่ไหม
static bool s_bolt_on;          // สายฟ้าติดอยู่ตอนที่วาดครั้งล่าสุดไหม (เหตุผลเดียวกัน)

static lv_obj_t *s_scene;      // ผืนฉาก: ฟ้า + สภาพอากาศ + พื้นดิน อยู่ล่างสุดของหน้า
static lv_obj_t *s_place;
static lv_obj_t *s_temp;
static lv_obj_t *s_hilo;
static lv_obj_t *s_age;
static lv_obj_t *s_empty;      // บรรทัดของสภาพ "ยังไม่เคยได้ข้อมูล"
static lv_obj_t *s_empty_sub;
static lv_obj_t *s_icon;   // ผืนวาดสัญลักษณ์อากาศ
static lv_obj_t *s_fc_hour[CT_WEATHER_FC_COLS];
static lv_obj_t *s_fc_temp[CT_WEATHER_FC_COLS];
static lv_obj_t *s_fc_icon[CT_WEATHER_FC_COLS];

static void paint_ink(void);

// --- สัญลักษณ์อากาศ ------------------------------------------------------------
// กลุ่มสภาพอากาศ (`ct_wx_kind_t` / `ct_sky_bucket`) อยู่ที่ ct_sky.h ตั้งแต่หน้ามาสคอต
// เอาไปใช้ด้วย (ADR-0012) — ที่นี่เหลือแต่การแปลงกลุ่มเป็นรูปและเป็นฉาก

// ชั่วโมงนี้ดวงบนฟ้าเป็นดวงจันทร์ไหม — ขอบเดียวกับที่ sky_disc() ใน ct_ui.c ใช้
// ไอคอนที่มีดวงอาทิตย์อยู่ข้างฟ้ากลางคืนที่เต็มไปด้วยดาวคืออุปกรณ์ที่ขัดแย้งกับตัวเอง
// ไม่รู้เวลา (h < 0) = กลางวัน — ดวงอาทิตย์เป็นรูปที่อ่านออกโดยไม่ต้องมีบริบท
// ต้องตรงกับ is_night() ใน tools/gen/weather.py
static bool is_night(float h)
{
    return h >= 0.0f && !(h >= CT_SKY_DAWN_HOUR && h < CT_SKY_NIGHT_HOUR);
}

// ก้อนเมฆ — สามชิ้นซ้อนกันในตาราง 10x10 unit ใช้ร่วมกันสี่กลุ่ม
static void add_cloud(ct_rects_t *out, uint16_t color)
{
    ct_rects_add_round(out, 1.0f, 3.6f, 8.0f, 2.8f, color, 1.4f);
    ct_rects_add_round(out, 2.4f, 2.0f, 3.4f, 3.0f, color, 1.5f);
    ct_rects_add_round(out, 5.0f, 2.6f, 3.0f, 2.6f, color, 1.3f);
}

// สัญลักษณ์หนึ่งชุดในตาราง 10x10 unit — พิกัด unit เหมือน asset อื่นทั้งโปรเจกต์
// ต้องตรงกับ icon() ใน tools/gen/weather.py
static void build_icon(ct_rects_t *out, int code, bool connected, bool night)
{
    ct_rects_reset(out);
    // หลุดลิงก์แล้วสัญลักษณ์เป็นเทา เหมือนมาสคอตที่หลุด — ตัวเลขที่ค้างอยู่ยังอ่านได้
    // แต่ต้องไม่อ่านว่าเป็นตอนนี้
    uint16_t cloud = connected ? CT_COL_CLOUD_DAY : CT_COL_GRAY;
    uint16_t sun = connected ? (night ? CT_COL_MOON : CT_COL_SUN) : CT_COL_GRAY;
    uint16_t wet = connected ? CT_COL_STEEL : CT_COL_GRAY_DARK;
    uint16_t bolt = connected ? CT_COL_ACCENT : CT_COL_GRAY_DARK;
    uint16_t flake = connected ? CT_COL_TEXT : CT_COL_GRAY_DARK;

    switch (ct_sky_bucket(code)) {
        case CT_WX_CLEAR:
            if (night) {
                // ดวงจันทร์ + ดาวสามดวง — ดวงกลมเปล่าๆ ที่ 20px (คอลัมน์พยากรณ์)
                // อ่านเป็นจุดหัวข้อ ไม่ใช่ดวงจันทร์ · ดาวทำหน้าที่เดียวกับรังสีของดวงอาทิตย์
                // คือเปลี่ยนวงกลมให้เป็นเวลาของวัน · ไม่ใช้วิธีแหว่งเสี้ยว เพราะการแหว่ง
                // ต้องวาดทับด้วยสีพื้นหลัง ซึ่งไอคอนนี้ไม่รู้ (มันอยู่บนฟ้าสี่ช่วงและบนพื้นดิน
                // อีกสี่สีในแถบพยากรณ์)
                ct_rects_add_round(out, 2.2f, 2.8f, 5.0f, 5.0f, sun, 2.5f);
                ct_rects_add_round(out, 8.0f, 1.0f, 1.4f, 1.4f, flake, 0.2f);
                ct_rects_add(out, 6.8f, 4.6f, 1.0f, 1.0f, flake);
                ct_rects_add_round(out, 8.4f, 7.0f, 1.2f, 1.2f, flake, 0.2f);
                break;
            }
            // ดวงกลมกับรังสีสี่ทิศ — ไม่ใช่แปดทิศ เพราะที่ 50px รังสีทแยงกลืนกับดวง
            ct_rects_add_round(out, 2.5f, 2.5f, 5.0f, 5.0f, sun, 2.5f);
            ct_rects_add(out, 4.6f, 0.2f, 0.8f, 1.6f, sun);
            ct_rects_add(out, 4.6f, 8.2f, 0.8f, 1.6f, sun);
            ct_rects_add(out, 0.2f, 4.6f, 1.6f, 0.8f, sun);
            ct_rects_add(out, 8.2f, 4.6f, 1.6f, 0.8f, sun);
            break;
        case CT_WX_CLOUD:
            // เมฆบังดวงบางส่วน — เมฆล้วนแยกไม่ออกจากหมอกที่ระยะโต๊ะ
            ct_rects_add_round(out, 5.6f, 0.2f, 3.6f, 3.6f, sun, 1.8f);
            add_cloud(out, cloud);
            break;
        case CT_WX_FOG:
            // สามขีดนอน ไม่มีเมฆ — หมอกคือสิ่งที่ *ไม่* มีรูปร่าง
            for (int i = 0; i < 3; i++) {
                ct_rects_add_round(out, 1.0f + (i % 2) * 0.8f, 2.6f + i * 2.2f, 7.4f, 1.0f,
                                   cloud, 0.5f);
            }
            break;
        case CT_WX_RAIN:
            add_cloud(out, cloud);
            for (int i = 0; i < 3; i++) {
                ct_rects_add_round(out, 2.2f + i * 2.4f, 7.0f, 0.9f, 2.4f, wet, 0.45f);
            }
            break;
        case CT_WX_SNOW:
            add_cloud(out, cloud);
            for (int i = 0; i < 3; i++) {
                ct_rects_add_round(out, 2.2f + i * 2.4f, 7.4f, 1.4f, 1.4f, flake, 0.7f);
            }
            break;
        case CT_WX_STORM:
            add_cloud(out, cloud);
            // สายฟ้าเป็นสองชิ้นเยื้องกัน — ชิ้นเดียวอ่านเป็นเสาไฟ
            ct_rects_add(out, 4.6f, 6.8f, 1.6f, 1.8f, bolt);
            ct_rects_add(out, 3.8f, 8.0f, 1.6f, 1.8f, bolt);
            break;
    }
}

// --- ฉาก: ฟ้าของชั่วโมงนี้ + สภาพอากาศที่กำลังเกิดบนมัน -------------------------
// ต้องตรงกับ _scene() ใน tools/gen/weather.py
//
// ทุกชิ้นวาดก่อนตัวหนังสือและทับกันได้ ไม่มีการกันพื้นที่ไว้ให้ — สิ่งที่ทำให้มันไม่กวนคือ
// ค่าความต่าง (แนวเมฆ ~1.8:1 กับฟ้า · ตัวหนังสือ 7:1 ขึ้นไป) หลักเดียวกับการ์ดปฏิทิน
//
// ฉากขยับด้วยจังหวะและความเร็วชุดเดียวกับฟ้าหน้ามาสคอต (`[sky]` ทั้งชุด) — เคยนิ่งโดย
// ตั้งใจ ด้วยเหตุผลว่าหน้านี้อยู่บนจอรอบละ 20 วินาทีและมีตัวเลขให้อ่านอยู่แล้ว **กลับคำนั้น
// เพราะสองหน้านี้อยู่ในรอบปัดเดียวกัน**: ฟ้าที่ไหลอยู่หน้าหนึ่งแล้วแข็งค้างในอีกหน้าอ่านเป็น
// จอที่ค้าง ไม่ใช่สองมุมมองของอากาศเดียวกัน และเป็นสิ่งที่คนปัดสลับสองหน้าเจอทันที
// ราคาที่จ่ายคือผืนนี้ถูก invalidate ตามจังหวะ ไม่ใช่เฉพาะตอนเฟรมหรือชั่วโมงเปลี่ยน
// (ดู `ct_weather_ui_tick` — ย่านที่วาดใหม่มีเลข 48px ยืนอยู่ด้วย)
static const uint16_t SKY_BG[CT_SKY_PHASE_COUNT] = {
    CT_COL_SKY_NIGHT, CT_COL_SKY_DAWN, CT_COL_SKY_DAY, CT_COL_SKY_DUSK};
static const uint16_t SKY_GROUND[CT_SKY_PHASE_COUNT] = {
    CT_COL_GROUND_NIGHT, CT_COL_GROUND_DAWN, CT_COL_GROUND_DAY, CT_COL_GROUND_DUSK};
static const uint16_t SKY_GRASS[CT_SKY_PHASE_COUNT] = {
    CT_COL_GRASS_NIGHT, CT_COL_GRASS_DAWN, CT_COL_GRASS_DAY, CT_COL_GRASS_DUSK};
// สีของก้อนลอยตอนฟ้าโล่ง — กลางคืนไม่มีเมฆ ช่องแรกจึงไม่ถูกใช้ (ดู `cloud_color`)
static const uint16_t SKY_CLOUD[CT_SKY_PHASE_COUNT] = {0, CT_COL_CLOUD_DAWN, CT_COL_CLOUD_DAY,
                                                       CT_COL_CLOUD_DUSK};

// ช่วงเวลาของฉาก — CT_SKY_NONE = ไม่มีฉากเลย ปล่อยให้เป็นพื้นจอเปล่า
// ต้องตรงกับ scene_phase() ใน tools/gen/weather.py
//
// เวลามาจากนาฬิกาบนแถบบน ไม่ได้อยู่ในเฟรมของหน้านี้ — Mac ส่งเวลามาทุกวินาทีอยู่แล้ว
// ส่วนเฟรมอากาศมาทุก 15 นาที การใส่เวลาลงไปด้วยคือสำเนาที่เก่ากว่าอีกใบ
static ct_sky_phase_t scene_phase(void)
{
    if (!s_connected || !*s_has_frame) return CT_SKY_NONE;
    float h = ct_clock_hours(s_mascot->clock);
    return h < 0.0f ? CT_SKY_NONE : ct_sky_phase_at(h);
}

// ย่านฟ้าตอนนี้พื้นสว่างหรือยัง — ต้องตรงกับ sky_is_light() ใน tools/gen/weather.py
//
// บรรทัดเดียวนี้คือทั้งหมดที่ตัดสินว่าตัวหนังสือในย่านฟ้าเป็นชุด text หรือชุด ink
// ถ้ามันแตกเป็นหลายเงื่อนไขเมื่อไร จะมีสภาพหนึ่งที่เลข 48px กลืนหายไปกับพื้นโดยไม่มีใคร
// เจอจนกว่าจะถึงชั่วโมงนั้นของวันที่อากาศแบบนั้นพอดี
//
// พายุไม่นับเป็นกลางวันไม่ว่ากี่โมง เพราะฉากพายุแทนที่สีฟ้าทั้งย่านด้วยฟ้ามืดของมันเอง
static bool sky_is_light(ct_sky_phase_t phase, ct_wx_kind_t kind)
{
    return phase == CT_SKY_DAY && kind != CT_WX_STORM;
}

static void fill_rect(lv_layer_t *layer, int x0, int y0, int x1, int y1, uint16_t color,
                      int radius)
{
    if (x1 < x0 || y1 < y0) return;
    lv_draw_rect_dsc_t dsc;
    lv_draw_rect_dsc_init(&dsc);
    dsc.bg_opa = LV_OPA_COVER;
    dsc.border_width = 0;
    dsc.bg_color = ct_color(color);
    dsc.radius = radius;
    lv_area_t a = {.x1 = x0, .y1 = y0, .x2 = x1, .y2 = y1};
    lv_draw_rect(layer, &dsc, &a);
}

// ก้นแนวเมฆของแต่ละกลุ่ม — 0 คือกลุ่มที่ไม่มีแนวเมฆเลย (โล่ง/หมอก)
// ต้องตรงกับ DECK_BOTTOM ใน tools/gen/weather.py
static int deck_bottom(ct_wx_kind_t kind)
{
    switch (kind) {
        case CT_WX_CLOUD: return CT_WEATHER_DECK_CLOUD_Y;
        case CT_WX_RAIN:
        case CT_WX_SNOW: return CT_WEATHER_DECK_WET_Y;
        case CT_WX_STORM: return CT_WEATHER_DECK_STORM_Y;
        default: return 0;
    }
}

// สีของแนวเมฆบนหน้านี้ — สองทาง ไม่ใช่สามทางแบบหน้ามาสคอต: หน้านี้ไม่มีชุดฟ้าครึ้ม
// (`wx_dull_*`) เลย ฟ้าของมันเป็นสีของช่วงเวลาล้วนหรือฟ้าพายุ ไม่มีอะไรอยู่ระหว่างกลาง
// ต้องตรงกับ _deck_color() ใน tools/gen/weather.py
static inline uint16_t deck_color(ct_wx_kind_t kind, ct_sky_phase_t phase)
{
    return kind == CT_WX_STORM ? CT_COL_WX_STORM_DECK : CT_SKY_DECK[phase];
}

// สีของก้อนลอย — 0 คือช่วงที่ไม่มีก้อนลอยเลย (กลางคืน)
// ต้องตรงกับ _cloud_color() ใน tools/gen/weather.py
//
// **ก้อนลอยสว่างกว่าฟ้าได้เฉพาะตอนที่หมึกเป็นชุดเข้ม** — เงื่อนไขเดียวกับ `sky_is_light`
// ไม่ใช่เงื่อนไขใหม่ และนี่คือที่ที่หน้านี้ต่างจากหน้ามาสคอตจริงๆ: ที่นั่นไม่มีตัวอักษรอยู่ใน
// ย่านฟ้าเลย ก้อนขาวจะลอยผ่านอะไรก็ได้ ส่วนที่นี่เลข 48px ยืนอยู่กลางย่านนั้น และก้อนลอย
// เป็นสิ่งเดียวบนจอที่ *เดินผ่านใต้ตัวหนังสือได้* · วัดแล้ว: ขาวบน cloud_dusk เหลือ 2.78:1
// (บนฟ้าเปล่าได้ 7.10) และบน cloud_dawn เหลือ 3.83:1 — เลขที่จางลงทุกครั้งที่เมฆลอยผ่าน
// คือบั๊กที่โผล่วันละสองครั้ง · สีแนวเมฆของช่วงเดียวกันได้ 4.50/4.24 ซึ่งเท่ากับก้อนที่ห้อย
// จากแนวเมฆที่หน้านี้ทาบเลขอยู่แล้ว จึงเป็นเพดานที่หน้านี้ยอมรับไปแล้ว ไม่ใช่เกณฑ์ใหม่
static inline uint16_t cloud_color(ct_wx_kind_t kind, ct_sky_phase_t phase)
{
    if (phase == CT_SKY_NIGHT) return 0;
    bool light = kind == CT_WX_CLEAR && sky_is_light(phase, kind);
    return light ? SKY_CLOUD[phase] : deck_color(kind, phase);
}

static void draw_deck(lv_layer_t *layer, ct_wx_kind_t kind, ct_sky_phase_t phase)
{
    int bottom = deck_bottom(kind);
    if (bottom == 0) return;
    uint16_t color = deck_color(kind, phase);
    fill_rect(layer, 0, CT_TOPBAR_HEIGHT, CT_SCREEN_WIDTH - 1, bottom - 1, color, 0);
    // ก้อนที่ห้อยลงจากก้นแนว — ก้นที่เป็นเส้นตรงอ่านเป็นแถบสี ไม่ใช่เมฆ
    // รัศมีเท่าครึ่งความลึก ก้อนจึงเป็นครึ่งวงกลมพอดี
    for (int i = 0; i < CT_WEATHER_DECK_LUMPS_COUNT; i++) {
        int x = ct_weather_deck_lumps[i][0], w = ct_weather_deck_lumps[i][1];
        int h = ct_weather_deck_lumps[i][2];
        fill_rect(layer, x, bottom - h, x + w - 1, bottom + h - 1, color, h);
    }
}

// ดาวของย่านฟ้า — พอร์ตของ sky.draw_stars() ใน tools/gen/sky.py ตัวเดียวกับที่หน้า
// มาสคอตวาด (ฝั่ง Python ใช้ฟังก์ชันเดียวกันจริงๆ ฝั่ง C แต่ละไฟล์วาดของตัวเองตามเดิม)
static void draw_stars(lv_layer_t *layer, ct_sky_phase_t phase, ct_wx_kind_t kind)
{
    // พายุไม่มีดาวไม่ว่ากี่โมง และกลางวันก็ไม่มีอยู่แล้ว
    if (phase == CT_SKY_DAY || kind == CT_WX_STORM) return;
    const int d = CT_SKY_STAR_PX - 1;
    if (phase != CT_SKY_NIGHT) {
        // ฟ้ายังสว่างเกินกว่าจะเห็นทั้งหมด — ดวงแรกๆ สีหรี่ ไม่กะพริบ
        for (int i = 0; i < CT_SKY_LOW_STAR_N; i++) {
            int x = ct_sky_stars[i][0], y = ct_sky_stars[i][1];
            fill_rect(layer, x, y, x + d, y + d, CT_COL_STAR_DIM, 0);
        }
        return;
    }
    // ดวงที่กะพริบไล่สว่างขึ้นแล้วหรี่ลง: dim -> mid -> star(โต) -> mid ขั้นละ 1 วินาที
    // ตั้งต้นที่หรี่แล้วสว่างขึ้น ไม่ใช่ตั้งต้นสว่างแล้วดับ — ดาวดับอ่านเป็นจอเสีย
    // i * 3 ทำให้สี่ดวงเริ่มคนละขั้น (0,3,2,1) ไม่กะพริบพร้อมกันเป็นจังหวะเดียว
    static const uint16_t ramp[4] = {CT_COL_STAR_DIM, CT_COL_STAR_MID, CT_COL_STAR,
                                     CT_COL_STAR_MID};
    static const int ramp_px[4] = {CT_SKY_STAR_PX, CT_SKY_STAR_PX, CT_SKY_STAR_PEAK_PX,
                                   CT_SKY_STAR_PX};
    // ฟ้าที่ถูกเมฆปิดก็เห็นไม่ครบเหมือนกัน — เหตุที่สอง ไม่ใช่กฎที่สอง แต่ *ยังกะพริบ*
    // ต่างจากทาง dawn/dusk ข้างบน เพราะกลางคืนที่เป็นเมฆล้วนไม่มีทั้งก้อนลอย (กลางคืน
    // ไม่มี) และของที่ตกลงมา ดาวที่หยุดกะพริบด้วยจะทำให้จอนิ่งสนิททั้งคืน
    int n = deck_bottom(kind) != 0 ? CT_SKY_LOW_STAR_N : CT_SKY_STARS_COUNT;
    for (int i = 0; i < n; i++) {
        int x = ct_sky_stars[i][0], y = ct_sky_stars[i][1];
        if (i >= CT_SKY_TWINKLE_N) {
            fill_rect(layer, x, y, x + d, y + d, CT_COL_STAR, 0);
            continue;
        }
        int step = (s_cycle + i * 3) % 4, s = ramp_px[step];
        // โตออกจากกึ่งกลาง ไม่ใช่ยืดลงขวา — ไม่งั้นดวงที่โตขึ้นอ่านเป็นดาวเลื่อนที่
        int off = (s - CT_SKY_STAR_PX) / 2;
        fill_rect(layer, x - off, y - off, x - off + s - 1, y - off + s - 1, ramp[step], 0);
    }
}

// ก้อนเมฆลอยผ่านย่านฟ้า — ตารางกับความเร็วเป็นของ `[sky]` ชุดเดียวกับหน้ามาสคอต
// ต้องตรงกับ sky.draw_clouds() ใน tools/gen/sky.py
static void draw_clouds(lv_layer_t *layer, float t, uint16_t color)
{
    if (color == 0) return;
    float span = (float)(CT_SCREEN_WIDTH + 2 * CT_SKY_CLOUD_PAD);
    for (int i = 0; i < CT_SKY_CLOUDS_COUNT; i++) {
        float base_x = ct_sky_clouds[i][0];
        int y = ct_sky_clouds[i][1], w = ct_sky_clouds[i][2];
        float x = fmodf(base_x + t * (float)CT_SKY_CLOUD_SPEED_PX_S, span) - CT_SKY_CLOUD_PAD;
        int xi = (int)lroundf(x);
        fill_rect(layer, xi, y, xi + w, y + 9, color, 4);
        // ก้อนบนทำให้อ่านเป็นเมฆ ไม่ใช่แถบ — เยื้องซ้ายของกึ่งกลาง ไม่ใช่สมมาตร
        int bx = (int)lroundf(x + w * 0.2f), bw = (int)lroundf(w * 0.45f);
        fill_rect(layer, bx, y - 5, bx + bw, y + 4, color, 4);
    }
}

static int fall_shift(float t, int speed)
{
    return (int)(t * (float)speed);
}

// สายฟ้าติดอยู่ไหม ณ วินาทีที่ `t` — ต้องตรงกับ bolt_on() ใน tools/gen/weather.py
//
// แลบสองแฉกในวินาทีเดียวแล้วมืดจนครบรอบ ไม่ใช่ติด-ดับสลับเท่าๆ กัน: อย่างหลังอ่านเป็น
// ไฟกะพริบ ไม่ใช่ฟ้าแลบ · แบ่งวินาทีเป็นสี่เสี้ยวแล้วติดที่เสี้ยวคู่ ทำให้แฉกละ 250ms
// ซึ่งหยาบพอให้รอบวาด ~4 ครั้ง/วิ จับได้ทุกขอบ ไม่ต้องดันย่านฟ้าให้วาดใหม่ทุกเฟรม
static bool bolt_on(float t)
{
    if ((int)t % CT_WEATHER_BOLT_PERIOD_S) return false;
    int q = (int)(fmodf(t, 1.0f) * 4.0f);
    return q == 0 || q == 2;
}

// เม็ดวนรอบระหว่างก้นแนวเมฆกับเส้นขอบฟ้า *ของหน้านี้* ไม่ใช่ของหน้ามาสคอต — ทั้งสองค่า
// ต่างกันทั้งคู่ (แนวลึกกว่า ขอบฟ้าต่ำกว่า) สิ่งเดียวที่ใช้ร่วมคือความเร็วกับตัวคิดระยะเลื่อน
static void draw_fall(lv_layer_t *layer, ct_wx_kind_t kind, bool light, float t)
{
    const int top = deck_bottom(kind), span = CT_WEATHER_HORIZON - top;
    if (kind == CT_WX_RAIN) {
        int shift = fall_shift(t, CT_SKY_RAIN_SPEED_PX_S);
        for (int i = 0; i < CT_WEATHER_RAIN_COUNT; i++) {
            int x = ct_weather_rain[i][0], len = ct_weather_rain[i][2];
            int y = top + (ct_weather_rain[i][1] - top + shift) % span;
            fill_rect(layer, x, y, x + CT_WEATHER_RAIN_W - 1, y + len - 1, CT_COL_STEEL, 0);
        }
        return;
    }
    if (kind != CT_WX_SNOW) return;
    uint16_t color = light ? CT_COL_WX_FLAKE_INK : CT_COL_WX_FLAKE;
    int shift = fall_shift(t, CT_SKY_SNOW_SPEED_PX_S);
    for (int i = 0; i < CT_WEATHER_SNOW_COUNT; i++) {
        int x = ct_weather_snow[i][0], s = ct_weather_snow[i][2];
        int y = top + (ct_weather_snow[i][1] - top + shift) % span;
        fill_rect(layer, x, y, x + s - 1, y + s - 1, color, 0);
    }
}

static void scene_draw_cb(lv_event_t *e)
{
    ct_sky_phase_t phase = scene_phase();
    if (phase == CT_SKY_NONE) return;  // ไม่มีฉาก = ปล่อยให้เป็นพื้นจอเปล่า

    lv_layer_t *layer = lv_event_get_layer(e);
    ct_wx_kind_t kind = ct_sky_bucket(s_frame->code);
    bool storm = kind == CT_WX_STORM;
    float t = (float)s_cycle + s_phase;

    fill_rect(layer, 0, CT_TOPBAR_HEIGHT, CT_SCREEN_WIDTH - 1, CT_WEATHER_HORIZON - 1,
              storm ? CT_COL_WX_STORM_SKY : SKY_BG[phase], 0);

    // ดาวก่อนแนวเมฆ — เมฆที่ปิดฟ้าต้องบังดาวได้ ไม่ใช่ลอยอยู่ใต้มัน
    draw_stars(layer, phase, kind);
    // ก้อนลอยหลังดาว ก่อนแนวเมฆ — ลำดับเดียวกับหน้ามาสคอต ต่างแค่ที่นี่ไม่มีดวงคั่นกลาง
    // (หน้านี้บอกสภาพด้วยไอคอน ส่วนเวลาอยู่บนแถบบน ดวงอาทิตย์จึงไม่มีงานให้ทำ)
    draw_clouds(layer, t, cloud_color(kind, phase));

    draw_deck(layer, kind, phase);
    draw_fall(layer, kind, sky_is_light(phase, kind), t);
    if (kind == CT_WX_FOG) {
        // หมอกไม่มีแนวเมฆ — แถบนอนที่หนาขึ้นเมื่อเข้าใกล้ขอบฟ้า
        for (int i = 0; i < CT_WEATHER_FOG_BANDS_COUNT; i++) {
            int y = ct_weather_fog_bands[i][0], h = ct_weather_fog_bands[i][1];
            fill_rect(layer, 0, y, CT_SCREEN_WIDTH - 1, y + h - 1, CT_SKY_DECK[phase], 0);
        }
    }
    if (storm && bolt_on(t)) {
        for (int i = 0; i < CT_WEATHER_BOLT_COUNT; i++) {
            int x = ct_weather_bolt[i][0], y = ct_weather_bolt[i][1];
            int w = ct_weather_bolt[i][2], h = ct_weather_bolt[i][3];
            fill_rect(layer, x, y, x + w - 1, y + h - 1, CT_COL_ACCENT, 0);
        }
    }

    // พื้นดินวาดทับหลังสุด — สิ่งที่ตกต่ำเกินเส้นขอบฟ้าจึงถูกตัดที่เส้นนั้นเอง
    fill_rect(layer, 0, CT_WEATHER_HORIZON, CT_SCREEN_WIDTH - 1, CT_SCREEN_HEIGHT - 1,
              storm ? CT_COL_GROUND_NIGHT : SKY_GROUND[phase], 0);
    // กอหญ้าชุดเดียวกับหน้ามาสคอต แต่เส้นขอบฟ้าคนละเส้น — สีของมันถูกจูนให้ได้ 2:1 กับ
    // *ฟ้า* ของช่วงนั้น ซึ่งยังจริงอยู่ที่นี่ ฟ้าเป็นชุดเดียวกัน
    // พายุยืมหญ้าของ dusk ไม่ใช่ของ night ทั้งที่ฟ้ามัน *มืด* — เกณฑ์ของสีหญ้าคือ 2:1
    // กับฟ้าของช่วงนั้น และฟ้าพายุที่ขอบฟ้าคือแถบสว่างค้าง ไม่ใช่ฟ้ากลางคืนที่เกือบดำ
    // grass_night ตรงนั้นได้ 1.2:1 คือหายไปทั้งแถว ส่วน grass_dusk เป็นเงาตัดขอบ
    uint16_t grass = storm ? CT_COL_GRASS_DUSK : SKY_GRASS[phase];
    int gy = CT_WEATHER_HORIZON - 1;
    for (int i = 0; i < CT_SKY_GRASS_X_COUNT; i++) {
        int x = ct_sky_grass_x[i];
        int main = 3 + i % 4, side = 2 + i % 3;
        fill_rect(layer, x, gy - main, x + 1, gy, grass, 0);
        fill_rect(layer, x - 3, gy - side, x - 2, gy, grass, 0);
        fill_rect(layer, x + 3, gy - (2 + (side + 1) % 3), x + 4, gy, grass, 0);
    }
}

// --- ไอคอน ---------------------------------------------------------------------
static void icon_draw_cb(lv_event_t *e)
{
    lv_obj_t *obj = lv_event_get_target_obj(e);
    lv_layer_t *layer = lv_event_get_layer(e);
    lv_area_t coords;
    lv_obj_get_coords(obj, &coords);

    ct_rects_t rects;
    // ยังไม่เคยได้ข้อมูล = เมฆเทาก้อนเดียว ไม่ใช่ผืนว่าง — หน้าเปล่าอ่านเป็นอุปกรณ์พัง
    build_icon(&rects, *s_has_frame ? s_frame->code : 3, *s_has_frame && s_connected,
               is_night(ct_clock_hours(s_mascot->clock)));
    ct_paint_rects(layer, &rects, coords.x1, coords.y1, CT_WEATHER_ICON_PX);
}

// แต่ละคอลัมน์รู้ชั่วโมงของตัวเอง จึงเลือกดวงของตัวเองได้ — แถบที่ข้ามพระอาทิตย์ตกจะเห็น
// ดวงอาทิตย์กลายเป็นดวงจันทร์ตรงชั่วโมงที่มันตกจริง
static void fc_icon_draw_cb(lv_event_t *e)
{
    lv_obj_t *obj = lv_event_get_target_obj(e);
    int i = (int)(intptr_t)lv_event_get_user_data(e);
    if (!*s_has_frame || i >= s_frame->hour_n) return;

    lv_layer_t *layer = lv_event_get_layer(e);
    lv_area_t coords;
    lv_obj_get_coords(obj, &coords);

    ct_rects_t rects;
    int h = (s_frame->hour_start + i) % 24;
    build_icon(&rects, s_frame->hour_code[i], s_connected, is_night((float)h));
    ct_paint_rects(layer, &rects, coords.x1, coords.y1, CT_WEATHER_FC_ICON_PX);
}

// --- ตัวช่วยสร้าง widget --------------------------------------------------------
static lv_obj_t *label(lv_obj_t *parent, const lv_font_t *font, uint16_t color, int x, int y)
{
    lv_obj_t *l = lv_label_create(parent);
    lv_obj_set_style_text_font(l, font, 0);
    lv_obj_set_style_text_color(l, ct_color(color), 0);
    lv_label_set_text(l, "");
    ct_label_set_pos(l, x, y);
    return l;
}

// กึ่งกลางคอลัมน์ที่ i — ต้องตรงกับ fc_center() ใน tools/gen/weather.py
static int fc_center(int i)
{
    return i * CT_WEATHER_FC_COL_W + CT_WEATHER_FC_COL_W / 2;
}

// ป้ายที่จัดกึ่งกลางรอบ `cx` — LVGL วางป้ายจากมุมซ้ายบน ความกว้างจึงต้องตั้งไว้ล่วงหน้า
// เหมือนช่องนับถอยหลังของหน้าปฏิทิน ไม่ใช่ให้มันโตตามข้อความ
static lv_obj_t *centered(lv_obj_t *parent, const lv_font_t *font, uint16_t color,
                          int cx, int y)
{
    lv_obj_t *l = label(parent, font, color, cx - CT_WEATHER_FC_COL_W / 2, y);
    lv_obj_set_width(l, CT_WEATHER_FC_COL_W);
    lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_CENTER, 0);
    return l;
}

void ct_weather_ui_init(lv_obj_t *parent, const ct_weather_t *frame, const bool *has_frame,
                        const ct_snapshot_t *mascot)
{
    s_frame = frame;
    s_has_frame = has_frame;
    s_mascot = mascot;

    // ฉากอยู่ล่างสุดของหน้า — LVGL เรียงชั้นตามลำดับสร้าง ทุกอย่างที่ตามมาจึงทับมันได้
    s_scene = lv_obj_create(parent);
    lv_obj_remove_style_all(s_scene);
    lv_obj_set_size(s_scene, CT_SCREEN_WIDTH, CT_SCREEN_HEIGHT - CT_TOPBAR_HEIGHT);
    lv_obj_set_pos(s_scene, 0, CT_TOPBAR_HEIGHT);
    lv_obj_remove_flag(s_scene, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(s_scene, scene_draw_cb, LV_EVENT_DRAW_MAIN, NULL);

    s_place = label(parent, ct_font_text_14(), CT_COL_TEXT, CT_WEATHER_PLACE_X,
                    CT_WEATHER_PLACE_Y);
    // ชื่อเมืองยาวเท่าไรก็ได้ (บริการภายนอกเป็นคนตั้ง) แต่พื้นที่มีเท่าเดิม — ตัดด้วยจุด
    // ไม่ใช่ปล่อยให้ล้นไปทับสัญลักษณ์
    lv_obj_set_width(s_place, CT_WEATHER_ICON_X - CT_WEATHER_PLACE_X - 8);
    lv_label_set_long_mode(s_place, LV_LABEL_LONG_DOT);

    s_temp = label(parent, &lv_font_montserrat_48, CT_COL_TEXT, CT_WEATHER_TEMP_X,
                   CT_WEATHER_TEMP_Y);
    _Static_assert(CT_WEATHER_TEMP_FONT == 48, "layout.toml and the font here must agree");
    s_hilo = label(parent, ct_font_text_14(), CT_COL_TEXT_DIM, CT_WEATHER_HILO_X,
                   CT_WEATHER_HILO_Y);
    // ฐานมาก่อนทุกอย่างที่อยู่ในมัน — LVGL เรียงชั้นตามลำดับสร้าง บรรทัดอายุกับมาสคอต
    // ต้องอยู่ *บน* แถบ ไม่ใช่ถูกมันทาทับ (ตรงกับลำดับใน `footer.draw`)
    // บนหน้านี้บรรทัดอายุถูกสร้างก่อนมาสคอต ฐานจึงต้องมาก่อนมันด้วย ไม่ใช่แค่ก่อนมาสคอต
    ct_footer_attach(parent, true);
    s_age = ct_age_label(parent);

    s_empty = label(parent, ct_font_text_14(), CT_COL_TEXT, CT_WEATHER_TEMP_X,
                    CT_WEATHER_EMPTY_Y);
    lv_label_set_text(s_empty, "No weather yet");
    s_empty_sub = label(parent, ct_font_text_12(), CT_COL_TEXT_DIM, CT_WEATHER_TEMP_X,
                        CT_WEATHER_EMPTY_SUB_Y);
    lv_label_set_text(s_empty_sub, "the mac has not sent this page");

    s_icon = lv_obj_create(parent);
    lv_obj_remove_style_all(s_icon);
    lv_obj_set_size(s_icon, CT_WEATHER_ICON_GRID * CT_WEATHER_ICON_PX,
                    CT_WEATHER_ICON_GRID * CT_WEATHER_ICON_PX);
    lv_obj_set_pos(s_icon, CT_WEATHER_ICON_X, CT_WEATHER_ICON_Y);
    lv_obj_remove_flag(s_icon, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(s_icon, icon_draw_cb, LV_EVENT_DRAW_MAIN, NULL);

    // แถบพยากรณ์นั่งบนพื้นดิน ซึ่งเข้มทุกช่วงเวลา — สีของมันจึงไม่ต้องกลับขั้วตามฟ้า
    _Static_assert(CT_WEATHER_FC_TEMP_FONT == 14, "layout.toml and the font here must agree");
    _Static_assert(CT_WEATHER_FC_HOUR_FONT == 12, "layout.toml and the font here must agree");
    const int side = CT_WEATHER_ICON_GRID * CT_WEATHER_FC_ICON_PX;
    for (int i = 0; i < CT_WEATHER_FC_COLS; i++) {
        int cx = fc_center(i);
        s_fc_hour[i] = centered(parent, ct_font_text_12(), CT_COL_TEXT_DIM, cx,
                                CT_WEATHER_FC_HOUR_Y);
        s_fc_icon[i] = lv_obj_create(parent);
        lv_obj_remove_style_all(s_fc_icon[i]);
        lv_obj_set_size(s_fc_icon[i], side, side);
        lv_obj_set_pos(s_fc_icon[i], cx - side / 2, CT_WEATHER_FC_ICON_Y);
        lv_obj_remove_flag(s_fc_icon[i], LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_add_event_cb(s_fc_icon[i], fc_icon_draw_cb, LV_EVENT_DRAW_MAIN,
                            (void *)(intptr_t)i);
        s_fc_temp[i] = centered(parent, ct_font_text_14(), CT_COL_TEXT, cx,
                                CT_WEATHER_FC_TEMP_Y);
    }

    ct_mini_attach(parent);

    paint_ink();
    ct_weather_ui_redraw();
}

static void show(lv_obj_t *obj, bool on)
{
    if (on) {
        lv_obj_remove_flag(obj, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(obj, LV_OBJ_FLAG_HIDDEN);
    }
}

void ct_weather_ui_redraw(void)
{
    bool have = *s_has_frame;
    // สองสภาพนี้ไม่เคยอยู่ด้วยกัน — หน้าที่ยังไม่เคยได้ข้อมูลไม่มีตัวเลขให้แสดงสักตัว
    show(s_temp, have);
    show(s_hilo, have);
    show(s_place, have);
    show(s_empty, !have);
    show(s_empty_sub, !have);

    if (have) {
        lv_label_set_text(s_place, s_frame->place);
        // ไม่มีสัญลักษณ์องศาในฟอนต์บนบอร์ด และการประดิษฐ์วงแหวนจาก rect ขึ้นมาเอง
        // เพื่อสิ่งที่ไม่มีใครอ่านผิดคือค่าใช้จ่ายที่ไม่คุ้ม — "31C" อ่านออกทันที
        lv_label_set_text_fmt(s_temp, "%d%c", s_frame->temp, s_frame->unit);
        lv_label_set_text_fmt(s_hilo, "H %d   L %d", s_frame->high, s_frame->low);
    }

    // เฟรมที่ไม่มีพยากรณ์ (host รุ่นก่อน หรือถูกบีบทิ้งเพราะชื่อเมืองยาว) ไม่วาดอะไรตรงนี้
    // ซึ่งไม่ใช่จอเปล่าตาม ADR-0002: ยังมีพื้นดิน กอหญ้า และบรรทัดอายุอยู่
    int hours = have ? s_frame->hour_n : 0;
    for (int i = 0; i < CT_WEATHER_FC_COLS; i++) {
        bool on = i < hours;
        show(s_fc_hour[i], on);
        show(s_fc_temp[i], on);
        show(s_fc_icon[i], on);
        if (!on) continue;
        // ชั่วโมงมีทวิภาคเสมอ — "15" เปล่าๆ อยู่เหนือ "32" อ่านเป็นตัวเลขสองแถวที่ต้องเดา
        // ว่าอันไหนคือเวลา ส่วน "15:00" ไม่มีใครอ่านเป็นอุณหภูมิ
        lv_label_set_text_fmt(s_fc_hour[i], "%02d:00", (s_frame->hour_start + i) % 24);
        lv_label_set_text_fmt(s_fc_temp[i], "%d", s_frame->hour_temp[i]);
        lv_obj_invalidate(s_fc_icon[i]);
    }

    paint_ink();
    lv_obj_invalidate(s_scene);
    lv_obj_invalidate(s_icon);
    ct_weather_ui_redraw_age();
}

void ct_weather_ui_redraw_age(void)
{
    if (!*s_has_frame) {
        lv_obj_add_flag(s_age, LV_OBJ_FLAG_HIDDEN);
        return;
    }
    lv_obj_remove_flag(s_age, LV_OBJ_FLAG_HIDDEN);
    ct_age_show(s_age, s_frame->age, CT_WEATHER_REFRESH_S);
}

// สีของตัวหนังสือในย่านฟ้าถูก *ผลัก* ลงป้าย ไม่ได้ถูกอ่านตอนวาดเหมือนสีในหน้ามาสคอต
// การตั้งค่าตั้งต้นจึงต้องเกิดตอน init ด้วย ไม่ใช่แค่ตอนสถานะเปลี่ยน — บอร์ดที่บูตขึ้นมา
// โดยยังไม่เจอ Mac เลยจะไม่มีการ "เปลี่ยน" ให้จับ แล้วตัวเลขที่ไม่มีใครรับรองจะขึ้นด้วย
// สีของข้อมูลสด
//
// ย่านล่างไม่ผ่านทางนี้: พื้นดินเข้มทุกช่วงเวลา สีของแถบพยากรณ์จึงขึ้นกับลิงก์อย่างเดียว
static void paint_ink(void)
{
    ct_sky_phase_t phase = scene_phase();
    ct_wx_kind_t kind = *s_has_frame ? ct_sky_bucket(s_frame->code) : CT_WX_CLOUD;
    bool light = sky_is_light(phase, kind);

    uint16_t text = light ? CT_COL_INK : CT_COL_TEXT;
    uint16_t dim = light ? CT_COL_INK_DIM : CT_COL_TEXT_DIM;
    if (!s_connected) {
        text = CT_COL_GRAY;
        dim = CT_COL_GRAY;
    }
    lv_obj_set_style_text_color(s_place, ct_color(text), 0);
    lv_obj_set_style_text_color(s_temp, ct_color(text), 0);
    lv_obj_set_style_text_color(s_hilo, ct_color(dim), 0);

    for (int i = 0; i < CT_WEATHER_FC_COLS; i++) {
        lv_obj_set_style_text_color(
            s_fc_temp[i], ct_color(s_connected ? CT_COL_TEXT : CT_COL_GRAY), 0);
        lv_obj_set_style_text_color(
            s_fc_hour[i], ct_color(s_connected ? CT_COL_TEXT_DIM : CT_COL_GRAY_DARK), 0);
    }
}

// นาฬิกาเดินข้ามขอบช่วงเวลา — ฟ้าต้องเปลี่ยนตามโดยไม่ต้องรอเฟรมอากาศใบถัดไปอีก 15 นาที
// (กติกาเดียวกับวันที่ตัวใหญ่บนหน้าปฏิทินที่ต้องข้ามเที่ยงคืนไปพร้อมนาฬิกาบนแถบ)
void ct_weather_ui_redraw_clock(void)
{
    static ct_sky_phase_t last = CT_SKY_NONE;
    static bool last_night;
    ct_sky_phase_t now = scene_phase();
    bool night = is_night(ct_clock_hours(s_mascot->clock));
    if (now == last && night == last_night) return;
    last = now;
    last_night = night;
    paint_ink();
    lv_obj_invalidate(s_scene);
    lv_obj_invalidate(s_icon);
    for (int i = 0; i < CT_WEATHER_FC_COLS; i++) lv_obj_invalidate(s_fc_icon[i]);
}

void ct_weather_ui_set_connected(bool connected)
{
    if (connected == s_connected) return;
    s_connected = connected;
    paint_ink();
    // หลุดลิงก์ = ฉากหายทั้งผืน clock ที่ค้างอยู่ไม่ใช่เวลาจริงอีกต่อไป
    lv_obj_invalidate(s_scene);
    lv_obj_invalidate(s_icon);
    for (int i = 0; i < CT_WEATHER_FC_COLS; i++) lv_obj_invalidate(s_fc_icon[i]);
}

// วาดใหม่เฉพาะ *ย่านฟ้า* ไม่ใช่ทั้งผืน — พื้นดินกับกอหญ้าอยู่ใต้เส้นขอบฟ้าและไม่มีอะไร
// ขยับที่นั่นเลย แต่แถบพยากรณ์ห้าคอลัมน์อยู่บนมัน การลากทั้งผืนจึงเป็นการวาดไอคอนห้าตัว
// กับตัวเลขสิบตัวใหม่ทุกเฟรมโดยที่ไม่มีพิกเซลไหนเปลี่ยน
static void invalidate_scene_band(void)
{
    lv_area_t a = {.x1 = 0, .y1 = CT_TOPBAR_HEIGHT, .x2 = CT_SCREEN_WIDTH - 1,
                   .y2 = CT_WEATHER_HORIZON - 1};
    lv_obj_invalidate_area(s_scene, &a);
}

// จังหวะเดียวกับ `ct_ui_tick` เป๊ะ: ฟ้าวาดใหม่ตอนเมฆขยับถึงพิกเซลถัดไป (~4 ครั้ง/วิ)
// หรือตอนวินาทีเดิน (ดาวกะพริบ) — ยกเว้นตอนมีของตกลงมา ที่ต้องทุกเฟรม ไม่งั้นฝนที่เดิน
// 4px ต่อเฟรมจะกระโดดทีละ 16px แทนที่จะไหล
//
// ราคาที่หน้านี้จ่ายแพงกว่าหน้ามาสคอต: ย่านที่วาดใหม่มีเลข 48px (`temp_y` = 52) ยืนอยู่
// LVGL จึงต้อง render montserrat_48 ใหม่ทุกครั้งที่ฝนขยับ · ยอมจ่ายเพราะเป็นการวาดย่าน
// เดิมถี่ขึ้นในลูปที่หมุนอยู่แล้ว ไม่ใช่เฟรมใหม่ และเฉพาะตอนหน้านี้อยู่บนจอกับฝน/หิมะจริง
// ถ้าวันหนึ่งเฟรมตก ทางแก้คือ invalidate เป็นคอลัมน์แคบต่อเม็ด ซึ่งได้ภาพเดียวกัน
void ct_weather_ui_tick(int elapsed_ms)
{
    s_phase += (float)elapsed_ms / (float)LOOP_MS;
    bool second_passed = false;
    while (s_phase >= 1.0f) {
        s_phase -= 1.0f;
        s_cycle++;
        second_passed = true;
    }
    if (scene_phase() == CT_SKY_NONE) return;  // ไม่มีฉาก = ไม่มีอะไรให้ขยับ

    float t = (float)s_cycle + s_phase;
    ct_wx_kind_t kind = ct_sky_bucket(s_frame->code);
    bool falling = kind == CT_WX_RAIN || kind == CT_WX_SNOW;
    int shift = (int)(t * (float)CT_SKY_CLOUD_SPEED_PX_S);
    // สายฟ้าถามตรงๆ ว่าเปลี่ยนหรือยัง ไม่ได้ฝากไว้กับจังหวะเมฆที่บังเอิญเป็นเสี้ยววินาที
    // เท่ากัน — ความเร็วเมฆเป็นค่าที่ปรับได้ วันที่มันเปลี่ยนฟ้าแลบจะหายไปเงียบๆ
    bool bolt = kind == CT_WX_STORM && bolt_on(t);
    if (falling || bolt != s_bolt_on || shift != s_cloud_shift || second_passed) {
        s_cloud_shift = shift;
        s_bolt_on = bolt;
        invalidate_scene_band();
    }
}
