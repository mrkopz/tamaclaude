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


def gap_text(secs: int) -> str:
    """ช่วงเวลาเปล่าๆ ไม่มีคำว่า updated — ใช้ตอบ "หลุดลิงก์มานานเท่าไร"

    อยู่คู่กับ `age_text` เพราะเป็นคำถามเดียวกัน ("ของชิ้นนี้เก่าแค่ไหน") คนละประโยค
    แยกไปเขียนใหม่ในหน้ามาสคอตเมื่อไร การปัดเศษนาทีของสองที่จะต่างกันเมื่อนั้น
    วินาทีโผล่เฉพาะนาทีแรก: ต่ำกว่านั้นคือการหลุดสั้นๆ ที่ต่อกลับเองได้ ตัวเลขที่เดินทีละ
    วินาทีบอกว่ามันเพิ่งเกิด ซึ่งเป็นคนละเรื่องกับ "หายไปตั้งแต่เมื่อวาน"
    """
    secs = max(secs, 0)
    if secs < 60:
        return f"{secs}s"
    if secs < 3600:
        return f"{secs // 60}m"
    if secs < 86400:
        return f"{secs // 3600}h {(secs % 3600) // 60:02d}m"
    return f"{secs // 86400}d {(secs % 86400) // 3600}h"


def is_stale(secs: int, refresh_s: int) -> bool:
    """รอบดึงเป็นของแต่ละหน้า ส่วนตัวคูณเป็นของทุกหน้า"""
    return secs > refresh_s * L.page.stale_factor


def draw_age(draw: ImageDraw.ImageDraw, secs: int, refresh_s: int,
             frozen: str | None = None) -> None:
    """`frozen` = เหตุผลที่ตัวเลขชุดนี้ *ควร* ค้าง เช่น "market closed"

    หน้าที่รู้ว่าข้อมูลของมันหยุดโดยชอบธรรมต้องไม่ตะโกนว่า stale: ราคาหุ้นตอนตีสองเก่า
    สิบชั่วโมงเป็นเรื่องปกติ ส่วนราคาคริปโตที่เก่าสิบชั่วโมงคือท่อพัง คำว่า stale จึงต้อง
    หมายถึงอย่างหลังเสมอ ไม่งั้นมันจะกลายเป็นคำที่ผู้ใช้เรียนรู้ที่จะมองข้าม
    """
    stale = is_stale(secs, refresh_s) and frozen is None
    text = age_text(secs)
    if frozen is not None:
        text = f"{text}  -  {frozen}"
    screen.line(draw, (L.page.age_x, L.page.age_y + 6),
                f"STALE - {text}" if stale else text, pil=10, board=12,
                fill=PAL.alert if stale else PAL.text_dim, anchor="lm")
