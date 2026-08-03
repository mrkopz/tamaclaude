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
        """วาดโดย (x, y) คือมุมซ้ายบนของบรรทัด — เหมือน lv_label ที่มุมซ้ายบน"""
        base = y + self.ascent
        pen = x
        for ch in text:
            key = f"{ord(ch):04X}"
            g = self.glyph(ord(ch))
            if g is None:
                continue
            if g["w"] and g["h"]:
                gx = round(pen) + g["ofs_x"]
                gy = round(base) - g["ofs_y"] - g["h"]
                draw.bitmap((gx, gy), self._mask(key, g), fill=color)
            pen += g["adv"]


@lru_cache(maxsize=None)
def font(size: int) -> BitmapFont:
    path = FONT_DIR / f"thai-{size}.json"
    return BitmapFont(json.loads(path.read_text(encoding="utf-8")))
