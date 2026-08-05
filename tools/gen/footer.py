"""ฐานของทุกหน้า — พอร์ตคู่กับ firmware/main/ct_footer.c

อยู่ที่นี่ที่เดียวด้วยเหตุผลเดียวกับ `topbar.py`: คนที่ปัดจากหุ้นไปปฏิทินต้องเจอคำตอบของ
"ข้อมูลเก่าแค่ไหน · session เป็นไง · จอกำลังจะทำอะไรต่อ" ที่เดิมเสมอ หน้าที่คัดลอกโค้ดนี้
ไปไว้ในตัวเองจะดริฟต์ทีละพิกเซลจนต้องค้นหาทุกครั้งที่ปัด

โมดูลนี้เป็นเจ้าของ *แถบ* ส่วนของข้างในยังเป็นของเดิม: `age.py` เขียนบรรทัดอายุ
`mini.py` วาดมาสคอต ทั้งสองยังทดสอบและแก้ได้แยกกัน ที่รวมมาที่นี่คือการจัดวางเท่านั้น

**pip อยู่ทุกหน้า รวมหน้ามาสคอต** ส่วนแถบกับมาสคอตจิ๋วไม่ขึ้นหน้ามาสคอต — ที่นั่น
มาสคอตตัวจริงอยู่กลางจอแล้ว และพื้นดินกินถึงขอบล่าง แถบทึบจะตัดเส้นขอบฟ้าทิ้ง
"""

from __future__ import annotations

from dataclasses import dataclass

from PIL import ImageDraw

from . import age, mini
from .config import L, PAL
from .render import quantize565

# ขอบบนของแถบ — คำนวณ ไม่ได้เก็บใน TOML เพราะมันเป็นผลของ height ตัวเดียว
# ต้องตรงกับ CT_FOOTER_TOP ใน firmware/main/ct_footer.c
TOP = L.screen.height - L.footer.height
# ศูนย์กลางแนวตั้งที่ทุกอย่างในแถบใช้ร่วมกัน — บรรทัดอายุกับ pip ต้องอยู่แนวเดียวกัน
# ไม่งั้นฐานกลับไปเป็นของสองชิ้นที่บังเอิญอยู่ด้วยกันเหมือนเดิม
MID_Y = TOP + L.footer.height // 2


@dataclass(slots=True)
class Pos:
    """ตำแหน่งในรอบหมุน — ฝั่งบอร์ดมาจาก `ct_pages_position` ฝั่งนี้ผู้เรียกใส่เอง

    `count` คือจำนวนหน้าที่ *ปัดถึงได้จริง* ไม่ใช่จำนวนหน้าในแผน: หน้าที่ยังไม่เคยได้
    เฟรมถูกข้ามตอนปัด (`in_rotation`) pip ที่นับมันด้วยคือคำสัญญาว่าปัดสองทีจะถึง
    ซึ่งไม่จริง

    `left_ms < 0` = ไม่มีนาฬิกาเดินอยู่ (ผู้ใช้ปิดรอบหมุน) ต่างจาก `left_ms == 0`
    ซึ่งคือกำลังจะพลิกเดี๋ยวนี้ — หลักเดียวกับ unknown != zero
    """

    index: int = 0
    count: int = 0
    left_ms: int = -1
    total_ms: int = 0

    def fraction(self) -> float:
        """ส่วนที่ยังเหลือของราง 0..1 — ปิดรอบหมุนได้เต็มราง ไม่ใช่รางเปล่า

        รางเปล่ากับรางเต็มต้องหมายถึงคนละเรื่อง: เปล่า = อีกแป๊บเดียวจะพลิก
        เต็มค้าง = จะไม่พลิกเลย ถ้าปิดรอบหมุนแล้วได้รางเปล่า มันจะอ่านว่า "กำลังจะพลิก"
        ค้างอยู่อย่างนั้นทั้งคืน
        """
        if self.left_ms < 0 or self.total_ms <= 0:
            return 1.0
        return min(max(self.left_ms / self.total_ms, 0.0), 1.0)


def band(draw: ImageDraw.ImageDraw) -> None:
    """พื้น + เส้นขอบบน — เส้นคือตัวที่ทำงาน พื้นเป็นตัวเสริม (ดู `[footer]` ใน layout.toml)"""
    w = L.screen.width
    draw.rectangle([0, TOP, w - 1, L.screen.height - 1], fill=quantize565(PAL.bg_slot))
    draw.rectangle([0, TOP, w - 1, TOP + L.footer.rule_h - 1],
                   fill=quantize565(PAL.gray_dark))


def pips(draw: ImageDraw.ImageDraw, pos: Pos, *, has_mini: bool = True) -> None:
    """จุดบอกหน้า + รางเวลาของหน้าปัจจุบัน

    หน้าเดียวไม่มี pip: ไม่มีที่ให้ปัดไป จุดเดียวโดดๆ จึงเป็นคำเชิญที่พาไปเจอความว่าง

    `has_mini=False` คือหน้ามาสคอต ซึ่งไม่มีตัวจิ๋วให้หลบ แถวจึงเลื่อนไปชิดขอบขวาแทน
    """
    n = pos.count
    if n < 2 or not (0 <= pos.index < n):
        return
    f = L.footer
    # ความกว้างรวมไม่ขึ้นกับว่าหน้าไหนกำลังแสดง (กว้างหนึ่ง แคบ n-1 เสมอ) แถวจึงไม่
    # ขยับซ้ายขวาตอนหมุน — ที่ขยับคือ pip กว้างที่ไหลไปตามตำแหน่ง ซึ่งคือสิ่งที่ต้องอ่าน
    # แถวเกาะขอบขวาของฐาน ส่วนมาสคอตจิ๋วเป็นสิ่งที่มาแทนที่ขอบนั้นเมื่อมันมีอยู่
    total = f.pip_cur_w + (n - 1) * f.pip_dot_w + (n - 1) * f.pip_gap
    right = (mini.mini_box()[0] - f.pip_right_gap if has_mini
             else L.screen.width - f.mini_right)
    x = right - total
    y = MID_Y - f.pip_h // 2
    for i in range(n):
        if i != pos.index:
            draw.rectangle([x, y, x + f.pip_dot_w - 1, y + f.pip_h - 1],
                           fill=quantize565(PAL.gray_dark))
            x += f.pip_dot_w + f.pip_gap
            continue
        # ราง (สีเดียวกับจุดอื่น = เฟอร์นิเจอร์ชุดเดียวกัน) แล้วเติมจากซ้ายด้วยสีมาสคอต
        # ภาษาเดียวกับแถบโควตาบนแถบบน: ราง + ส่วนที่เติม ไม่ใช่แท่งที่หดตัว
        draw.rectangle([x, y, x + f.pip_cur_w - 1, y + f.pip_h - 1],
                       fill=quantize565(PAL.gray_dark))
        fill_w = round(f.pip_cur_w * pos.fraction())
        if fill_w:
            draw.rectangle([x, y, x + fill_w - 1, y + f.pip_h - 1],
                           fill=quantize565(PAL.clay))
        x += f.pip_cur_w + f.pip_gap


def plinth(draw: ImageDraw.ImageDraw) -> None:
    """แท่นใต้ฝ่าเท้ามาสคอตจิ๋ว — ผู้เรียกเช็ก `connected` มาแล้ว

    ไม่มี Mac = ไม่มีมาสคอต = ไม่มีแท่น แท่นเปล่าอ่านว่า "ตัวหายไปไหน" ซึ่งเป็นคำถามที่
    บรรทัด `no link` บนแถบบนตอบไปแล้ว
    """
    f = L.footer
    x, _, w, _ = mini.mini_box()
    draw.rectangle([x - f.plinth_pad, f.mini_bottom_y,
                    x + w - 1 + f.plinth_pad, f.mini_bottom_y + f.plinth_h - 1],
                   fill=quantize565(PAL.gray))


def draw(draw_: ImageDraw.ImageDraw, pos: Pos, *, secs: int, refresh_s: int,
         state: str | None, connected: bool, phase: float, cycle: int,
         frozen: str | None = None, has_frame: bool = True) -> None:
    """ฐานเต็มใบของหน้าที่ไม่ใช่มาสคอต — เรียกเป็นสิ่งสุดท้ายของหน้า

    `has_frame=False` คือหน้าที่ยังไม่เคยได้ข้อมูล: ไม่มีอายุให้บอก แต่ยังมีแถบ มี pip
    และมีมาสคอต — สถานะ session กับตำแหน่งในรอบหมุนไม่ได้ขึ้นกับว่าหน้านี้มีตัวเลขให้ดูหรือยัง
    """
    band(draw_)
    if connected:
        plinth(draw_)
    mini.draw_mini(draw_, state, connected, phase, cycle)
    if has_frame:
        age.draw_age(draw_, (L.footer.age_x, L.footer.age_y), secs, refresh_s, frozen)
    pips(draw_, pos)
