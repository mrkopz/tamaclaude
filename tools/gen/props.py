"""Prop — ของที่มาสคอตถือหรือลอยเหนือหัว บอกว่ากำลังทำอะไร

พิกัดอยู่ในตารางเดียวกับมาสคอต ซิลลูเอ็ตกิน x -0.5..16.5, y 0..11.2 (ฝ่าเท้าที่ y=11.2)
  prop ถือ  อยู่ช่วง x 17.2..23.4 — นอกลำตัว ไม่ทับตา ไม่ทับขา
  prop ลอย  อยู่ช่วง y -5.6..-0.1 เหนือหัว
  ยกเว้นแว่นขยาย ที่ตั้งใจให้ทับตาข้างขวา (ท่ายกส่อง) — เลนส์กลวงจึงยังเห็นตา
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

# ตาข้างขวา — อยู่ที่นี่เพราะ prop บางชิ้น (แว่นขยาย) ต้องเล็งไปที่ตา
# mascot.py import ไปใช้ต่อ จึงมีค่าชุดเดียวไม่ต้องซิงก์สองที่
EYE_R, EYE_Y, EYE_S = 10.64, 2.10, 2.0
# ตาที่อยู่หลังเลนส์ต้องโตกว่าอีกข้าง ไม่งั้นวงแหวนอ่านเป็นแค่ห่วงคล้องหน้า ไม่ใช่แว่นขยาย
# mascot.py เป็นคนวาดตาที่ขยายแล้ว (มันรู้ว่าตากำลังเป็นท่าไหน เช่นตอนกะพริบ)
EYE_MAG = 2.0


def _c(connected: bool, color: str) -> str:
    return color if connected else PAL.gray_dark


def _ring_round(x: float, y: float, s: float, t: float, color: str) -> RectList:
    """วงกลมกลวง หนา t — ตัดมุมทั้งสี่เป็นแนวทแยง จึงอ่านเป็นวงกลมไม่ใช่กรอบสี่เหลี่ยม"""
    c = s / 4.0  # ความยาวมุมที่ตัดออก
    out = [
        Rect(x + c, y, s - 2 * c, t, color),  # บน
        Rect(x + c, y + s - t, s - 2 * c, t, color),  # ล่าง
        Rect(x, y + c, t, s - 2 * c, color),  # ซ้าย
        Rect(x + s - t, y + c, t, s - 2 * c, color),  # ขวา
    ]
    for cx, cy in ((c - t, c - t), (s - c, c - t), (c - t, s - c), (s - c, s - c)):
        out.append(Rect(x + cx, y + cy, t, t, color))  # ชิ้นเชื่อมมุม
    return out


LENS_S, LENS_T = 8.0, 0.9


def _lens_box(phase: float) -> tuple[float, float]:
    """มุมบนซ้ายของเลนส์ในเฟรมนี้ — กระจกกับขอบต้องอ่านค่าเดียวกัน ไม่งั้นเลื่อนหลุดกัน"""
    # ขยับลงอย่างเดียว — เลนส์สูงกว่าหัวอยู่แล้ว ถ้าลอยขึ้นอีกจะฉีกซิลลูเอ็ตจนอ่านไม่ออก
    lift = abs(math.sin(phase * math.pi * 2.0)) * 0.4
    x = EYE_R + EYE_S / 2.0 - LENS_S / 2.0  # จัดวงให้ล้อมตาข้างขวาพอดี
    return x, EYE_Y + EYE_S / 2.0 - LENS_S / 2.0 + lift


def magnifier_glass(phase: float, connected: bool = True) -> RectList:
    """กระจกในเลนส์ — วาดก่อนตา (mascot.py เป็นคนเรียก) ตาจึงทับอยู่บนกระจก

    ถ้าวาดพร้อมขอบเลนส์ซึ่งอยู่หน้าตา กระจกจะบังตาที่เป็นพระเอกของท่านี้
    """
    # ตอนหลุดการเชื่อมต่อใช้สีเดียวกับลำตัว = กระจกหายไปเลย ไม่ใช่หรี่เป็นเทาเข้ม
    # เพราะเทาเข้มจะกลืนกับสีตาจนมองไม่เห็นตาในวง
    col = PAL.glass if connected else PAL.gray
    x, y = _lens_box(phase)
    s = LENS_S - 2 * LENS_T  # เต็มรูในวงแหวนพอดี
    x, y = x + LENS_T, y + LENS_T
    c = LENS_S / 4.0 - LENS_T  # มุมที่ตัดต้องพอดีบันไดด้านในของวงแหวน ไม่เหลือรูและไม่ล้น
    return [
        Rect(x + c, y, s - 2 * c, c, col),
        Rect(x, y + c, s, s - 2 * c, col),
        Rect(x + c, y + s - c, s - 2 * c, c, col),
    ]


def magnifier(phase: float, connected: bool = True) -> RectList:
    """แว่นขยาย — Read/Grep/Glob

    ยกมาส่องที่ตาข้างขวาแทนที่จะถือห้อยข้างตัว: ท่านี้อ่านออกทันทีว่า "กำลังอ่าน"
    ไม่ใช่แค่ "ถือของกลมๆ" ในวงมีตาที่ถูกขยายบนกระจกฟ้าอ่อน (ทั้งคู่ mascot.py
    วาดให้ก่อนหน้านี้) ด้ามลากไปจบที่แขนขวา ขยับขึ้นลงเหมือนกำลังปรับระยะส่อง

    กรอบเป็นฟ้าเทา เข้มกว่ากระจกพอให้เห็นเป็นวงแหวน แต่ไม่ดังกว่าตาที่เป็นพระเอกของท่านี้
    วงใหญ่กว่าหัวและล้นขึ้นไปด้านบน — ตั้งใจ ให้อ่านออกแต่ไกลว่าเป็นแว่นขยาย ไม่ใช่แว่นตา
    """
    col = _c(connected, PAL.steel)
    s, t = LENS_S, LENS_T
    x, y = _lens_box(phase)
    out = _ring_round(x, y, s, t, col)
    for i in range(3):  # ด้ามลากลงขวาไปจบที่มือ — ต้องพ้นขอบแขน (16.5) ถึงจะอ่านออกว่าถืออยู่
        out.append(Rect(x + s - 0.5 + i * 1.15, y + s * 0.70 + i * 0.55, 1.5, 1.05, col))
    # แสงสะท้อนบนกระจกเป็นขีดสองขีดมุมบนซ้าย — วางในช่องว่างระหว่างตากับขอบ ไม่ทับตา
    glint = _c(connected, PAL.outline)
    out.append(Rect(x + 1.05, y + 2.5, 0.9, 1.5, glint))
    out.append(Rect(x + 2.3, y + 1.05, 1.5, 0.9, glint))
    return out


# แล็ปท็อป — วางหน้าลำตัว ไม่ใช่ช่อง prop ข้างตัว จึงมีค่าคงที่ชุดของตัวเอง
# ใหญ่เกือบเท่าลำตัว แต่แคบกว่าอยู่ราวข้างละ 1 unit — ช่องนั้นคือที่ที่ไหล่ยังโผล่ให้เห็น
# แขนที่โผล่ข้างฝาคือแขนเดิมของลำตัว (nub) ที่ขยับขึ้นลง — ไม่มีแขนวาดเพิ่มพาดหน้าฝา
LID_X, LID_W = 2.5, 11.0
LID_Y, LID_H = 5.0, 4.9  # ขอบบนต่ำกว่าตา (จบที่ 4.1) — จอไม่บังหน้า
LAP_X, LAP_W = 1.8, 12.4  # ฐาน — ยื่นออกกว่าฝาจอนิดเดียว จึงอ่านเป็นแล็ปท็อปไม่ใช่ป้าย
LAP_Y, LAP_H = 9.9, 1.3  # ฐานจบพอดีระดับฝ่าเท้า (11.2) — แล็ปท็อปบังขาหมดทั้งสี่


# โลโก้แอปเปิลบนฝา — เขียนเป็นภาพ ASCII ตรงๆ อ่านง่ายกว่าลิสต์ตัวเลข
# ช่องละ 0.25 unit = 1 พิกเซลพอดีที่ unit_px=4 จึงคมและไม่เพี้ยนจากการปัดเศษ
# ใบเอียงขึ้นขวา ตัวลูกเป็นก้อนกลมทึบ ขอบขวาเว้าสองแถว = รอยกัด ก้นแยกสองพู
# ตั้งใจให้รายละเอียดน้อย: ที่ 12 px ต่อโลโก้ รอยหยักย่อยๆ กลายเป็นขอบเละ ไม่ใช่รูปทรง
APPLE_PX = 0.25
APPLE_ART = (
    ".....##...",
    "....##....",
    "..######..",
    ".########.",
    "##########",
    "########..",
    "########..",
    "##########",
    ".########.",
    "..######..",
    "..##..##..",
)


def _apple(x: float, y: float, color: str) -> RectList:
    """แปลง APPLE_ART เป็น rect ทีละช่วงพิกเซลติดกัน ไม่ใช่ทีละช่อง"""
    out: RectList = []
    for row, line in enumerate(APPLE_ART):
        col = 0
        while col < len(line):
            if line[col] == "#":
                run = 1
                while col + run < len(line) and line[col + run] == "#":
                    run += 1
                out.append(
                    Rect(x + col * APPLE_PX, y + row * APPLE_PX, run * APPLE_PX, APPLE_PX, color)
                )
                col += run
            else:
                col += 1
    return out


def laptop(phase: float, connected: bool = True) -> RectList:
    """แล็ปท็อป — Edit/Write  (นั่งพิมพ์ โดยจอหันหลังให้เรา)

    วางทับลำตัวแทนที่จะถือข้างตัวเหมือน prop อื่น: ท่า "พิมพ์โค้ดอยู่" อ่านออกจากการ
    มีจอคั่นระหว่างเรากับตัวมัน จอหันหลัง = ฝาเป็นแผ่นเหล็กทึบล้วน ไม่มีอะไรสว่างอยู่บนนั้น
    สิ่งเดียวที่บอกว่าจออีกด้านเปิดอยู่คือแสงที่รอดขึ้นมาเลาะขอบบนของฝาไปโดนหน้ามัน
    (จุดสว่างกลางฝาจะอ่านกลับเป็นจอหันเข้าหาเราทันที จึงห้ามมี)
    ส่วนการอ่านสื่อด้วยสายตาที่กวาดซ้ายไปขวา และการพิมพ์สื่อด้วยแขนที่ขยับสลับข้าง
    (ทั้งคู่อยู่ใน mascot.py)
    """
    # ฝาเป็นแผ่นเหล็กทึบ ไม่ใช่สีดำ — สี่เหลี่ยมดำใหญ่ๆ อ่านเป็น "จอที่เปิดอยู่" เสมอ
    # ต่อให้ไม่มีอะไรสว่างบนนั้น ขอบสีหมึกบางๆ ทำหน้าที่ตัดฝาออกจากลำตัวแทน
    shell = _c(connected, PAL.steel)
    rim = _c(connected, PAL.ink)
    # แสงที่รอดขอบจอ — ตอนหลุดการเชื่อมต่อใช้เทาอ่อน ไม่ใช่เทาเข้ม ไม่งั้นกลืนไปกับฝา
    spill = PAL.glass if connected else PAL.gray

    out = [
        Rect(LID_X, LID_Y, LID_W, LID_H, rim),  # ขอบฝา — ตัดฝากับลำตัวสีดินออกจากกัน
        Rect(LID_X + 0.5, LID_Y + 0.5, LID_W - 1.0, LID_H - 1.0, shell),  # หลังฝา (ทึบล้วน)
        Rect(LAP_X, LAP_Y, LAP_W, LAP_H, rim),  # ฐาน — เข้มกว่าฝา จึงไม่อ่านเป็นก้อนเดียวกัน
        Rect(LAP_X, LAP_Y, LAP_W, 0.5, shell),  # สันบนของฐาน = ระนาบคีย์บอร์ดที่รับแสง
    ]
    # แสงจอรอดขึ้นมาเหนือฝา หายใจเข้าออกช้าๆ — ขีดบางๆ ขีดเดียว ไม่ใช่ก้อนสว่าง
    # ต้องอยู่ *เหนือ* ขอบฝา ไม่ใช่บนฝา ไม่งั้นกลับไปอ่านเป็นเนื้อจออีก
    w = LID_W - 4.0 + 0.8 * math.sin(phase * math.pi * 2.0)
    out.append(Rect(LID_X + (LID_W - w) / 2.0, LID_Y - 0.5, w, 0.5, spill))

    # โลโก้แอปเปิลกลางฝา — รูปทรงชัดเจน ไม่ใช่ก้อนสว่างสี่เหลี่ยม จึงไม่พลิกกลับไป
    # อ่านเป็นเนื้อจอ วาดทีละแถวเป็นแท่งยาว ไม่ใช่ทีละพิกเซล จะได้ไม่กิน rect budget
    mark = _c(connected, PAL.outline)
    ax = LID_X + (LID_W - len(APPLE_ART[0]) * APPLE_PX) / 2.0
    ay = LID_Y + (LID_H - len(APPLE_ART) * APPLE_PX) / 2.0
    out += _apple(ax, ay, mark)
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
    "laptop": laptop,
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
