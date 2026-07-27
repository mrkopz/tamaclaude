"""Prop — ของที่มาสคอตถือหรือลอยเหนือหัว บอกว่ากำลังทำอะไร

พิกัดอยู่ในตารางเดียวกับมาสคอต ซิลลูเอ็ตกิน x 0..16, y 0..11.2 (ฝ่าเท้าที่ y=11.2)
  prop ถือ  อยู่ช่วง x 16.6..22  — นอกลำตัว ไม่ทับตา ไม่ทับขา
  prop ลอย  อยู่ช่วง y -5.4..-0.5 เหนือหัว
"""

from __future__ import annotations

import math
from collections.abc import Callable

from .config import PAL
from .rects import Rect, RectList

# กรอบวาดจริงรวม prop — 22.5 x 16.8 unit = 67.5 x 50.4 px ที่ unit_px=3
# เล็กกว่า slot 80px อยู่ ~6px ต่อข้าง ทำให้ prop ไม่ล้ำไปพื้นหลังของ slot ข้างๆ
BOX_X0, BOX_X1 = -0.5, 22.0
BOX_Y0, BOX_Y1 = -5.6, 11.2

HEAD_CX = 8.0  # กึ่งกลางลำตัวในแนวนอน
HAND_X = 16.6  # ขอบซ้ายของพื้นที่ prop ที่ถือ
HAND_Y = 2.4


def _c(connected: bool, color: str) -> str:
    return color if connected else PAL.gray_dark


def _ring(x: float, y: float, s: float, t: float, color: str) -> RectList:
    """สี่เหลี่ยมกลวง หนา t"""
    return [
        Rect(x, y, s, t, color),
        Rect(x, y + s - t, s, t, color),
        Rect(x, y + t, t, s - 2 * t, color),
        Rect(x + s - t, y + t, t, s - 2 * t, color),
    ]


def magnifier(phase: float, connected: bool = True) -> RectList:
    """แว่นขยาย — Read/Grep/Glob  (ส่ายซ้ายขวาเหมือนกำลังไล่อ่าน)"""
    col = _c(connected, PAL.accent)
    x = HAND_X + math.sin(phase * math.pi * 2.0) * 0.45
    y, s, t = HAND_Y, 4.0, 0.7
    out = _ring(x, y, s, t, col)  # เลนส์ปล่อยโปร่ง — ถ้าถมสีจะเพี้ยนเวลาพื้นหลังเปลี่ยน
    for i in range(2):  # ด้ามจับทแยงลงขวา
        out.append(Rect(x + s - 0.25 + i * 0.7, y + s - 0.25 + i * 0.7, 0.9, 0.9, col))
    return out


def pencil(phase: float, connected: bool = True) -> RectList:
    """ดินสอ — Edit/Write  (ขยับเป็นจังหวะเขียน)"""
    col = _c(connected, PAL.accent)
    tip = _c(connected, PAL.text)
    wob = math.sin(phase * math.pi * 4.0) * 0.4
    x, y = HAND_X, HAND_Y + wob
    out = [Rect(x + 2.9 - i * 0.78, y + i * 0.86, 1.3, 1.05, col) for i in range(4)]
    out.append(Rect(x - 0.1, y + 3.44, 1.15, 1.15, tip))  # ปลายไส้
    return out


def hammer(phase: float, connected: bool = True) -> RectList:
    """ค้อน — Bash  (ทุบเป็นจังหวะ มีประกายตอนกระแทก)"""
    col = _c(connected, PAL.accent)
    head = _c(connected, PAL.text_dim)
    down = phase % 0.5 < 0.25
    x = HAND_X + 0.3
    y = HAND_Y + (2.2 if down else 0.0)
    out = [Rect(x + 1.4, y + 1.2, 1.0, 2.9, col)]  # ด้าม
    out.append(Rect(x, y, 3.8, 1.4, head))  # หัวค้อน
    if down:
        out.append(Rect(x - 0.8, y + 4.3, 0.8, 0.8, PAL.accent))
        out.append(Rect(x + 3.8, y + 4.3, 0.8, 0.8, PAL.accent))
    return out


def globe(phase: float, connected: bool = True) -> RectList:
    """ลูกโลก — WebSearch/WebFetch

    ทรงกลมตัน ไม่ใช่สี่เหลี่ยมกลวง เพราะจะไปซ้ำกับแว่นขยายจนแยกไม่ออกที่ 12px
    ทวีปสีเข้มเลื่อนไปทางเดียวกันตลอด อ่านเป็น "กำลังหมุน"
    """
    col = _c(connected, PAL.accent)
    dark = _c(connected, PAL.ink)
    x, y, s = HAND_X, HAND_Y, 4.2
    c = s / 6.0  # ความลึกของมุมที่ตัดออก ทำให้อ่านเป็นทรงกลม
    out = [
        Rect(x + c, y, s - 2 * c, c, col),
        Rect(x, y + c, s, s - 2 * c, col),
        Rect(x + c, y + s - c, s - 2 * c, c, col),
    ]
    spin = (phase % 1.0) * s
    for dx, dy, w, h in ((0.0, 1.2, 1.0, 0.8), (1.9, 2.4, 1.3, 0.7)):
        px = x + (dx + spin) % s
        if px + w <= x + s:  # ตัดชิ้นที่จะล้นขอบลูกโลกทิ้ง แทนที่จะให้ยื่นออกมา
            out.append(Rect(px, y + dy, w, h, dark))
    return out


def dots(phase: float, connected: bool = True) -> RectList:
    """จุดคิด — thinking  (ไล่สว่างทีละจุด)"""
    col = _c(connected, PAL.text)
    lit = int(phase * 3.0) % 3
    out: RectList = []
    for i in range(3):
        s = 1.7 if i == lit else 1.05
        cx = HEAD_CX + (i - 1) * 2.8
        cy = -2.5 - (0.5 if i == lit else 0.0)
        out.append(Rect(cx - s / 2, cy - s / 2, s, s, col))
    return out


def bang(phase: float, connected: bool = True) -> RectList:
    """อัศเจรีย์แดง — alert (พัง/ต้องดูด่วน)"""
    col = _c(connected, PAL.alert)
    pulse = 0.4 * (0.5 + 0.5 * math.sin(phase * math.pi * 4.0))
    x, y = HEAD_CX - 0.75, -4.7 - pulse
    return [Rect(x, y, 1.5, 2.6, col), Rect(x, y + 3.3, 1.5, 1.2, col)]


def query(phase: float, connected: bool = True) -> RectList:
    """เครื่องหมายคำถามเหลือง — waiting (Claude ขออนุญาต/รอคำตอบ)

    ต้องแยกจาก bang ให้ขาด: "รอคุณ" ไม่ใช่ "พัง" — ต่างทั้งรูปทรงและสี
    """
    col = _c(connected, PAL.accent)
    u = 0.62
    pulse = 0.35 * (0.5 + 0.5 * math.sin(phase * math.pi * 2.0))
    x, y = HEAD_CX - 2 * u, -4.9 - pulse
    cells = ((1, 0), (2, 0), (0, 1), (3, 1), (3, 2), (2, 3), (2, 4), (2, 6))
    return [Rect(x + cx * u, y + cy * u, u, u, col) for cx, cy in cells]


def zzz(phase: float, connected: bool = True) -> RectList:
    """Zzz — sleeping  (ลอยขึ้นทแยงจากมุมบนขวาของหัว)"""
    col = _c(connected, PAL.text_dim)
    out: RectList = []
    for i in range(3):
        t = (phase + i / 3.0) % 1.0
        s = 0.7 + i * 0.4
        out.append(Rect(12.0 + i * 1.8 + t * 0.9, -0.7 - i * 1.3 - t * 1.2, s, s, col))
    return out


def sparkle(phase: float, connected: bool = True) -> RectList:
    """ประกาย — celebrate  (กระพริบสลับรอบตัว)"""
    col = _c(connected, PAL.accent)
    spots = ((1.6, -2.3), (14.0, -1.8), (HEAD_CX, -3.9), (0.1, 2.5), (17.5, 5.0))
    out: RectList = []
    for i, (x, y) in enumerate(spots):
        if (int(phase * 4.0) + i) % 2:
            continue
        out += [Rect(x - 0.4, y - 1.2, 0.8, 2.4, col), Rect(x - 1.2, y - 0.4, 2.4, 0.8, col)]
    return out


def crew(phase: float, connected: bool = True) -> RectList:
    """มาสคอตจิ๋วสองตัวลอยเหนือหัว — conducting (มี subagent กำลังทำงานให้)

    เป็นรูปย่อของมาสคอตเอง ไม่ใช่สัญลักษณ์นามธรรม: สารที่ต้องสื่อคือ "มีอีกหลายตัว
    ทำงานอยู่" ซึ่งอ่านออกทันทีเมื่อของที่ลอยอยู่หน้าตาเหมือนตัวที่ยืนอยู่ข้างล่าง
    กระเด้งคนละเฟส (ห่างกันครึ่งลูป) จึงไม่อ่านเป็นก้อนเดียวที่ขยับพร้อมกัน
    """
    body = _c(connected, PAL.clay)
    ink = _c(connected, PAL.ink)
    out: RectList = []
    for i in range(2):
        bob = math.sin(phase * math.pi * 2.0 + i * math.pi) * 0.5
        x = HEAD_CX + (i * 2 - 1) * 3.5 - 1.5
        y = -4.4 + bob
        out.append(Rect(x, y, 3.0, 2.2, body))  # ลำตัว
        out.append(Rect(x + 0.3, y + 2.2, 0.7, 0.8, body))  # ขาซ้าย
        out.append(Rect(x + 2.0, y + 2.2, 0.7, 0.8, body))  # ขาขวา
        out.append(Rect(x + 0.55, y + 0.6, 0.75, 0.75, ink))  # ตา
        out.append(Rect(x + 1.7, y + 0.6, 0.75, 0.75, ink))
    return out


def beacon(phase: float, connected: bool = True) -> RectList:
    """เสาสัญญาณ — LSP/MCP  (คลื่นแผ่ออกสองข้างเป็นจังหวะ)

    "คุยกับบริการอื่นอยู่" ไม่ใช่ "ค้นหา" จึงไม่ใช้ลูกโลกซ้ำ อ่านออกที่ 3 px/unit
    เพราะทุกชิ้นตั้งฉาก: เสาตรง ฐานแบน คลื่นเป็นแท่งตั้งที่ถอยห่างออกไป
    คลื่นสองชุดเดินห่างกันครึ่งลูป จึงไม่อ่านเป็นก้อนเดียวที่ขยับพร้อมกัน
    """
    col = _c(connected, PAL.accent)
    post = _c(connected, PAL.text_dim)
    cx = (HAND_X + BOX_X1) / 2.0  # กึ่งกลางพื้นที่ prop — คลื่นแผ่ได้เท่ากันสองข้าง
    out = [
        Rect(cx - 0.4, HAND_Y + 1.2, 0.8, 3.6, post),  # เสา
        Rect(cx - 1.5, HAND_Y + 4.8, 3.0, 0.8, post),  # ฐาน
        Rect(cx - 0.7, HAND_Y, 1.4, 1.2, col),  # ไฟยอดเสา
    ]
    for i in range(2):
        t = (phase + i * 0.5) % 1.0
        if t > 0.8:  # ดับก่อนถึงขอบ อ่านเป็นคลื่นจางหาย ไม่ใช่คลื่นโดนตัด
            continue
        spread = 0.8 + t * 1.2  # กว้างสุด 2.0 — พอดีขอบ BOX_X1 ไม่ล้ำ slot ข้างๆ
        rise = t * 0.6
        out.append(Rect(cx - spread - 0.6, HAND_Y - rise, 0.6, 1.6, col))
        out.append(Rect(cx + spread, HAND_Y - rise, 0.6, 1.6, col))
    return out


PROPS: dict[str, Callable[[float, bool], RectList]] = {
    "magnifier": magnifier,
    "pencil": pencil,
    "hammer": hammer,
    "globe": globe,
    "dots": dots,
    "bang": bang,
    "query": query,
    "zzz": zzz,
    "sparkle": sparkle,
    "crew": crew,
    "beacon": beacon,
}
