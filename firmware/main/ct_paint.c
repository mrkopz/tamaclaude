#include "ct_paint.h"

#include <math.h>

#include "ct_color.h"

void ct_paint_rects(lv_layer_t *layer, const ct_rects_t *rects, float ox, float oy, float px)
{
    lv_draw_rect_dsc_t dsc;
    lv_draw_rect_dsc_init(&dsc);
    dsc.bg_opa = LV_OPA_COVER;
    dsc.border_width = 0;

    for (int i = 0; i < rects->count; i++) {
        const ct_rect_t *r = &rects->items[i];
        int x0 = (int)lroundf(ox + r->x * px);
        int y0 = (int)lroundf(oy + r->y * px);
        int x1 = (int)lroundf(ox + (r->x + r->w) * px);
        int y1 = (int)lroundf(oy + (r->y + r->h) * px);
        if (x1 <= x0 || y1 <= y0) continue;  // ชิ้นที่บางกว่าหนึ่งพิกเซลหายไปเลย
        // clamp เองแทนที่จะปล่อยให้ LVGL ทำ — ฝั่ง preview ใช้ PIL ซึ่งไม่ clamp ให้
        // ถ้าปล่อยไปคนละทาง ขาที่ยุบจนเตี้ยจะออกมาคนละรูปบนจอกับบน preview
        int radius = (int)lroundf(r->r * px);
        int half = ((x1 - x0) < (y1 - y0) ? (x1 - x0) : (y1 - y0)) / 2;
        dsc.radius = radius < half ? radius : half;
        dsc.bg_color = ct_color(r->color);
        lv_area_t a = {.x1 = x0, .y1 = y0, .x2 = x1 - 1, .y2 = y1 - 1};
        lv_draw_rect(layer, &dsc, &a);
    }
}
