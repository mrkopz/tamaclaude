#include "ct_paint.h"

#include <math.h>

#include "ct_color.h"

void ct_paint_rect(lv_layer_t *layer, const ct_rect_t *r, float ox, float oy, float px)
{
    lv_draw_rect_dsc_t dsc;
    lv_draw_rect_dsc_init(&dsc);
    dsc.bg_opa = LV_OPA_COVER;
    dsc.border_width = 0;

    int x0 = (int)lroundf(ox + r->x * px);
    int y0 = (int)lroundf(oy + r->y * px);
    int x1 = (int)lroundf(ox + (r->x + r->w) * px);
    int y1 = (int)lroundf(oy + (r->y + r->h) * px);
    if (x1 <= x0 || y1 <= y0) return;  // ชิ้นที่บางกว่าหนึ่งพิกเซลหายไปเลย
    // clamp เองแทนที่จะปล่อยให้ LVGL ทำ — ฝั่ง preview ใช้ PIL ซึ่งไม่ clamp ให้
    // ถ้าปล่อยไปคนละทาง ขาที่ยุบจนเตี้ยจะออกมาคนละรูปบนจอกับบน preview
    int radius = (int)lroundf(r->r * px);
    int half = ((x1 - x0) < (y1 - y0) ? (x1 - x0) : (y1 - y0)) / 2;
    dsc.radius = radius < half ? radius : half;
    dsc.bg_color = ct_color(r->color);
    lv_area_t a = {.x1 = x0, .y1 = y0, .x2 = x1 - 1, .y2 = y1 - 1};
    lv_draw_rect(layer, &dsc, &a);
}

void ct_paint_rects(lv_layer_t *layer, const ct_rects_t *rects, float ox, float oy, float px)
{
    for (int i = 0; i < rects->count; i++) ct_paint_rect(layer, &rects->items[i], ox, oy, px);
}

void ct_paint_triangle(lv_layer_t *layer, const ct_pt_t p[3], uint16_t color, float ox,
                       float oy, float px)
{
    lv_draw_triangle_dsc_t dsc;
    lv_draw_triangle_dsc_init(&dsc);
    dsc.bg_opa = LV_OPA_COVER;
    dsc.bg_color = ct_color(color);
    for (int i = 0; i < 3; i++) {
        // ปัดเป็นจำนวนเต็มเพราะ LVGL คอมไพล์มาแบบ LV_USE_FLOAT ปิด — ขอบเฉียงยังนุ่ม
        // อยู่ (mask line คิด coverage ต่อพิกเซลจากสมการเส้น) ที่หายไปคือปลายที่ตกครึ่ง
        // พิกเซล ซึ่งที่ขนาด 16-20px ไม่มีใครเห็น
        dsc.p[i].x = (lv_value_precise_t)lroundf(ox + p[i].x * px);
        dsc.p[i].y = (lv_value_precise_t)lroundf(oy + p[i].y * px);
    }
    lv_draw_triangle(layer, &dsc);
}
