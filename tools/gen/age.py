"""สิ่งที่ทุกหน้าซึ่งไม่ใช่มาสคอตมีเหมือนกัน — พอร์ตคู่กับ firmware/main/ct_age.c

บรรทัด data age เป็นสัญญากับผู้ใช้ ไม่ใช่รายละเอียดของหน้าใดหน้าหนึ่ง: ทุกหน้าบอกอายุ
ข้อมูลด้วยถ้อยคำเดียวกัน ที่ตำแหน่งเดียวกัน และขึ้นคำว่า stale ด้วยเกณฑ์รูปเดียวกัน
หน้าที่คัดลอกโค้ดนี้ไปไว้ในตัวเองจะดริฟต์ทีละคำจนผู้ใช้อ่านสองหน้าไม่เหมือนกัน
"""

from __future__ import annotations

from PIL import ImageDraw

from . import screen
from .config import L, PAL


def age_text(secs: int) -> str:
    """อายุข้อมูล -> ข้อความสั้นที่สุดที่ยังบอกได้ว่าควรเชื่อแค่ไหน"""
    if secs < 60:
        return "updated just now"
    if secs < 3600:
        return f"updated {secs // 60}m ago"
    if secs < 86400:
        return f"updated {secs // 3600}h {(secs % 3600) // 60:02d}m ago"
    return f"updated {secs // 86400}d ago"


def is_stale(secs: int, refresh_s: int) -> bool:
    """รอบดึงเป็นของแต่ละหน้า ส่วนตัวคูณเป็นของทุกหน้า"""
    return secs > refresh_s * L.page.stale_factor


def draw_age(draw: ImageDraw.ImageDraw, secs: int, refresh_s: int) -> None:
    stale = is_stale(secs, refresh_s)
    text = age_text(secs)
    screen.line(draw, (L.page.age_x, L.page.age_y + 6),
                f"STALE - {text}" if stale else text, pil=10, board=12,
                fill=PAL.alert if stale else PAL.text_dim, anchor="lm")
