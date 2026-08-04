"""วาดข้อความด้วยฟอนต์บิตแมปตัวเดียวกับที่แฟลชลงบอร์ด

ADR-0008: ถ้า preview วาดไทยด้วย TTF ต้นฉบับ เอนจินของ PIL จะจัดวางสวยกว่าบอร์ดจริง
แล้วพรีวิวจะกลายเป็นคำโกหกตรงจุดที่ต้องใช้ตัดสินใจ ไฟล์นี้จึงอ่านบิตแมปชุดเดียวกับที่
tools/export_thai_font.py ปล่อยลง firmware แล้ววาดแบบเดียวกับ LVGL — เรียงไปทางขวา
ทีละ codepoint ตาม adv_w ไม่มีการจัดวางเพิ่มเติมใดๆ ทั้งสิ้น
"""

from __future__ import annotations

import base64
import json
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw

FONT_DIR = Path(__file__).resolve().parent.parent / "fonts"


class BitmapFont:
    def __init__(self, data: dict) -> None:
        self.size: int = data["size"]
        self.line_height: int = data["line_height"]
        self.base_line: int = data["base_line"]
        self.ascent = self.line_height - self.base_line
        # ที่ว่างเหนือตัวละตินที่กันไว้ให้วรรณยุกต์ไทย — เลย์เอาต์วางป้ายด้วยขอบบนของ
        # ตัวละติน กล่องบรรทัดจึงเริ่มสูงกว่านั้นขึ้นไปเท่านี้ (ct_font_rise ฝั่ง C)
        self.rise = self.ascent - data["host_ascent"]
        self._glyphs = data["glyphs"]
        self._cache: dict[str, Image.Image] = {}

    def glyph(self, cp: int) -> dict | None:
        return self._glyphs.get(f"{cp:04X}")

    def _mask(self, key: str, g: dict) -> Image.Image:
        """สตรีม 4 บิตต่อพิกเซล -> ภาพ L ที่ PIL วางทับได้"""
        m = self._cache.get(key)
        if m is not None:
            return m
        bits = base64.b64decode(g["bits"])
        px = bytearray()
        for b in bits:
            px.append((b >> 4) * 17)
            px.append((b & 0xF) * 17)
        del px[g["w"] * g["h"]:]
        m = Image.frombytes("L", (g["w"], g["h"]), bytes(px))
        self._cache[key] = m
        return m

    def length(self, text: str) -> float:
        return sum(g["adv"] for ch in text if (g := self.glyph(ord(ch))))

    def draw(self, draw: ImageDraw.ImageDraw, x: float, y: float, text: str,
             color: tuple[int, int, int]) -> None:
        """วาดโดย (x, y) คือมุมซ้ายบนของบรรทัด — เหมือน lv_label ที่มุมซ้ายบน

        **หนีบที่ขอบบนล่างของบรรทัดเหมือน LVGL** — `lv_label.c:818` ตัดพื้นที่วาดด้วยกรอบ
        ของ label แล้ว `lv_draw_label.c:409` ทิ้ง glyph ที่พ้นกรอบ ตอนที่ไฟล์นี้ยังไม่หนีบ
        สระล่างที่ไม่มีที่อยู่จะ *ล้น* ทับการ์ดใบถัดไปในพรีวิว แต่ *หายทั้งตัว* บนบอร์ด —
        บั๊กเดียวให้ภาพคนละแบบ แล้วลูป "เรนเดอร์ แล้วดู out/" ก็มองไม่เห็นสิ่งที่จะเกิดจริง
        """
        base = y + self.ascent
        top, bot = round(y), round(y) + self.line_height
        pen = x
        for ch in text:
            key = f"{ord(ch):04X}"
            g = self.glyph(ord(ch))
            if g is None:
                continue
            if g["w"] and g["h"]:
                gx = round(pen) + g["ofs_x"]
                gy = round(base) - g["ofs_y"] - g["h"]
                y0, y1 = max(gy, top), min(gy + g["h"], bot)
                if y1 > y0:
                    mask = self._mask(key, g)
                    if (y0, y1) != (gy, gy + g["h"]):
                        mask = mask.crop((0, y0 - gy, g["w"], y1 - gy))
                    draw.bitmap((gx, y0), mask, fill=color)
            pen += g["adv"]


@lru_cache(maxsize=None)
def font(size: int) -> BitmapFont:
    path = FONT_DIR / f"thai-{size}.json"
    return BitmapFont(json.loads(path.read_text(encoding="utf-8")))
