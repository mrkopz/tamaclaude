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
        draw.rectangle([x0, y0, x1 - 1, y1 - 1], fill=conv(r.color))


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
