// ฐานของทุกหน้า — พอร์ตคู่กับ tools/gen/footer.py
//
// เคยไม่มีไฟล์นี้ และนั่นคือปัญหา: บรรทัดอายุ (`ct_age`) กับมาสคอตจิ๋ว (`ct_mini`)
// เป็นของสองชิ้นที่บังเอิญอยู่ก้นจอด้วยกัน คนละ baseline ไม่มีพื้น ไม่มีขอบ ห่างกัน ~200px
// จอจึงมีหัวที่ชัด (`ct_topbar` มีพื้น มีจุดสถานะ มีโครง) แต่มีเท้าที่เปื่อย
//
// **ผืนเดียวต่อหน้า วาดเองด้วย rect ไม่ใช่ widget ใบละชิ้น** — เขียนแบบ widget มาก่อน
// (พื้น เส้น แท่น และ pip อย่างละใบ = 9 ใบ x 5 หน้า) แล้วบอร์ดค้างตาย: LVGL มี pool
// ของตัวเองขนาด 48KB (`CONFIG_LV_MEM_SIZE_KILOBYTES`) ซึ่งวัดแล้วเหลือ **780 ไบต์**
// หลัง init จอ พอจัดสรร draw task ไม่ได้ `lv_draw_dispatch` ก็วนรอไม่จบ main ไม่คืนจาก
// `lv_timer_handler` และ task watchdog ยิงทุก 5 วินาที · ผืนเดียวต่อหน้าคือ 5 ใบรวม
// และเป็นทางเดียวกับที่ `ct_mini` กับฉากของหน้าอากาศใช้อยู่แล้ว
#include "ct_footer.h"

#include "ct_mini.h"
#include "ct_paint.h"
#include "ct_rects.h"
#include "layout.h"

// คำนวณจาก height ตัวเดียว ไม่ได้เก็บซ้ำใน layout.toml — ต้องตรงกับ `TOP`/`MID_Y`
// ใน tools/gen/footer.py ซึ่งคำนวณด้วยสูตรเดียวกันนี้
#define FOOTER_TOP (CT_SCREEN_HEIGHT - CT_FOOTER_HEIGHT)
#define FOOTER_MID (FOOTER_TOP + CT_FOOTER_HEIGHT / 2)

// พิกัดข้างในผืนนับจากขอบบนของผืน ไม่ใช่จากขอบจอ
#define PIP_DY (FOOTER_MID - CT_FOOTER_PIP_H / 2 - FOOTER_TOP)
#define PLINTH_DY (CT_FOOTER_MINI_BOTTOM_Y - FOOTER_TOP)

// หน้าละหนึ่งผืน — ผืนที่เกินมาคือหน้าที่ attach สองครั้ง ซึ่งเป็นบั๊กที่เห็นได้ทันทีบนจอ
// (เหตุผลเดียวกับเพดานใน `ct_mini`)
static lv_obj_t *s_attached[CT_PAGE_KIND_COUNT];
// หน้ามาสคอตไม่มีแถบ: ที่นั่นมาสคอตตัวจริงอยู่กลางจอแล้ว ไม่มีข้อมูลที่ดึงมาจึงไม่มีอายุ
// ให้บอก และพื้นดินกินถึงขอบล่าง แถบทึบจะตัดฉากทิ้ง — แต่ pip ยังได้
static bool s_banded[CT_PAGE_KIND_COUNT];
static int s_count;

static bool s_connected;
static ct_footer_pos_t s_pos = {.index = -1, .count = 0, .left_ms = -1, .total_ms = 0};

static void fill(lv_layer_t *layer, float ox, float oy, int x, int y, int w, int h,
                 uint16_t color)
{
    ct_rect_t r = {.x = (float)x, .y = (float)y, .w = (float)w, .h = (float)h,
                   .color = color, .r = 0.0f};
    ct_paint_rect(layer, &r, ox, oy, 1.0f);
}

// ส่วนที่ยังเหลือของราง — ปิดรอบหมุนได้ *เต็มราง* ไม่ใช่รางเปล่า
//
// รางเปล่ากับรางเต็มต้องหมายถึงคนละเรื่อง: เปล่า = อีกแป๊บเดียวจะพลิก · เต็มค้าง =
// จะไม่พลิกเลย · ถ้าปิดรอบหมุนแล้วได้รางเปล่า มันจะอ่านว่า "กำลังจะพลิก" ค้างอยู่ทั้งคืน
static int fill_width(void)
{
    if (s_pos.left_ms < 0 || s_pos.total_ms <= 0) return CT_FOOTER_PIP_CUR_W;
    int left = s_pos.left_ms > s_pos.total_ms ? s_pos.total_ms : s_pos.left_ms;
    if (left < 0) left = 0;
    // ปัดครึ่งขึ้นแบบเดียวกับ `round()` ที่ฝั่ง Python ใช้กับความกว้างนี้
    return (CT_FOOTER_PIP_CUR_W * left + s_pos.total_ms / 2) / s_pos.total_ms;
}

// `has_mini` = หน้านี้มีมาสคอตจิ๋วให้หลบไหม (หน้ามาสคอตไม่มี)
static void draw_pips(lv_layer_t *layer, float ox, float oy, bool has_mini)
{
    int n = s_pos.count;
    // หน้าเดียวไม่มี pip: ไม่มีที่ให้ปัดไป จุดเดียวโดดๆ เป็นคำเชิญที่พาไปเจอความว่าง
    if (n < 2 || s_pos.index < 0 || s_pos.index >= n) return;

    // ความกว้างรวมไม่ขึ้นกับว่าหน้าไหนกำลังแสดง (กว้างหนึ่ง แคบ n-1 เสมอ) แถวจึงไม่
    // ขยับซ้ายขวาตอนหมุน — ที่ขยับคือ pip กว้างที่ไหลไปตามตำแหน่ง ซึ่งคือสิ่งที่ต้องอ่าน
    // แถวเกาะขอบขวาของฐาน ส่วนมาสคอตจิ๋วเป็นสิ่งที่มาแทนที่ขอบนั้นเมื่อมันมีอยู่
    int total = CT_FOOTER_PIP_CUR_W + (n - 1) * (CT_FOOTER_PIP_DOT_W + CT_FOOTER_PIP_GAP);
    int right = CT_SCREEN_WIDTH - CT_FOOTER_MINI_RIGHT;
    if (has_mini) {
        int mx, my, mw, mh;
        ct_mini_box(&mx, &my, &mw, &mh);
        right = mx - CT_FOOTER_PIP_RIGHT_GAP;
    }
    int x = right - total;
    for (int i = 0; i < n; i++) {
        int w = i == s_pos.index ? CT_FOOTER_PIP_CUR_W : CT_FOOTER_PIP_DOT_W;
        // ราง (gray_dark) กับจุดอื่นเป็นเฟอร์นิเจอร์ชุดเดียวกัน ส่วนที่เติมเป็นสีมาสคอต
        // ภาษาเดียวกับแถบโควตาบนแถบบน: ราง + ส่วนที่เติม ไม่ใช่แท่งที่หดตัว
        // *ความกว้าง* คือแกนที่บอกว่าหน้าไหนกำลังแสดง ไม่ใช่สี — จอนี้ห้ามใช้สีเป็นแกนเดียว
        fill(layer, ox, oy, x, PIP_DY, w, CT_FOOTER_PIP_H, CT_COL_GRAY_DARK);
        if (i == s_pos.index) {
            int fw = fill_width();
            if (fw > 0) fill(layer, ox, oy, x, PIP_DY, fw, CT_FOOTER_PIP_H, CT_COL_CLAY);
        }
        x += w + CT_FOOTER_PIP_GAP;
    }
}

static void footer_draw_cb(lv_event_t *e)
{
    lv_obj_t *obj = lv_event_get_target_obj(e);
    lv_layer_t *layer = lv_event_get_layer(e);
    lv_area_t coords;
    lv_obj_get_coords(obj, &coords);
    float ox = (float)coords.x1, oy = (float)coords.y1;

    bool banded = false;
    for (int i = 0; i < s_count; i++) {
        if (s_attached[i] == obj) banded = s_banded[i];
    }

    if (banded) {
        fill(layer, ox, oy, 0, 0, CT_SCREEN_WIDTH, CT_FOOTER_HEIGHT, CT_COL_BG_SLOT);
        // **เส้นคือสิ่งที่ประกาศว่ามีฐานอยู่ ไม่ใช่พื้น** — bg_slot ต่างจากพื้นจอแค่ 1.05:1
        // ซึ่งวัดแล้วคือมองไม่เห็น (หลักฐานเดียวกับที่ทำให้การ์ดปฏิทินต้องมีขอบ)
        // พื้นยังมีเพราะมันทำงานจริงบนหน้าอากาศ ที่ฐานไปนั่งในแถบพยากรณ์เขียวเข้ม
        fill(layer, ox, oy, 0, 0, CT_SCREEN_WIDTH, CT_FOOTER_RULE_H, CT_COL_GRAY_DARK);

        // แท่น *ไม่ใช่เงา*: บนพื้นเข้ม เงาที่เข้มกว่าพื้นมองไม่เห็น สิ่งที่ทำงานคือแท่นสว่าง
        // สว่างกว่าเส้นขอบบนหนึ่งขั้นเพราะมันเป็นของเฉพาะที่ ไม่ใช่โครงของจอ
        // ไม่มี Mac = ไม่มีมาสคอต = ไม่มีแท่น (แท่นเปล่าอ่านว่า "ตัวหายไปไหน")
        if (s_connected) {
            int mx, my, mw, mh;
            ct_mini_box(&mx, &my, &mw, &mh);
            fill(layer, ox, oy, mx - CT_FOOTER_PLINTH_PAD, PLINTH_DY,
                 mw + 2 * CT_FOOTER_PLINTH_PAD, CT_FOOTER_PLINTH_H, CT_COL_GRAY);
        }
    }
    // หน้าที่มีแถบคือหน้าที่มีมาสคอตจิ๋ว — ธงเดียวกันตอบทั้งสองเรื่องเพราะมันคือเรื่องเดียวกัน
    // ("หน้านี้เป็นหน้าข้อมูลไหม") ธงที่สองจะกลายเป็นสองความจริงที่ต้องคอยจับให้ตรงกัน
    draw_pips(layer, ox, oy, banded);
}

void ct_footer_attach(lv_obj_t *parent, bool with_band)
{
    if (s_count >= CT_PAGE_KIND_COUNT) return;

    lv_obj_t *obj = lv_obj_create(parent);
    lv_obj_remove_style_all(obj);
    lv_obj_set_size(obj, CT_SCREEN_WIDTH, CT_FOOTER_HEIGHT);
    lv_obj_set_pos(obj, 0, FOOTER_TOP);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(obj, footer_draw_cb, LV_EVENT_DRAW_MAIN, NULL);

    s_banded[s_count] = with_band;
    s_attached[s_count++] = obj;
}

// ผืนของหน้าที่ถูกซ่อนอยู่ก็ถูกสั่งวาดใหม่ด้วย เพราะ LVGL ไม่วาดของที่ซ่อนอยู่จริงๆ อยู่แล้ว
// (เหตุผลเดียวกับ `invalidate_all` ใน `ct_mini`)
static void invalidate_all(void)
{
    for (int i = 0; i < s_count; i++) lv_obj_invalidate(s_attached[i]);
}

void ct_footer_set_connected(bool connected)
{
    if (connected == s_connected) return;
    s_connected = connected;
    invalidate_all();
}

void ct_footer_set_pos(const ct_footer_pos_t *pos)
{
    // เทียบสิ่งที่ *วาดออกมา* ไม่ใช่ตัวเลขดิบ — รางกว้าง 14px ในรอบสิบวินาทีขยับทุก
    // ~700ms ส่วน left_ms ขยับทุก tick การวาดใหม่ตามตัวเลขคือการวาดจอทิ้งวินาทีละสิบครั้ง
    ct_footer_pos_t was = s_pos;
    int was_fill = fill_width();
    s_pos = *pos;
    if (pos->index == was.index && pos->count == was.count && fill_width() == was_fill) {
        return;
    }
    invalidate_all();
}
