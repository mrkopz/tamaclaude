"""กติกาของหน้า watchlist ทุกหน้า — พอร์ตคู่กับ firmware/main/ct_trend.c

หน้า watchlist ทุกหน้า (คริปโต หุ้น) เล่าเรื่องเดียวกันด้วยกติกาชุดเดียวกัน อยู่ที่นี่
ที่เดียวเพราะมันเป็นสัญญากับผู้ใช้ ไม่ใช่รายละเอียดของหน้าใดหน้าหนึ่ง: ลูกศรที่ชี้คนละแบบ
ระหว่างสองหน้าคือจอที่ต้องอ่านสองครั้งเพื่อรู้เรื่องเดียวกัน · *พิกัด* ไม่ได้อยู่ที่นี่ มันอยู่
ใน [crypto]/[stocks] แยกกันคนละชุด ด้วยเหตุผลที่ layout.toml เขียนไว้แล้ว

ทิศทางเป็นกติกาข้อแรกของไฟล์นี้ ไม่ใช่ข้อเดียว — ตอนนี้มีรูป 24 ชั่วโมง (`spark`) และ
การหั่นราคาเป็นสองขนาด (`split_price`) ด้วย ทั้งคู่เป็นสิ่งที่สองหน้าต้องทำเหมือนกันเป๊ะ

สีอย่างเดียวไม่พอ: ตาบอดสีแดง-เขียวคือคนกลุ่มใหญ่ที่สุดที่ *ต้อง* แยกกำไรกับขาดทุนออก
โดยไม่อ่านตัวเลข รูปทรงจึงเป็นตัวบอกหลัก ส่วนสีเป็นตัวช่วยที่สอง
"""

from __future__ import annotations

from dataclasses import dataclass

from .config import PAL
from .rects import Rect, RectList

# ระดับสูงสุดที่ nibble หนึ่งตัวเก็บได้ — ตรงกับที่ Mac quantize มาบนสาย
SPARK_MAX = 15


def tone(change: int, connected: bool = True) -> str:
    """สีของแถวหนึ่ง — ทั้งลูกศรและตัวเลขเปอร์เซ็นต์อ่านจากที่เดียวกัน

    ต้องตรงกับ ct_trend_tone() ใน ct_trend.c
    """
    if not connected:
        return PAL.gray
    if change > 0:
        return PAL.good
    if change < 0:
        return PAL.alert
    return PAL.text_dim


@dataclass(frozen=True)
class Arrow:
    """ลูกศรหนึ่งใบ: *ทิศทาง* เป็นสามเหลี่ยม ส่วน *นิ่ง* เป็นขีด สองอย่างนี้วาดคนละแบบ"""
    color: str
    tri: tuple[tuple[float, float], ...] | None  # สามจุดในตาราง 4x4 unit (None = นิ่ง)
    bar: RectList                                # ขีดนิ่ง (ว่างเมื่อมีสามเหลี่ยม)


# ปลายอยู่กึ่งกลางแนวนอน ฐานกว้างเท่ากับความสูง — สามเหลี่ยมด้านเท่าโดยประมาณอ่านเป็น
# "ลูกศร" ที่ 16px ได้เร็วกว่าทรงเรียวสูง ซึ่งที่ขนาดนี้เริ่มอ่านเป็นขีดเอียง
_TRI_INSET = 0.4  # เว้นขอบตาราง unit ไว้ทุกด้าน กันปลายชนกล่องผืนวาด


def arrow(change: int, connected: bool = True) -> Arrow:
    """ลูกศรขึ้น/ลง — ต้องตรงกับ ct_trend_arrow() ใน ct_trend.c

    **สามเหลี่ยมจริง ไม่ใช่บันไดสี่เหลี่ยมสามขั้นเหมือนของเดิม** — ที่ 16px ขั้นบันได
    อ่านออกว่าเป็นขั้น ไม่ใช่ด้านเฉียง และมันเป็นชิ้นเดียวบนหน้าที่ต้องแหลมจริงๆ (ทุกอย่าง
    อื่นบนสองหน้านี้เป็นแท่งกับกล่องซึ่งขอบตรงอยู่แล้ว) · ทั้งสองฝั่งวาดด้วยขอบ
    anti-alias: บอร์ดได้จาก lv_draw_triangle, พรีวิวได้จากการ supersample ใน render.py
    """
    color = tone(change, connected)

    if change == 0:
        # นิ่งคือขีดเดียว ไม่ใช่ลูกศรแบนๆ — สามเหลี่ยมที่ชี้ไปไหนไม่ได้อ่านเป็นลูกศรเสีย
        return Arrow(color, None, [Rect(0.5, 1.75, 3.0, 0.5, color)])

    lo, hi = _TRI_INSET, 4.0 - _TRI_INSET
    apex_y, base_y = (lo, hi) if change > 0 else (hi, lo)
    return Arrow(color, ((2.0, apex_y), (lo, base_y), (hi, base_y)), [])


def card_fill(change: int, live: bool) -> str:
    """พื้นการ์ดของแถวแรก — `live` = ตัวเลขชุดนี้ยังเดินอยู่จริงไหม

    ต้องตรงกับ ct_trend_card_fill() ใน ct_trend.c · `live` เป็นคนละเรื่องกับ `connected`
    ฝั่งผู้เรียก: หุ้นตอนตลาดปิดยังต่อลิงก์อยู่ แต่ราคาหยุดเดินโดยชอบธรรม ทั้งสองกรณี
    ได้พื้นกลางเหมือนกัน เพราะการ์ดที่ยังเขียวอยู่ตอนตัวเลขไม่ขยับคือการโกหก
    """
    if not live:
        return PAL.bg_slot
    if change > 0:
        return PAL.bg_card_up
    if change < 0:
        return PAL.bg_card_down
    return PAL.bg_slot


def card_edge(change: int, connected: bool) -> str:
    """ขอบการ์ดของแถวแรก — ต้องตรงกับ ct_trend_card_edge() ใน ct_trend.c

    ไม่ใช่ `tone()` แม้จะตอบคำถามเดียวกัน: `tone` เป็นสีของสิ่งที่ *บอก* ทิศทาง
    (ลูกศร ตัวเลข แท่ง) ส่วนขอบเป็นสิ่งที่บอกว่ามีการ์ดอยู่ ถ้าใช้สีเดียวกันกรอบ 303px
    จะกลบทุกอย่างที่มันล้อมอยู่ · เหตุผลเต็มอยู่ที่ `card_edge_up` ใน [palette]
    """
    if not connected:
        return PAL.gray
    if change > 0:
        return PAL.card_edge_up
    if change < 0:
        return PAL.card_edge_down
    return PAL.gray


def fold(levels: list[int], cols: int) -> list[int]:
    """ย่อจำนวนจุดลง โดย **เก็บปลายทั้งสองไว้เสมอ**

    ต้องตรงกับ ct_trend_fold() ใน ct_trend.c · เฉลี่ยเป็นคู่ๆ จะทำให้จุดสุดท้ายไม่ใช่
    ราคาปิดอีกต่อไป แล้วแท่งสุดท้ายก็เลิกตรงกับเปอร์เซ็นต์ที่พิมพ์อยู่ข้างมัน — ซึ่งเป็น
    สิ่งเดียวที่ทำให้รูปกับตัวเลขอ่านเป็นประโยคเดียวกันได้
    """
    n = len(levels)
    if n <= cols or cols < 2:
        return list(levels)
    # เลขจำนวนเต็มปัดครึ่งขึ้น ไม่ใช่ `round()` — `round()` ของ Python ปัดครึ่งไปเลขคู่
    # ส่วน C ไม่มีทางทำแบบนั้นโดยไม่ตั้งใจ สองพอร์ตจะต่างกันเงียบๆ ที่ .5 พอดีวันหนึ่ง
    return [levels[(i * (n - 1) * 2 + (cols - 1)) // (2 * (cols - 1))] for i in range(cols)]


def spark(levels: list[int], *, w: int, h: int, cols: int, pitch: int, bar: int,
          connected: bool = True) -> RectList:
    """รูปราคา 24 ชั่วโมงเป็นแท่ง — ต้องตรงกับ ct_trend_spark() ใน ct_trend.c

    พิกัดที่คืนเป็น *พิกเซล* ไม่ใช่ unit เหมือน `arrow`: กล่องของมันมีขนาดจริงในเลย์เอาต์
    ทั้งสองหน้า การให้มันเป็น unit แล้วคูณกลับคือการปัดเศษสองรอบโดยไม่ได้อะไรเพิ่ม

    **เส้นฐานคือจุดแรก** ไม่ใช่ค่ากลางหรือค่าต่ำสุด — จุดแรกคือราคาเปิดของ 24 ชั่วโมง
    แท่งที่โผล่เหนือเส้น = แพงกว่าตอนเปิด จมใต้เส้น = ถูกกว่า ทิศทางจึงกลายเป็น
    *ตำแหน่ง* ที่คนตาบอดสีอ่านได้เท่ากับคนอื่น และไม่ต้องส่งราคาเปิดมาบนสายเพิ่มเลย
    แถมยังทำให้แท่งสุดท้ายเทียบเส้นฐาน = เปอร์เซ็นต์ที่พิมพ์อยู่ โดยโครงสร้าง ไม่ใช่โดยบังเอิญ

    แท่งที่ยาวศูนย์ไม่ถูกวาด (รวมถึงแท่งแรกซึ่งเป็นเส้นฐานเอง) — เส้นฐานพูดแทนแล้ว
    ถ้ายัดแท่ง 1px ลงไปทับ มันจะอ่านเป็นเส้นฐานที่หนาไม่เท่ากันตลอดแนว
    """
    pts = fold(levels, cols)
    base = PAL.text_dim if connected else PAL.gray
    if not pts:
        # ไม่มีประวัติ (บริการไม่ให้มา หรือถูกตัดทิ้งตอนบีบเฟรม) = เส้นฐานเปล่ากลางกล่อง
        # ไม่ใช่กล่องว่าง · กล่องว่างอ่านเป็นที่ที่ยังโหลดไม่เสร็จ ส่วนเส้นเปล่าอ่านเป็น
        # "รู้ว่าควรมีอะไรตรงนี้ แต่ไม่มี" ซึ่งเป็นความจริง
        return [Rect(0, (h - 1) // 2, w, 1, base)]

    def y_of(level: int) -> int:
        lv = min(max(level, 0), SPARK_MAX)
        return round((SPARK_MAX - lv) * (h - 1) / SPARK_MAX)

    base_y = y_of(pts[0])
    out: RectList = [Rect(0, base_y, w, 1, base)]
    for i, lv in enumerate(pts):
        x = i * pitch
        if x + bar > w:
            break
        y, delta = y_of(lv), lv - pts[0]
        # แท่งขึ้นจบก่อนเส้นฐานหนึ่งพิกเซล แท่งลงเริ่มหลังมันหนึ่งพิกเซล — เส้นฐานต้อง
        # มองเห็นตลอดแนว ไม่งั้นตัวอ้างอิงของทั้งรูปหายไปตรงที่มีข้อมูลหนาแน่นที่สุดพอดี
        top, height = (y, base_y - y) if delta > 0 else (base_y + 1, y - base_y)
        if height > 0:
            out.append(Rect(x, top, bar, height, tone(delta, connected)))
    return out


def split_price(price: str, int_digits_max: int) -> tuple[str, str]:
    """ราคา -> (ก้อนที่ได้ฟอนต์ใหญ่, ก้อนที่ได้ฟอนต์เล็ก)

    ต้องตรงกับ ct_trend_split_price() ใน ct_trend.c · ก้อนหลังรวมจุดทศนิยมไว้ด้วย
    คืน `("", price)` แปลว่า "ทั้งก้อนเล็ก" ซึ่งเกิดสองกรณี: จำนวนเต็มยาวเกินกล่อง
    หรือราคาไม่มีจุดเลย (ซึ่งไม่ควรเกิดหลัง Mac ตรึงทศนิยมไว้ แต่บอร์ดไม่ได้เชื่อ Mac)
    """
    head, dot, tail = price.partition(".")
    # นับ *หลัก* ไม่ใช่ตัวอักษร — Mac เติมจุลภาคคั่นหลักพันมาแล้ว ("65,343.56") ถ้านับ
    # ตัวอักษร ราคาหกหลักจะยาว 7 ตัวและถูกหั่นลงฟอนต์เล็กทั้งก้อนก่อนถึงเพดานจริง
    if not dot or sum(c.isdigit() for c in head) > int_digits_max:
        return "", price
    return head, dot + tail


def pct_text(change: int) -> str:
    """เปอร์เซ็นต์คูณสิบ -> ข้อความที่มีเครื่องหมายเสมอ

    "+1.1%" กับ "1.1%" ต่างกันตรงที่อันหลังต้องอ่านสีหรือลูกศรก่อนถึงจะรู้ว่าขึ้นหรือลง
    ต้องตรงกับ ct_trend_pct_text() ใน ct_trend.c
    """
    sign = "+" if change > 0 else ("-" if change < 0 else "")
    return f"{sign}{abs(change) // 10}.{abs(change) % 10}%"
