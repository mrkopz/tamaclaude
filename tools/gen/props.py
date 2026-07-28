"""Prop — ของที่มาสคอตถือหรือลอยเหนือหัว บอกว่ากำลังทำอะไร

พิกัดอยู่ในตารางเดียวกับมาสคอต ซิลลูเอ็ตกิน x -0.5..16.5, y 0..11.2 (ฝ่าเท้าที่ y=11.2)
  prop ถือ  อยู่ช่วง x 17.2..23.4 — นอกลำตัว ไม่ทับตา ไม่ทับขา
  prop ลอย  อยู่ช่วง y -5.6..-0.1 เหนือหัว
  ยกเว้นแว่นขยาย ที่ตั้งใจให้ทับตาข้างขวา (ท่ายกส่อง) — เลนส์กลวงจึงยังเห็นตา
  ยกเว้นค้อน ที่กินหัว (หมวกวิศวกร) และพื้นด้านขวา (ปุ่มแดง) เพิ่มจากช่อง prop ปกติ
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


# ค้อน + หมวกวิศวกร + แท่นเหล็ก — ทั้งชุดคือ prop เดียวกัน (Bash) จึงใช้ค่าคงที่ร่วมกัน
# หนึ่งลูปคือการทุบหนึ่งครั้งที่มีจังหวะเงื้อนำ ไม่ใช่ค้อนเด้งขึ้นลงสองรอบ:
# จังหวะเงื้อคือสิ่งที่ทำให้การกระแทกมีน้ำหนัก ถ้าตัดทิ้งจะเหลือแค่ของขยับไปมา
HAM_READY, HAM_WINDUP, HAM_STRIKE, HAM_RECOVER = 0, 1, 2, 3
# ขอบเขตของแต่ละท่าในลูป — ท่าฟาดสั้นที่สุด (สองเฟรม) เพราะการกระแทกต้องคม
HAM_T_WINDUP, HAM_T_STRIKE, HAM_T_RECOVER = 0.25, 0.45, 0.62

ANVIL_CX = 20.0  # กลางแท่น = ปลายทางที่หัวค้อนตกลงมา
ANVIL_TOP = 8.7  # ผิวบนของบล็อก = ก้นของชิ้นงานร้อน ทั้งตอนยุบและไม่ยุบ
HOT_UP_H, HOT_DOWN_H = 1.3, 0.7  # ชิ้นงานยุบลงราวครึ่งหนึ่งตอนโดนทุบ

HAM_HEAD_W, HAM_HEAD_H = 4.0, 2.4  # หัวค้อน
HAM_GRIP_W = 1.4  # ความหนาของด้าม
HAM_STEP = 0.65  # ระยะไล่ของบล็อกด้ามต่อชิ้น ทั้งสองแกน = ทแยง 45 องศาพอดี
HAM_BLK = 1.4  # ด้านของบล็อกด้าม — ใหญ่กว่า step จึงเหลื่อมกันเป็นเส้นทึบ ไม่ขาดเป็นจุด
HAM_N = 5  # จำนวนบล็อกด้าม


def hammer_stage(phase: float) -> int:
    """ท่าของการทุบในเฟรมนี้ — ค้อน ตัวมาสคอต ชิ้นงาน และประกาย ต้องอ่านค่าเดียวกัน

    ถ้าแต่ละชิ้นคิดจังหวะเอง จะได้ภาพที่ตัวยุบตอนค้อนยังลอย หรือประกายมาก่อนโดน
    (mascot.py import ไปใช้กำหนดท่าตัวมาสคอตด้วย)
    """
    if phase < HAM_T_WINDUP:
        return HAM_READY
    if phase < HAM_T_STRIKE:
        return HAM_WINDUP
    if phase < HAM_T_RECOVER:
        return HAM_STRIKE
    return HAM_RECOVER


def hammer_anvil(phase: float, connected: bool = True) -> RectList:
    """แท่นเหล็กกับชิ้นงานร้อน — วาดแยกจาก hammer() เพราะห้ามกระเด้งตามตัวมาสคอต

    ของที่วางอยู่กับพื้นต้องนิ่ง ถ้าเลื่อนตาม dy ของลำตัวจะอ่านเป็นแท่นลอยได้
    (mascot.py จึงเรียกอันนี้แยกโดยไม่ move ตาม dy เหมือน prop ชิ้นอื่น)
    """
    strike = hammer_stage(phase) == HAM_STRIKE
    # แท่นเป็นเทาสองโทน ไม่ใช่สีหมึก — สีหมึกจมหายไปกับพื้นหลังช่อง เหลือชิ้นงานลอยเดี่ยว
    block = _c(connected, PAL.steel)
    base = _c(connected, PAL.text_dim)
    # ชิ้นงานวาบเป็นเหลืองสว่างในเฟรมที่โดนกระแทก แล้วคืนเป็นแดงร้อน
    hot = _c(connected, PAL.accent if strike else PAL.alert)
    h = HOT_DOWN_H if strike else HOT_UP_H
    return [
        # ฐานกว้างกว่าบล็อก จึงอ่านเป็นของตั้งอยู่กับพื้น ไม่ใช่ก้อนลอย
        Rect(ANVIL_CX - 2.6, 10.4, 5.2, 0.8, base),  # ฐานจบพอดีระดับฝ่าเท้า (11.2)
        Rect(ANVIL_CX - 1.9, ANVIL_TOP, 3.8, 1.7, block),  # บล็อกเหล็ก
        Rect(ANVIL_CX - 1.25, ANVIL_TOP - h, 2.5, h, hot),  # ชิ้นงานร้อน — ยุบตอนโดนทุบ
    ]


# หมวกนิรภัย — พีระมิดขั้นบันได กว้างขึ้นทีละขั้นจนจบที่ปีกซึ่งกว้างเท่าช่วงแขน
# '#' คือด้านที่รับแสง '+' คือริ้วเงา — ริ้วแนวตั้งสลับกันคือสิ่งที่ทำให้หมวกมีสัน
# ไม่ใช่โดมเรียบ และอ่านออกว่าเป็นหมวกนิรภัยตั้งแต่แวบแรก
HAT_ART = (
    ".....##+##.....",
    "....+##+##+....",
    "...+##+#+##+...",
    "..++#######++..",
    "+++++++++++++++",
)
HAT_COLS = len(HAT_ART[0])
HAT_W = 16.0  # ปีกยื่นพ้นลำตัว (1..15) ข้างละ 1 — กว้างกว่านี้เริ่มอ่านเป็นหมวกชาวนา
HAT_X0 = 0.0
HAT_ROW_H = 0.96  # ห้าแถวรวม 4.8 — สูงกว่านี้ยอดหมวกจะโผล่พ้นกรอบวาดตอนตัวกระเด้ง


def _hat(light: str, dark: str) -> RectList:
    """แปลง HAT_ART เป็น rect ทีละช่วงสีติดกัน ไม่ใช่ทีละช่อง"""
    u = HAT_W / HAT_COLS
    out: RectList = []
    for row, line in enumerate(HAT_ART):
        y = -len(HAT_ART) * HAT_ROW_H + row * HAT_ROW_H
        col = 0
        while col < HAT_COLS:
            ch = line[col]
            if ch == ".":
                col += 1
                continue
            run = 1
            while col + run < HAT_COLS and line[col + run] == ch:
                run += 1
            out.append(
                Rect(HAT_X0 + col * u, y, run * u, HAT_ROW_H, light if ch == "#" else dark)
            )
            col += run
    return out


def _hammer_tool(stage: int, grip: str, head: str, face: str) -> RectList:
    """ค้อนในท่าหนึ่ง — สามท่าคีย์ ไม่ใช่การหมุนต่อเนื่อง

    renderer วาดได้แต่สี่เหลี่ยมแกนตั้งฉาก การหมุนจริงจึงทำไม่ได้ ท่าคีย์สามท่า
    (ตั้งพัก / เงื้อทแยงขึ้น / ฟาดทแยงลง) ให้สายตาเติมส่วนที่ขาดเองอยู่แล้ว
    """
    out: RectList = []
    if stage in (HAM_READY, HAM_RECOVER):
        # ตั้งพักข้างตัว — ด้ามเอียงขวาเป็นสองขั้น ปลายล่างจบในระดับมือ ไม่ลอยห่างจากแขน
        out.append(Rect(16.9, 2.2, HAM_GRIP_W, 3.2, grip))
        out.append(Rect(17.8, -1.2, HAM_GRIP_W, 3.6, grip))
        hx, hy = 16.6, -3.6
    else:
        # ด้ามทแยง 45 องศาจากมือ — ขึ้นตอนเงื้อ ลงตอนฟาด (สะท้อนรอบระดับมือเดียวกัน)
        up = stage == HAM_WINDUP
        y0 = 3.6 if up else 2.6
        step = -HAM_STEP if up else HAM_STEP
        for i in range(HAM_N):
            out.append(Rect(17.0 + i * HAM_STEP, y0 + i * step, HAM_BLK, HAM_BLK, grip))
        # หัวค้อนต้องคาบปลายด้ามไว้เสมอ ไม่งั้นเห็นเป็นก้อนเทาลอยแยกจากด้าม
        # ตอนฟาด ก้นหัวจบที่ผิวชิ้นงานที่ยุบแล้วพอดี = จุดที่แรงลงจริง
        hx = ANVIL_CX - HAM_HEAD_W / 2.0
        hy = -1.0 if up else ANVIL_TOP - HOT_DOWN_H - HAM_HEAD_H
        if up:
            hx = 18.8
    out.append(Rect(hx, hy, HAM_HEAD_W, HAM_HEAD_H, head))
    # ครึ่งล่างของหัวเข้ม = หน้าค้อนที่ฟาดลงไป ทำให้ก้อนเทาไม่แบนเป็นก้อนเดียว
    out.append(Rect(hx, hy + HAM_HEAD_H / 2.0, HAM_HEAD_W, HAM_HEAD_H / 2.0, face))
    return out


# ประกายกระเด็นจากจุดกระแทก — สามทิศที่ไม่สมมาตรกัน จึงอ่านเป็นเศษที่กระเด็นจริง
# ไม่ใช่เอฟเฟกต์ที่ก๊อปวางสองข้าง (ทิศมาจากไฟล์ต้นแบบ คูณสเกลของตารางนี้)
SPARK_DIRS = ((2.5, -3.8), (3.1, -0.6), (1.9, 1.9))


def hammer(phase: float, connected: bool = True) -> RectList:
    """หมวกวิศวกร + ค้อน — Bash  (เงื้อแล้วฟาดชิ้นงานบนแท่น หนึ่งครั้งต่อลูป)

    ค้อนแกว่งอย่างเดียวอ่านได้แค่ "ถือของ" — ท่าที่อ่านออกว่ากำลังสั่งงานเครื่องคือ
    ครบชุด: หมวกบอกว่าเป็นคนคุมงาน ค้อนคือเครื่องมือ แท่นคือสิ่งที่ถูกลงแรง
    น้ำหนักของการกระแทกมาจากจังหวะ (เงื้อค้าง -> ฟาดสองเฟรม -> คืนตัว) ไม่ใช่จากขนาด
    """
    stage = hammer_stage(phase)
    out = _hat(_c(connected, PAL.accent), _c(connected, PAL.accent_dark))
    out += _hammer_tool(
        stage,
        _c(connected, PAL.clay_dark),
        _c(connected, PAL.text_dim),
        # เงาของหัวค้อนต้องเป็นเทากลาง ไม่ใช่สีหมึก — สีหมึกเกือบเท่าพื้นหลังช่อง
        # ครึ่งล่างของหัวจะหายไปกับฉาก เหลือหัวค้อนบางเป็นขีด
        _c(connected, PAL.gray),
    )

    # หยดเหงื่อกระเด็นออกข้างหมวก ตั้งแต่เงื้อจนฟาด — สัญญาณว่ากำลังออกแรง ไม่ใช่กำลังเล่น
    if stage in (HAM_WINDUP, HAM_STRIKE):
        drop = _c(connected, PAL.glass)
        fly = 1.2 if stage == HAM_STRIKE else 0.0
        x, y = 1.0 - fly, -1.2 - fly
        out.append(Rect(x, y, 1.3, 1.3, drop))
        out.append(Rect(x + 0.3, y - 0.8, 0.7, 0.8, drop))

    if stage == HAM_STRIKE:
        # กระเด็นออกครึ่งทางในเฟรมที่สองของการฟาด — เฟรมเดียวจะอ่านเป็นจุดค้าง ไม่ใช่ประกาย
        t = 0.0 if phase < (HAM_T_STRIKE + HAM_T_RECOVER) / 2.0 else 1.0
        spark = _c(connected, PAL.accent)
        for dx, dy in SPARK_DIRS:
            out.append(Rect(ANVIL_CX - 0.6 + dx * t, ANVIL_TOP - 1.4 + dy * t, 1.2, 1.2, spark))
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


BUB_W, BUB_H = 9.4, 3.9


def dots(phase: float, connected: bool = True) -> RectList:
    """ฟองข้อความเหนือหัว — thinking  (จุดในฟองไล่สว่างทีละจุด)

    ฟองทึบสีสว่าง จุดเป็นสีเข้ม — อ่านออกที่ 12px กว่าจุดลอยเปล่าๆ ซึ่งดูเหมือนเศษ noise
    หางฟองเป็นบันไดชี้ลงหาหัว บอกว่าความคิดนี้เป็นของมาสคอต ไม่ใช่ของ slot ข้างๆ
    """
    # ตอนหลุดการเชื่อมต่อฟองต้องหรี่เป็นเทา แต่ยังต้องเข้มพอให้จุดข้างในไม่จม
    skin = PAL.text if connected else PAL.gray
    # จุดฟ้า: ทั้งสามใช้ฟ้าเทาเข้ม (steel) ตัวเดียวกัน ต่างกันแค่ขนาด
    # (ถ้าให้จุดที่ยังไม่ติดเป็นฟ้าอ่อน มันจะจมหายไปกับฟองสว่างเมื่อย่อลงเหลือ ~4px/unit)
    dark = PAL.steel if connected else PAL.gray_dark
    dim = PAL.steel if connected else PAL.gray_dark

    bob = 0.3 * (0.5 + 0.5 * math.sin(phase * math.pi * 2.0))  # ลงอย่างเดียว กันล้นขอบบน
    x, y = HEAD_CX - BUB_W / 2.0, -5.4 + bob
    cut = 0.8  # มุมที่ตัดออก ทำให้ฟองมนไม่ใช่กล่อง
    out: RectList = [
        Rect(x + cut, y, BUB_W - 2 * cut, cut, skin),
        Rect(x, y + cut, BUB_W, BUB_H - 2 * cut, skin),
        Rect(x + cut, y + BUB_H - cut, BUB_W - 2 * cut, cut, skin),
    ]

    # หางบันไดสองขั้น — เยื้องซ้ายของฟอง ชี้ลงหาหัวที่ y=0
    ty = y + BUB_H
    out.append(Rect(x + 2.4, ty, 1.7, 0.7, skin))
    out.append(Rect(x + 2.4, ty + 0.7, 0.9, 0.6, skin))

    lit = int(phase * 3.0) % 3
    for i in range(3):
        s = 1.7 if i == lit else 1.0
        cx = HEAD_CX + (i - 1) * 2.6
        cy = y + BUB_H / 2.0
        out.append(Rect(cx - s / 2, cy - s / 2, s, s, dark if i == lit else dim))
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
