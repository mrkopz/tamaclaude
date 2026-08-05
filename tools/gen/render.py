"""วาด rect list ลงภาพ — ตัวแทนของ lv_draw_rect ฝั่ง Python

หน้าที่เดียว: พิสูจน์ว่า *การออกแบบ* ถูก ไม่ได้พิสูจน์ renderer ฝั่ง C
ค่าคงที่ layout มาจาก layout.toml ชุดเดียวกับที่ generate เป็น layout.h
"""

from __future__ import annotations

from PIL import Image, ImageDraw

from .rects import RectList


def hex_rgb(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


def to_rgb565(s: str) -> int:
    """สีที่ firmware จะใช้จริง — เก็บไว้ตรวจว่าสีเพี้ยนตอนลดบิตหรือไม่"""
    r, g, b = hex_rgb(s)
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)


def quantize565(s: str) -> tuple[int, int, int]:
    """สีหลังบีบเป็น RGB565 แล้วขยายกลับ — ตรงกับที่ตาเห็นบนจอจริง"""
    v = to_rgb565(s)
    r5, g6, b5 = (v >> 11) & 0x1F, (v >> 5) & 0x3F, v & 0x1F
    return (r5 * 255 + 15) // 31, (g6 * 255 + 31) // 63, (b5 * 255 + 15) // 31


def draw_rects(
    draw: ImageDraw.ImageDraw,
    rects: RectList,
    px: float,
    ox: float = 0.0,
    oy: float = 0.0,
    true_color: bool = False,
) -> None:
    """ox/oy = พิกัดพิกเซลของจุด (0,0) ในตาราง unit"""
    conv = hex_rgb if true_color else quantize565
    for r in rects:
        x0 = round(ox + r.x * px)
        y0 = round(oy + r.y * px)
        x1 = round(ox + (r.x + r.w) * px)
        y1 = round(oy + (r.y + r.h) * px)
        if x1 <= x0 or y1 <= y0:
            continue
        # clamp เองทั้งสองฝั่ง ไม่ปล่อยให้ backend ตัดสิน — LVGL clamp ให้ แต่ PIL ไม่
        # ถ้าปล่อย ขาที่ยุบจนเตี้ยจะออกมาคนละรูปบน preview กับบนบอร์ด
        radius = min(round(r.r * px), (x1 - x0) // 2, (y1 - y0) // 2)
        if radius > 0:
            draw.rounded_rectangle([x0, y0, x1 - 1, y1 - 1], radius=radius, fill=conv(r.color))
        else:
            draw.rectangle([x0, y0, x1 - 1, y1 - 1], fill=conv(r.color))


# กี่เท่าที่ขยายก่อนย่อกลับเพื่อให้ได้ขอบนุ่ม — 8 เท่าให้ 64 ระดับต่อพิกเซล ซึ่งเกินกว่าที่
# ตาแยกออกบนแผง RGB565 อยู่แล้ว สูงกว่านี้คือเวลาเรนเดอร์ที่ไม่มีใครเห็นผล
_AA = 8


def draw_poly(
    img: Image.Image,
    points: tuple[tuple[float, float], ...],
    px: float,
    ox: float = 0.0,
    oy: float = 0.0,
    color: str = "#ffffff",
    true_color: bool = False,
) -> None:
    """รูปหลายเหลี่ยมขอบนุ่ม — ตัวแทนของ ct_paint_triangle() ฝั่ง Python

    PIL วาด polygon แบบขอบแข็งอย่างเดียว จึงวาดลง mask ที่ขยาย `_AA` เท่าแล้วย่อกลับ
    ด้วย BOX (= เฉลี่ยพื้นที่จริง) ผลที่ได้คือ coverage ต่อพิกเซลแบบเดียวกับที่ LVGL
    คำนวณจาก mask line · ไม่ใช่ผลลัพธ์เดียวกันบิตต่อบิตกับบอร์ด และไม่ต้องเป็น — พรีวิว
    พิสูจน์ *การออกแบบ* ไม่ใช่ renderer (ดูหัวไฟล์)
    """
    xs = [ox + x * px for x, _ in points]
    ys = [oy + y * px for _, y in points]
    x0, y0 = int(min(xs)), int(min(ys))
    w, h = int(max(xs)) - x0 + 1, int(max(ys)) - y0 + 1
    if w <= 0 or h <= 0:
        return
    mask = Image.new("L", (w * _AA, h * _AA), 0)
    ImageDraw.Draw(mask).polygon(
        [((x - x0) * _AA, (y - y0) * _AA) for x, y in zip(xs, ys)], fill=255)
    fill = Image.new("RGB", (w, h), (hex_rgb if true_color else quantize565)(color))
    img.paste(fill, (x0, y0), mask.resize((w, h), Image.BOX))


def draw_arrow(
    img: Image.Image,
    draw: ImageDraw.ImageDraw,
    a,  # gen.trend.Arrow — ไม่ import เพื่อไม่ให้ตัววาดรู้จักกติกาของหน้า watchlist
    px: float,
    ox: float,
    oy: float,
) -> None:
    """ลูกศรหนึ่งใบ — ทิศทางเป็นสามเหลี่ยมขอบนุ่ม นิ่งเป็นขีด (ดู `trend.arrow`)

    ตัวคู่ขนานฝั่ง C คือ arrow_draw_cb ใน ct_crypto_ui.c / ct_stocks_ui.c
    """
    if a.tri is not None:
        draw_poly(img, a.tri, px, ox, oy, a.color)
    else:
        draw_rects(draw, a.bar, px, ox, oy)


def render_rects(
    rects: RectList,
    px: float,
    box: tuple[float, float, float, float],
    bg: str,
    true_color: bool = False,
) -> Image.Image:
    x0, y0, x1, y1 = box
    w = max(round((x1 - x0) * px), 1)
    h = max(round((y1 - y0) * px), 1)
    img = Image.new("RGB", (w, h), quantize565(bg) if not true_color else hex_rgb(bg))
    draw_rects(ImageDraw.Draw(img), rects, px, -x0 * px, -y0 * px, true_color)
    return img
