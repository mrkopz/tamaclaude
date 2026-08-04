"""หน้าปฏิทินทั้งใบ — พอร์ตคู่กับ firmware/main/ct_calendar_ui.c

ค่าคงที่ทั้งหมดมาจาก layout.toml ชุดเดียวกับ firmware ถ้าภาพที่นี่ต่างจากบนบอร์ด
แปลว่าเป็นบั๊ก renderer ไม่ใช่ค่าคงที่ไม่ตรงกัน
"""

from __future__ import annotations

from dataclasses import dataclass, field

from PIL import Image, ImageDraw

from . import age, mini, pages, screen, topbar
from .config import L, PAL
from .render import quantize565

# สถานะของหน้า — ต้องตรงกับ `CalendarState` ฝั่ง Swift และ `ct_calendar_state_t`
# ฝั่ง firmware ตัวเลขเดินทางบนสาย จึงเรียงใหม่ไม่ได้
OK = 0
EMPTY = 1
NEEDS_ACCESS = 2
NO_CALENDARS = 3
NOT_ASKED = 4

# สองบรรทัดของทุกสภาพที่ไม่มีนัดให้แสดง — บรรทัดบนบอกว่าเกิดอะไร บรรทัดล่างบอกว่า
# ต้องทำอะไรต่อ หน้าที่บอกแต่ปัญหาโดยไม่บอกทางออกอ่านเหมือนอุปกรณ์พัง
# ต้องตรงกับ empty_lines() ใน ct_calendar_ui.c
MESSAGES = {
    # สัปดาห์ที่ว่างใช้บรรทัดล่างเป็นคำอธิบายใต้วันที่ตัวใหญ่ ส่วนบรรทัดบนเหลือไว้สำหรับ
    # บอร์ดที่ยังไม่รู้ว่าวันนี้วันอะไร (ยังไม่เคยได้ snapshot) — ดู `_empty`
    EMPTY: ("No events", "nothing in the next 7 days"),
    NEEDS_ACCESS: ("Calendar not allowed", "allow it in System Settings > Privacy"),
    NOT_ASKED: ("Calendar not set up", "allow it from the mac app"),
    NO_CALENDARS: ("No calendars picked", "pick calendars in the mac app"),
}


@dataclass(slots=True)
class Appointment:
    """หนึ่งแถวอย่างที่มันมาถึงบอร์ด — Mac จัดรูปวันกับเวลามาแล้ว

    บอร์ดไม่มี timezone ไม่มีปฏิทิน และไม่มีนาฬิกาที่ตั้งตรง การส่งเวลาสัมบูรณ์ไปให้
    มันจัดรูปเองคือการขอให้มันเดาสามอย่างที่ Mac รู้อยู่แล้ว (ดู `CalendarFrame`)
    """

    day: str
    time: str
    title: str


@dataclass(slots=True)
class Calendar:
    """หน้าปฏิทินหนึ่งใบ — `has_frame=False` คือยังไม่เคยได้ข้อมูลเลย"""

    events: list[Appointment] = field(default_factory=list)
    state: int = OK
    age: int = 35
    # มี snapshot สดอยู่ไหม — ตรงกับ ct_calendar_ui_set_connected
    connected: bool = True
    # เคยได้ page frame ของหน้านี้แล้วหรือยัง (ADR-0002)
    has_frame: bool = True
    # ท่าของมาสคอตจิ๋วมุมจอ — None = ไม่มี session เลย ซึ่งคือท่าหลับ
    mascot_state: str | None = None
    # แถบบน — มาจาก snapshot ของหน้ามาสคอต ไม่ใช่จากเฟรมของหน้านี้ (`gen/topbar.py`)
    bar: topbar.Bar = field(default_factory=topbar.Bar)
    # วันที่วันนี้ ("Tue 4 Aug") — มาจาก snapshot ของหน้ามาสคอตเช่นกัน ไม่ได้อยู่ในเฟรม
    # ของหน้านี้: บอร์ดไม่มีปฏิทิน และ Mac ส่งวันที่มาอยู่แล้วทุกวินาที เพิ่มลงเฟรมปฏิทิน
    # ก็จะเป็นสำเนาที่เก่ากว่าอีกใบ (เฟรมนี้มาทุก 5 นาที ไม่ใช่ทุกวินาที)
    # "" = ยังไม่เคยได้ snapshot เลย
    date: str = "Tue 4 Aug"


def shows_big_date(c: Calendar) -> bool:
    """หน้านี้กำลังเป็นปฏิทินตั้งโต๊ะอยู่ไหม — ต้องตรงกับ `shows_big_date` ใน ct_calendar_ui.c

    เฉพาะสัปดาห์ที่ว่างจริงเท่านั้น สภาพที่ผิด (ไม่ได้สิทธิ์ · ยังไม่เลือกปฏิทิน) ต้องอ่าน
    เป็นคำสั่งให้ไปทำอะไรต่อ วันที่ตัวใหญ่บนหน้าแบบนั้นจะกลายเป็นเครื่องประดับที่กลบคำสั่ง
    """
    return c.has_frame and c.state == EMPTY and bool(c.date)


def _empty(draw: ImageDraw.ImageDraw, c: Calendar) -> None:
    """สภาพที่ไม่มีนัดให้แสดง — ห้ามเป็นจอเปล่าไม่ว่าด้วยเหตุใด (ADR-0002)"""
    if shows_big_date(c):
        # หลุดลิงก์แล้วเป็นเทาเหมือนนาฬิกา ไม่ใช่หายไป: วันที่ที่ค้างยังถูกเกือบตลอด
        # และรู้ทันทีที่มันผิด ต่างจากเปอร์เซ็นต์โควตา
        draw.text((L.screen.width // 2, L.calendar.date_y + 24), c.date,
                  font=screen.font(L.calendar.date_font_pil),
                  fill=quantize565(PAL.text if c.connected else PAL.gray), anchor="mm")
        screen.line(draw, (L.screen.width // 2, L.calendar.date_sub_y + 6),
                    MESSAGES[EMPTY][1], pil=10, board=12, fill=PAL.text_dim, anchor="mm")
        return

    state = c.state if c.has_frame else NO_CALENDARS
    head, sub = MESSAGES.get(state, MESSAGES[NO_CALENDARS])
    screen.line(draw, (L.calendar.time_x, L.calendar.empty_y + 7), head,
                pil=12, board=14, fill=PAL.text, anchor="lm")
    screen.line(draw, (L.calendar.time_x, L.calendar.empty_sub_y + 6), sub,
                pil=10, board=12, fill=PAL.text_dim, anchor="lm")


def render(c: Calendar, phase: float = 0.0, cycle: int = 0) -> Image.Image:
    img = Image.new("RGB", (L.screen.width, L.screen.height), quantize565(PAL.bg))
    draw = ImageDraw.Draw(img)
    # หน้านี้ไม่เคยแสดงเวลาหรือโควตาเอง แถบจึงพูดครบเสมอ (ดู `topbar.draw`)
    topbar.draw(draw, c.bar, page=pages.LABELS["calendar"], connected=c.connected)

    # มาสคอตอยู่แถบบนของทุกหน้า รวมสภาพที่ไม่มีนัดให้แสดง — สถานะ session ไม่ได้ขึ้นกับ
    # ว่าหน้านี้อ่านปฏิทินได้หรือไม่
    mini.draw_mini(draw, c.mascot_state, c.connected, phase, cycle)

    events = c.events[: L.calendar.rows] if c.has_frame and c.state == OK else []
    if not events:
        _empty(draw, c)
        if c.has_frame:
            age.draw_age(draw, c.age, L.calendar.refresh_s)
        return img

    text = PAL.text if c.connected else PAL.gray
    dim = PAL.text_dim if c.connected else PAL.gray
    for i, event in enumerate(events):
        top = L.calendar.row_y + i * L.calendar.row_h
        # เวลาชิดซ้าย: "all day" ที่ยาวกว่า HH:MM ต้องเริ่มที่เดิม ไม่ใช่ล้นไปทางซ้าย
        draw.text((L.calendar.time_x, top + L.calendar.time_dy + 12), event.time,
                  font=screen.font(L.calendar.time_font_pil), fill=quantize565(text),
                  anchor="lm")
        screen.line(draw, (L.calendar.day_x, top + L.calendar.day_dy + 6), event.day,
                    pil=10, board=12, fill=dim, anchor="lm", max_w=L.calendar.day_w)
        screen.line(draw, (L.calendar.title_x, top + L.calendar.title_dy + 7), event.title,
                    pil=12, board=14, fill=text, anchor="lm", max_w=L.calendar.title_w)

    age.draw_age(draw, c.age, L.calendar.refresh_s)
    return img
