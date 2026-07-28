"""Rect list — รูปแบบ asset เดียวของโปรเจกต์

มาสคอตและ prop ทุกชิ้นคือรายการสี่เหลี่ยมในพิกัด "unit" ไม่ใช่พิกเซล
firmware วาดด้วย lv_draw_rect ตอน runtime จึงย่อขยายได้อิสระ
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class Rect:
    x: float
    y: float
    w: float
    h: float
    color: str

    def moved(self, dx: float, dy: float) -> "Rect":
        return Rect(self.x + dx, self.y + dy, self.w, self.h, self.color)

    def recolored(self, color: str) -> "Rect":
        return Rect(self.x, self.y, self.w, self.h, color)


RectList = list[Rect]


def move(rects: RectList, dx: float, dy: float) -> RectList:
    return [r.moved(dx, dy) for r in rects]


def recolor(rects: RectList, color: str) -> RectList:
    return [r.recolored(color) for r in rects]


def mirror_x(rects: RectList, axis: float) -> RectList:
    """สะท้อนซ้าย-ขวารอบแกน x = axis"""
    return [Rect(2 * axis - r.x - r.w, r.y, r.w, r.h, r.color) for r in rects]


def scaled(rects: RectList, sx: float, sy: float, ox: float = 0.0, oy: float = 0.0) -> RectList:
    """ย่อ/ขยายรอบจุด (ox, oy)"""
    return [
        Rect(ox + (r.x - ox) * sx, oy + (r.y - oy) * sy, r.w * sx, r.h * sy, r.color)
        for r in rects
    ]


def bounds(rects: RectList) -> tuple[float, float, float, float]:
    xs0 = min(r.x for r in rects)
    ys0 = min(r.y for r in rects)
    xs1 = max(r.x + r.w for r in rects)
    ys1 = max(r.y + r.h for r in rects)
    return xs0, ys0, xs1, ys1
