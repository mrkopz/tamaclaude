"""ขึ้น ลง หรือนิ่ง — พอร์ตคู่กับ firmware/main/ct_trend.c

หน้า watchlist ทุกหน้า (คริปโต หุ้น) บอกทิศทางด้วยกติกาชุดเดียวกัน อยู่ที่นี่ที่เดียว
เพราะมันเป็นสัญญากับผู้ใช้ ไม่ใช่รายละเอียดของหน้าใดหน้าหนึ่ง: ลูกศรที่ชี้คนละแบบ
ระหว่างสองหน้าคือจอที่ต้องอ่านสองครั้งเพื่อรู้เรื่องเดียวกัน

สีอย่างเดียวไม่พอ: ตาบอดสีแดง-เขียวคือคนกลุ่มใหญ่ที่สุดที่ *ต้อง* แยกกำไรกับขาดทุนออก
โดยไม่อ่านตัวเลข รูปทรงจึงเป็นตัวบอกหลัก ส่วนสีเป็นตัวช่วยที่สอง
"""

from __future__ import annotations

from .config import PAL
from .rects import Rect, RectList


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


def arrow(change: int, connected: bool = True) -> RectList:
    """ลูกศรขึ้น/ลง — ต้องตรงกับ ct_trend_arrow() ใน ct_trend.c"""
    color = tone(change, connected)

    if change == 0:
        # นิ่งคือขีดเดียว ไม่ใช่ลูกศรแบนๆ — สามเหลี่ยมที่ชี้ไปไหนไม่ได้อ่านเป็นลูกศรเสีย
        return [Rect(0.5, 1.75, 3.0, 0.5, color)]
    out: RectList = []
    for i in range(3):
        w = 1.0 + i
        x = 2.0 - w / 2.0
        y = 0.5 + i if change > 0 else 3.5 - i - 1.0
        out.append(Rect(x, y, w, 1.0, color))
    return out


def pct_text(change: int) -> str:
    """เปอร์เซ็นต์คูณสิบ -> ข้อความที่มีเครื่องหมายเสมอ

    "+1.1%" กับ "1.1%" ต่างกันตรงที่อันหลังต้องอ่านสีหรือลูกศรก่อนถึงจะรู้ว่าขึ้นหรือลง
    ต้องตรงกับ ct_trend_pct_text() ใน ct_trend.c
    """
    sign = "+" if change > 0 else ("-" if change < 0 else "")
    return f"{sign}{abs(change) // 10}.{abs(change) % 10}%"
