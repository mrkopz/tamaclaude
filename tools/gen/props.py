"""Prop — ของที่มาสคอตถือหรือลอยเหนือหัว บอกว่ากำลังทำอะไร

พิกัดอยู่ในตารางเดียวกับมาสคอต ซิลลูเอ็ตกิน x -0.5..16.5, y 0..11.2 (ฝ่าเท้าที่ y=11.2)
  prop ถือ  อยู่ช่วง x 17.2..23.4 — นอกลำตัว ไม่ทับตา ไม่ทับขา
  prop ลอย  อยู่ช่วง y -5.6..-0.1 เหนือหัว
"""

from __future__ import annotations

import math
from collections.abc import Callable

from .config import PAL
from .rects import Rect, RectList

# กรอบวาดจริงรวม prop — 23.9 x 16.8 unit = 95.6 x 67.2 px ที่ unit_px=4
# เล็กกว่า slot 106px อยู่ ~5px ต่อข้าง ทำให้ prop ไม่ล้ำไปพื้นหลังของ slot ข้างๆ
BOX_X0, BOX_X1 = -0.5, 23.4
BOX_Y0, BOX_Y1 = -5.6, 11.2

HEAD_CX = 8.0  # กึ่งกลางลำตัวในแนวนอน
HAND_X = 17.2  # ขอบซ้ายของพื้นที่ prop ที่ถือ (แขนจบที่ 16.5 เว้นช่องหายใจ 0.7)
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
    x = HAND_X + math.sin(phase * math.pi * 2.0) * 0.35
    y, s, t = HAND_Y, 4.5, 0.8
    out = _ring(x, y, s, t, col)  # เลนส์ปล่อยโปร่ง — ถ้าถมสีจะเพี้ยนเวลาพื้นหลังเปลี่ยน
    for i in range(2):  # ด้ามจับทแยงลงขวา
        out.append(Rect(x + s - 0.3 + i * 0.65, y + s - 0.3 + i * 0.65, 0.9, 0.9, col))
    return out


def pencil(phase: float, connected: bool = True) -> RectList:
    """ดินสอ — Edit/Write  (ขยับเป็นจังหวะเขียน)"""
    col = _c(connected, PAL.accent)
    tip = _c(connected, PAL.text)
    wob = math.sin(phase * math.pi * 4.0) * 0.4
    x, y = HAND_X, HAND_Y + wob
    out = [Rect(x + 3.5 - i * 0.95, y + i * 1.02, 1.6, 1.25, col) for i in range(4)]
    out.append(Rect(x - 0.1, y + 4.06, 1.4, 1.4, tip))  # ปลายไส้
    return out


def hammer(phase: float, connected: bool = True) -> RectList:
    """ค้อน — Bash  (ทุบเป็นจังหวะ มีประกายตอนกระแทก)"""
    col = _c(connected, PAL.accent)
    head = _c(connected, PAL.text_dim)
    down = phase % 0.5 < 0.25
    x = HAND_X + 0.3
    y = HAND_Y + (2.0 if down else 0.0)
    out = [Rect(x + 1.7, y + 1.8, 1.3, 3.4, col)]  # ด้าม
    out.append(Rect(x, y, 4.8, 2.0, head))  # หัวค้อน
    if down:
        out.append(Rect(x - 0.9, y + 4.4, 1.0, 1.0, PAL.accent))
        out.append(Rect(x + 4.7, y + 4.4, 1.0, 1.0, PAL.accent))
    return out


def globe(phase: float, connected: bool = True) -> RectList:
    """ลูกโลก — WebSearch/WebFetch

    ทรงกลมตัน ไม่ใช่สี่เหลี่ยมกลวง เพราะจะไปซ้ำกับแว่นขยายจนแยกไม่ออกที่ 12px
    ทวีปสีเข้มเลื่อนไปทางเดียวกันตลอด อ่านเป็น "กำลังหมุน"
    """
    col = _c(connected, PAL.accent)
    dark = _c(connected, PAL.ink)
    x, y, s = HAND_X, HAND_Y, 5.0
    c = s / 6.0  # ความลึกของมุมที่ตัดออก ทำให้อ่านเป็นทรงกลม
    out = [
        Rect(x + c, y, s - 2 * c, c, col),
        Rect(x, y + c, s, s - 2 * c, col),
        Rect(x + c, y + s - c, s - 2 * c, c, col),
    ]
    spin = (phase % 1.0) * s
    for dx, dy, w, h in ((0.0, 1.4, 1.2, 1.0), (2.3, 2.9, 1.5, 0.9)):
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
        s = 2.2 if i == lit else 1.4
        cx = HEAD_CX + (i - 1) * 3.4
        cy = -2.7 - (0.5 if i == lit else 0.0)
        out.append(Rect(cx - s / 2, cy - s / 2, s, s, col))
    return out


def bang(phase: float, connected: bool = True) -> RectList:
    """อัศเจรีย์แดง — alert (พัง/ต้องดูด่วน)"""
    col = _c(connected, PAL.alert)
    pulse = 0.4 * (0.5 + 0.5 * math.sin(phase * math.pi * 4.0))
    x, y = HEAD_CX - 0.95, -5.1 - pulse
    return [Rect(x, y, 1.9, 3.0, col), Rect(x, y + 3.8, 1.9, 1.3, col)]


def query(phase: float, connected: bool = True) -> RectList:
    """เครื่องหมายคำถามเหลือง — waiting (Claude ขออนุญาต/รอคำตอบ)

    ต้องแยกจาก bang ให้ขาด: "รอคุณ" ไม่ใช่ "พัง" — ต่างทั้งรูปทรงและสี
    """
    col = _c(connected, PAL.accent)
    u = 0.74
    pulse = 0.35 * (0.5 + 0.5 * math.sin(phase * math.pi * 2.0))
    x, y = HEAD_CX - 2 * u, -5.2 - pulse
    cells = ((1, 0), (2, 0), (0, 1), (3, 1), (3, 2), (2, 3), (2, 4), (2, 6))
    return [Rect(x + cx * u, y + cy * u, u, u, col) for cx, cy in cells]


def zzz(phase: float, connected: bool = True) -> RectList:
    """Zzz — sleeping  (ลอยขึ้นทแยงจากมุมบนขวาของหัว)"""
    col = _c(connected, PAL.text_dim)
    out: RectList = []
    for i in range(3):
        t = (phase + i / 3.0) % 1.0
        s = 1.0 + i * 0.55
        out.append(Rect(12.4 + i * 2.0 + t * 1.0, -1.1 - i * 1.5 - t * 1.3, s, s, col))
    return out


def sparkle(phase: float, connected: bool = True) -> RectList:
    """ประกาย — celebrate  (กระพริบสลับรอบตัว)"""
    col = _c(connected, PAL.accent)
    spots = ((1.6, -2.6), (14.4, -2.0), (HEAD_CX, -4.0), (1.2, 2.5), (18.6, 5.2))
    out: RectList = []
    for i, (x, y) in enumerate(spots):
        if (int(phase * 4.0) + i) % 2:
            continue
        out += [Rect(x - 0.45, y - 1.5, 0.9, 3.0, col), Rect(x - 1.5, y - 0.45, 3.0, 0.9, col)]
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
        x = HEAD_CX + (i * 2 - 1) * 4.0 - 1.7
        y = -4.8 + bob
        out.append(Rect(x, y, 3.4, 2.4, body))  # ลำตัว
        out.append(Rect(x - 0.5, y + 0.7, 0.5, 0.9, body))  # แขนซ้าย
        out.append(Rect(x + 3.4, y + 0.7, 0.5, 0.9, body))  # แขนขวา
        out.append(Rect(x + 0.35, y + 2.4, 0.8, 0.9, body))  # ขาซ้าย
        out.append(Rect(x + 2.25, y + 2.4, 0.8, 0.9, body))  # ขาขวา
        out.append(Rect(x + 0.6, y + 0.7, 0.8, 0.8, ink))  # ตา
        out.append(Rect(x + 2.0, y + 0.7, 0.8, 0.8, ink))
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
        Rect(cx - 0.5, HAND_Y + 1.4, 1.0, 3.8, post),  # เสา
        Rect(cx - 1.8, HAND_Y + 5.2, 3.6, 0.9, post),  # ฐาน
        Rect(cx - 0.9, HAND_Y, 1.8, 1.4, col),  # ไฟยอดเสา
    ]
    for i in range(2):
        t = (phase + i * 0.5) % 1.0
        if t > 0.8:  # ดับก่อนถึงขอบ อ่านเป็นคลื่นจางหาย ไม่ใช่คลื่นโดนตัด
            continue
        spread = 1.0 + t * 1.4  # กว้างสุด 2.4 — พอดีขอบ BOX_X1 ไม่ล้ำ slot ข้างๆ
        rise = t * 0.7
        out.append(Rect(cx - spread - 0.7, HAND_Y - rise, 0.7, 1.9, col))
        out.append(Rect(cx + spread, HAND_Y - rise, 0.7, 1.9, col))
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
