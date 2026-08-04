"""มาสคอตจิ๋วที่ทุกหน้าซึ่งไม่ใช่หน้ามาสคอตมีเหมือนกัน — พอร์ตคู่กับ firmware/main/ct_mini.c

อยู่ที่นี่ที่เดียวด้วยเหตุผลเดียวกับบรรทัดอายุใน `age.py`: มันเป็นสัญญากับผู้ใช้ ไม่ใช่
รายละเอียดของหน้าใดหน้าหนึ่ง ผู้ใช้ที่ปัดจากหุ้นไปปฏิทินต้องเจอสถานะ session ที่มุมเดิม
ด้วยขนาดเดิม หน้าที่คัดลอกโค้ดนี้ไปไว้ในตัวเองจะดริฟต์ทีละพิกเซลจนต้องค้นหาทุกครั้งที่ปัด
"""

from __future__ import annotations

from PIL import ImageDraw

from . import mascot
from .config import L
from .props import BOX_X0, BOX_X1, BOX_Y1
from .rects import scaled
from .render import draw_rects


def draw_mini(draw: ImageDraw.ImageDraw, state: str | None, connected: bool,
              phase: float, cycle: int) -> None:
    """rect list ชุดเดิมที่ย่อลง ไม่มีอาร์ตใหม่ ไม่มีท้องฟ้า ไม่มี prop ที่ต้องเว้นที่ให้

    `state=None` คือไม่มี session เลย ซึ่งคือท่าหลับ — ต่างจากการไม่วาดอะไรเลย

    อายุขั้นต่ำของ pose ถูกบังคับที่ daemon อยู่แล้ว (Timings.minPose) ที่นี่จึงวาดสิ่งที่
    snapshot บอกตรงๆ และได้กติกาเดียวกันมาฟรี
    """
    # ไม่มี Mac = ไม่มีมาสคอต ซึ่งต่างจากมาสคอตที่หลับ (= ไม่มี session)
    if not connected:
        return
    px = L.slots.unit_px
    scale = L.page.mini_unit_px / px
    rects = scaled(mascot.build_centered(state or "sleeping", phase, True, cycle), scale, scale)
    # ปัดเป็นจำนวนเต็มแบบเดียวกับฝั่งบอร์ด (lv_obj_set_size กินพิกเซลเต็มเท่านั้น)
    # ปล่อยให้ที่นี่เป็นทศนิยมแล้วมาสคอตจะเยื้องจากบนจอจริงหนึ่งพิกเซล
    mini_w = int((BOX_X1 - BOX_X0) * L.page.mini_unit_px) + 1
    ox = L.screen.width - L.page.mini_right - mini_w - BOX_X0 * scale * px
    oy = L.page.mini_bottom_y - BOX_Y1 * scale * px
    draw_rects(draw, rects, px, ox, oy)
