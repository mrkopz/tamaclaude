"""หน้าอากาศทั้งใบ — พอร์ตคู่กับ firmware/main/ct_weather_ui.c

ค่าคงที่ทั้งหมดมาจาก layout.toml ชุดเดียวกับ firmware ถ้าภาพที่นี่ต่างจากบนบอร์ด
แปลว่าเป็นบั๊ก renderer ไม่ใช่ค่าคงที่ไม่ตรงกัน
"""

from __future__ import annotations

from dataclasses import dataclass

from PIL import Image, ImageDraw

from . import age, mascot, screen
from .config import L, PAL
from .props import BOX_X0, BOX_X1, BOX_Y1
from .rects import Rect, RectList, scaled
from .render import draw_rects, quantize565

def bucket(code: int) -> str:
    """รหัส WMO -> กลุ่มสัญลักษณ์ — ต้องตรงกับ bucket() ใน ct_weather_ui.c

    รหัสมีหลายสิบค่า แต่จอ 2.8 นิ้วที่มองจากอีกฝั่งห้องแยกได้จริงราวหกกลุ่ม
    หมอกกับหมอกน้ำแข็งคนละรูปคือรายละเอียดที่ไม่มีใครอ่านออก
    """
    if code >= 95:
        return "storm"
    if 71 <= code <= 77 or code in (85, 86):
        return "snow"
    if 51 <= code <= 67 or 80 <= code <= 82:
        return "rain"
    if code in (45, 48):
        return "fog"
    if code >= 2:
        return "cloud"
    return "clear"


def _cloud(color: str) -> RectList:
    return [
        Rect(1.0, 3.6, 8.0, 2.8, color, 1.4),
        Rect(2.4, 2.0, 3.4, 3.0, color, 1.5),
        Rect(5.0, 2.6, 3.0, 2.6, color, 1.3),
    ]


def icon(code: int, connected: bool = True) -> RectList:
    """สัญลักษณ์สภาพอากาศหนึ่งชุด — ต้องตรงกับ build_icon() ใน ct_weather_ui.c"""
    # หลุดลิงก์แล้วสัญลักษณ์เป็นเทา เหมือนมาสคอตที่หลุด — ตัวเลขที่ค้างอยู่ยังอ่านได้
    # แต่ต้องไม่อ่านว่าเป็นตอนนี้
    cloud = PAL.cloud_day if connected else PAL.gray
    sun = PAL.sun if connected else PAL.gray
    wet = PAL.steel if connected else PAL.gray_dark
    bolt = PAL.accent if connected else PAL.gray_dark
    flake = PAL.text if connected else PAL.gray_dark

    kind = bucket(code)
    if kind == "clear":
        # ดวงกลมกับรังสีสี่ทิศ — ไม่ใช่แปดทิศ เพราะที่ 50px รังสีทแยงกลืนกับดวง
        return [
            Rect(2.5, 2.5, 5.0, 5.0, sun, 2.5),
            Rect(4.6, 0.2, 0.8, 1.6, sun),
            Rect(4.6, 8.2, 0.8, 1.6, sun),
            Rect(0.2, 4.6, 1.6, 0.8, sun),
            Rect(8.2, 4.6, 1.6, 0.8, sun),
        ]
    if kind == "cloud":
        # เมฆบังดวงบางส่วน — เมฆล้วนแยกไม่ออกจากหมอกที่ระยะโต๊ะ
        return [Rect(5.6, 0.2, 3.6, 3.6, sun, 1.8)] + _cloud(cloud)
    if kind == "fog":
        # สามขีดนอน ไม่มีเมฆ — หมอกคือสิ่งที่ *ไม่* มีรูปร่าง
        return [Rect(1.0 + (i % 2) * 0.8, 2.6 + i * 2.2, 7.4, 1.0, cloud, 0.5) for i in range(3)]
    if kind == "rain":
        return _cloud(cloud) + [
            Rect(2.2 + i * 2.4, 7.0, 0.9, 2.4, wet, 0.45) for i in range(3)
        ]
    if kind == "snow":
        return _cloud(cloud) + [
            Rect(2.2 + i * 2.4, 7.4, 1.4, 1.4, flake, 0.7) for i in range(3)
        ]
    # storm — สายฟ้าเป็นสองชิ้นเยื้องกัน ชิ้นเดียวอ่านเป็นเสาไฟ
    return _cloud(cloud) + [
        Rect(4.6, 6.8, 1.6, 1.8, bolt),
        Rect(3.8, 8.0, 1.6, 1.8, bolt),
    ]


@dataclass(slots=True)
class Weather:
    """หน้าอากาศหนึ่งใบ — `place` ว่างและ `has_frame=False` คือยังไม่เคยได้ข้อมูลเลย"""

    place: str = "Bangkok"
    temp: int = 31
    high: int = 34
    low: int = 26
    code: int = 61
    unit: str = "C"
    age: int = 420
    # มี snapshot สดอยู่ไหม — ตรงกับ ct_weather_ui_set_connected
    connected: bool = True
    # เคยได้ page frame ของหน้านี้แล้วหรือยัง (ADR-0002)
    has_frame: bool = True
    # ท่าของมาสคอตจิ๋วมุมจอ — None = ไม่มี session เลย ซึ่งคือท่าหลับ
    mascot_state: str | None = None


def _mini_mascot(draw: ImageDraw.ImageDraw, w: Weather, phase: float, cycle: int) -> None:
    """rect list ชุดเดิมที่ย่อลง ไม่มีอาร์ตใหม่ ไม่มีท้องฟ้า ไม่มี prop ที่ต้องเว้นที่ให้

    อายุขั้นต่ำของ pose ถูกบังคับที่ daemon อยู่แล้ว (Timings.minPose) ที่นี่จึงวาดสิ่งที่
    snapshot บอกตรงๆ และได้กติกาเดียวกันมาฟรี
    """
    # ไม่มี Mac = ไม่มีมาสคอต ซึ่งต่างจากมาสคอตที่หลับ (= ไม่มี session)
    if not w.connected:
        return
    px = L.slots.unit_px
    scale = L.weather.mini_unit_px / px
    rects = scaled(mascot.build_centered(w.mascot_state or "sleeping", phase, True, cycle),
                   scale, scale)
    # ปัดเป็นจำนวนเต็มแบบเดียวกับฝั่งบอร์ด (lv_obj_set_size กินพิกเซลเต็มเท่านั้น)
    # ปล่อยให้ที่นี่เป็นทศนิยมแล้วมาสคอตจะเยื้องจากบนจอจริงหนึ่งพิกเซล
    mini_w = int((BOX_X1 - BOX_X0) * L.weather.mini_unit_px) + 1
    ox = L.screen.width - L.weather.mini_right - mini_w - BOX_X0 * scale * px
    oy = L.weather.mini_bottom_y - BOX_Y1 * scale * px
    draw_rects(draw, rects, px, ox, oy)


def render(w: Weather, phase: float = 0.0, cycle: int = 0) -> Image.Image:
    img = Image.new("RGB", (L.screen.width, L.screen.height), quantize565(PAL.bg))
    draw = ImageDraw.Draw(img)

    icon_x, icon_y = L.weather.icon_x, L.weather.icon_y
    draw_rects(draw, icon(w.code if w.has_frame else 3, w.has_frame and w.connected),
               L.weather.icon_px, icon_x, icon_y)
    _mini_mascot(draw, w, phase, cycle)

    if not w.has_frame:
        # ยังไม่เคยได้ข้อมูลของหน้านี้ ต้องมีหน้าตาของตัวเอง ห้ามเป็นจอเปล่า (ADR-0002)
        screen.line(draw, (L.weather.temp_x, L.weather.empty_y + 7), "No weather yet",
                    pil=12, board=14, fill=PAL.text, anchor="lm")
        screen.line(draw, (L.weather.temp_x, L.weather.empty_sub_y + 6),
                    "the mac has not sent this page", pil=10, board=12,
                    fill=PAL.text_dim, anchor="lm")
        return img

    screen.line(draw, (L.weather.place_x, L.weather.place_y + 7), w.place,
                 pil=12, board=14, fill=PAL.text, anchor="lm",
                 max_w=icon_x - L.weather.place_x - 8)
    # ไม่มีสัญลักษณ์องศาในฟอนต์บนบอร์ด และการประดิษฐ์วงแหวนจาก rect ขึ้นมาเองเพื่อสิ่งที่
    # ไม่มีใครอ่านผิดคือค่าใช้จ่ายที่ไม่คุ้ม — "31C" อ่านออกทันที
    draw.text((L.weather.temp_x, L.weather.temp_y + 24), f"{w.temp}{w.unit}",
              font=screen.font(L.weather.temp_font_pil),
              fill=quantize565(PAL.text if w.connected else PAL.gray), anchor="lm")
    screen.line(draw, (L.weather.hilo_x, L.weather.hilo_y + 7),
                 f"H {w.high}   L {w.low}", pil=12, board=14, fill=PAL.text_dim, anchor="lm")

    age.draw_age(draw, w.age, L.weather.refresh_s)
    return img
