"""หน้าปฏิทินทั้งใบ — พอร์ตคู่กับ firmware/main/ct_calendar_ui.c

ค่าคงที่ทั้งหมดมาจาก layout.toml ชุดเดียวกับ firmware ถ้าภาพที่นี่ต่างจากบนบอร์ด
แปลว่าเป็นบั๊ก renderer ไม่ใช่ค่าคงที่ไม่ตรงกัน
"""

from __future__ import annotations

from dataclasses import dataclass, field

from PIL import Image, ImageDraw

from . import age, footer, pages, screen, sky, topbar
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


def countdown_text(mins: int | None) -> str | None:
    """นาทีที่เหลือ -> บรรทัดใต้ตัวเลขเวลา · None = ไม่มีอะไรจะนับ (นัดทั้งวัน)

    ต้องตรงกับ countdown_text() ใน ct_calendar_ui.c

    "09:30" ต้องเอาไปลบกับนาฬิกาในหัวก่อนถึงจะรู้ว่าต้องลุกตอนไหน ส่วน "in 42 min"
    ไม่ต้อง — หน้านี้ตอบคำถาม *เหลืออีกนานแค่ไหน* ตัวเลขนาฬิกาเป็นของประกอบ
    """
    if mins is None or mins > L.calendar.countdown_max_min:
        return None
    if mins <= 0:
        return "now"
    if mins < 60:
        return f"in {mins} min"
    return f"in {mins // 60}h {mins % 60:02d}m"


def remaining_min(mins: int | None, age: int) -> int | None:
    """นาทีที่เหลือ *ตอนนี้* — เฟรมมาทุก 5 นาที ตัวเลขในเฟรมจึงเก่าเท่าอายุของมัน

    บอร์ดนับต่อเองจากอายุข้อมูลที่มีอยู่แล้ว ไม่ต้องมีตัวจับเวลาใบใหม่และไม่ต้องมีเวลา
    สัมบูรณ์บนสาย — กติกาเดียวกับที่หน้าอื่นใช้กับบรรทัด "updated ... ago"
    """
    return None if mins is None else mins - age // 60


@dataclass(slots=True)
class Calendar:
    """หน้าปฏิทินหนึ่งใบ — `has_frame=False` คือยังไม่เคยได้ข้อมูลเลย"""

    events: list[Appointment] = field(default_factory=list)
    state: int = OK
    age: int = 35
    # นาทีจนถึงนัดแรก ตอนที่ Mac สร้างเฟรม — None = นัดทั้งวัน ซึ่งไม่มีอะไรให้นับ
    mins: int | None = None
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
        screen.line(draw, (L.screen.width // 2, L.calendar.date_sub_y),
                    MESSAGES[EMPTY][1], pil=10, board=12, fill=PAL.text_dim, anchor="mt")
        return

    state = c.state if c.has_frame else NO_CALENDARS
    head, sub = MESSAGES.get(state, MESSAGES[NO_CALENDARS])
    screen.line(draw, (L.calendar.time_x, L.calendar.empty_y), head,
                pil=12, board=14, fill=PAL.text, anchor="lt")
    screen.line(draw, (L.calendar.time_x, L.calendar.empty_sub_y), sub,
                pil=10, board=12, fill=PAL.text_dim, anchor="lt")


def hero_sub(c: Calendar) -> str | None:
    """ช่องขวาของการ์ด — ตัวนับถอยหลัง หรือ None เมื่อไม่มีอะไรจะนับ

    ต้องตรงกับ hero_sub() ใน ct_calendar_ui.c

    ตัวนับถอยหลังเป็นคำกล่าวเกี่ยวกับ *ตอนนี้* ท่อที่หยุดเดินพูดแบบนั้นไม่ได้: เฟรมที่ค้าง
    มาห้าสิบนาทีจะนับจนถึง "now" เองแล้วค้างอยู่ตรงนั้น ซึ่งอ่านว่านัดกำลังเริ่มทั้งที่ไม่มี
    ใครรู้ · ช่องนี้จึงว่างได้ ต่างจากชื่อวันซึ่งจริงเสมอและอยู่ติดเวลาตลอด (ADR-0002)
    """
    if not c.connected or age.is_stale(c.age, L.calendar.refresh_s):
        return None
    return countdown_text(remaining_min(c.mins, c.age))


# พื้นการ์ดตามช่วงเวลาของนัด — ต้องตรงกับ CARD_* ใน ct_calendar_ui.c
# ทุกใบเป็น (พื้น, ขอบ, ตัวหนังสือ, ตัวหรี่, สีเน้น) ครบชุดในที่เดียว ไม่ใช่พื้นอย่างเดียว
# แล้วให้ตัวหนังสือไปเดาเอาเอง: ใบกลางวันพื้นสว่าง ตัวหนังสือทั้งใบต้องกลับขั้ว
CARD = {
    "night": (PAL.cal_sky_night, PAL.cal_edge_night, PAL.text, PAL.cal_dim, PAL.cal_accent),
    "dawn": (PAL.cal_sky_dawn, PAL.cal_edge_dawn, PAL.text, PAL.cal_dim, PAL.cal_accent),
    "day": (PAL.cal_sky_day, PAL.cal_edge_day, PAL.ink, PAL.ink_dim,
            PAL.cal_ink_accent),
    "dusk": (PAL.cal_sky_dusk, PAL.cal_edge_dusk, PAL.text, PAL.cal_dim, PAL.cal_accent),
}
# ก้นการ์ด · ดาวและเมฆ · ดวง — ต้องตรงกับ CARD_LO/CARD_GLOW/CARD_DISC ใน ct_calendar_ui.c
CARD_LO = {"night": PAL.cal_lo_night, "dawn": PAL.cal_lo_dawn, "day": PAL.cal_lo_day,
           "dusk": PAL.cal_lo_dusk}
CARD_GLOW = {"night": PAL.cal_glow_night, "dawn": PAL.cal_glow_dawn,
             "day": PAL.cal_glow_day, "dusk": PAL.cal_glow_dusk}
CARD_DISC = {"night": PAL.cal_disc_night, "dawn": PAL.cal_disc_dawn,
             "day": PAL.cal_disc_day, "dusk": PAL.cal_disc_dusk}


def card_phase(c: Calendar, first: Appointment) -> str | None:
    """ช่วงเวลาที่พื้นการ์ดต้องใช้ — None = ไม่มีฉาก ใช้พื้นการ์ดกลางเดิม

    ต้องตรงกับ card_phase() ใน ct_calendar_ui.c

    เวลาของ *นัด* ก่อน ไม่ใช่เวลาตอนนี้ — การ์ดคือช่องหน้าต่างที่มองไปยังชั่วโมงที่นัดจะเกิด
    นัดทั้งวันไม่มีชั่วโมงให้ดู ("all day" อ่านเป็นเวลาไม่ได้) จึงตกไปใช้นาฬิกาบนแถบบน:
    ฟ้าของตอนนี้ยังจริงกว่าการเดาว่านัดทั้งวันเกิดตอนเที่ยง

    หลุดลิงก์แล้วไม่มีฉากเลย กติกาเดียวกับฟ้าหน้ามาสคอต (`sky.draw`) — ฉากที่ยังสวยอยู่
    จะกลบสัญญาณว่าขาดการติดต่อ และโกหกเรื่องเวลาไปพร้อมกัน
    """
    if not c.connected:
        return None
    h = sky.hours(first.time)
    if h is None:
        h = sky.hours(c.bar.clock)
    return None if h is None else sky.phase_at(h)


def hero_title_top(lines: int) -> int:
    """ขอบบนของบล็อกชื่อนัดบนการ์ด เมื่อชื่อกิน `lines` บรรทัด

    ต้องตรงกับ hero_title_top() ใน ct_calendar_ui.c

    ชื่อบรรทัดเดียวถูกดันลงมากึ่งกลางที่ว่างที่เหลือ ไม่ใช่ชิดบน — ครึ่งล่างของการ์ดที่ว่าง
    เปล่าอ่านเป็นการ์ดที่โหลดไม่ครบ ส่วนการ์ดที่สูงไม่เท่ากันตามความยาวชื่อจะดันแถวล่าง
    ขึ้นลงทุกครั้งที่เฟรมใหม่มา
    """
    cal = L.calendar
    return cal.hero_title_dy + (cal.hero_title_lines - lines) * cal.hero_title_line_h // 2


def _card_sky(draw: ImageDraw.ImageDraw, phase: str, fill: str, edge: str) -> None:
    """พื้นการ์ด: ฟ้าไล่สี + ดาว + เมฆ + ดวง — ต้องตรงกับ card_sky() ใน ct_calendar_ui.c

    ทุกชิ้นวาดก่อนตัวหนังสือและไม่มีการกันพื้นที่ไว้ให้ สิ่งที่ทำให้มันไม่กวนคือค่าความต่าง
    (ดู cal_glow_* กับ cal_disc_*) ไม่ใช่ตำแหน่ง — การ์ดถูกจองไปหมดแล้วทั้งใบ

    ฝั่งบอร์ดเป็นวัตถุ LVGL ที่วางเป็นลูกของกล่องการ์ด จึงถูกตัดที่ขอบการ์ดให้เอง
    ที่นี่ต้องตัดเองด้วย `clip` เพราะ PIL วาดเลยขอบไปเฉยๆ
    """
    cal = L.calendar
    x0, y0 = cal.hero_pad, cal.hero_y
    x1, y1 = L.screen.width - cal.hero_pad - 1, cal.hero_y + cal.hero_h - 1
    hi = tuple(int(fill[i:i + 2], 16) for i in (1, 3, 5))
    lo = tuple(int(CARD_LO[phase][i:i + 2], 16) for i in (1, 3, 5))
    # ไล่ทีละแถว แล้วค่อยลง 565 ทีเดียว — LVGL ก็ผสมที่ 8 บิตแล้วค่อยแปลงเหมือนกัน
    for i in range(cal.hero_h):
        u = i / (cal.hero_h - 1)
        row = "#%02X%02X%02X" % tuple(round(a + (b - a) * u) for a, b in zip(hi, lo))
        draw.rectangle([x0, y0 + i, x1, y0 + i], fill=quantize565(row))

    # ขอบ 1px คือสิ่งที่ทำให้ใบกลางคืนยังอ่านเป็นการ์ด ทั้งที่พื้นมันเข้มพอๆ กับพื้นจอ
    # วาดก่อนองค์ประกอบ ไม่ใช่หลัง — ฝั่ง LVGL ขอบเป็นของกล่องการ์ดซึ่งวาดก่อนลูกของมัน
    # เสมอ ดวงที่จมขอบบนจึงกินขอบไปหนึ่งพิกเซลทั้งสองฝั่ง เท่ากัน
    draw.rectangle([x0, y0, x1, y1], outline=quantize565(edge), width=1)

    def clip(box: list[int]) -> list[int] | None:
        if box[2] < x0 or box[0] > x1 or box[3] < y0 or box[1] > y1:
            return None
        return [max(box[0], x0), max(box[1], y0), min(box[2], x1), min(box[3], y1)]

    glow = quantize565(CARD_GLOW[phase])
    if phase != "day":
        s = cal.card_star_px
        for sx, sy in cal.card_stars:
            box = clip([x0 + sx, y0 + sy, x0 + sx + s - 1, y0 + sy + s - 1])
            if box:
                draw.rectangle(box, fill=glow)
    if phase != "night":
        h, r = cal.card_cloud_h, cal.card_cloud_r
        for cx, cy, w in cal.card_clouds:
            # แท่งมน + ก้อนบนเยื้องซ้าย — รูปเดียวกับเมฆหน้ามาสคอต
            draw.rounded_rectangle([x0 + cx, y0 + cy, x0 + cx + w, y0 + cy + h - 1],
                                   radius=r, fill=glow)
            bx, bw = round(cx + w * 0.25), round(w * 0.45)
            draw.rounded_rectangle([x0 + bx, y0 + cy - 4, x0 + bx + bw, y0 + cy + h - 5],
                                   radius=r, fill=glow)
    # ดวงจมขอบบนไปครึ่งดวง — ครึ่งที่หายคือสิ่งที่ทำให้มันอ่านเป็นฉากที่ใหญ่กว่ากรอบ
    r = cal.card_disc_r
    dx, dy = x0 + cal.card_disc_x, y0 + cal.card_disc_y
    box = clip([dx - r, dy - r, dx + r, dy + r])
    if box:
        # PIL ไม่มี clip ให้วงกลม — วาดลงผืนย่อยแล้วปะกลับ
        img = Image.new("RGB", (x1 - x0 + 1, y1 - y0 + 1))
        sub = ImageDraw.Draw(img)
        sub.ellipse([dx - r - x0, dy - r - y0, dx + r - x0, dy + r - y0],
                    fill=quantize565(CARD_DISC[phase]))
        for px in range(box[0], box[2] + 1):
            for py in range(box[1], box[3] + 1):
                col = img.getpixel((px - x0, py - y0))
                if col != (0, 0, 0):
                    draw.point((px, py), fill=col)


def _hero(draw: ImageDraw.ImageDraw, c: Calendar, first: Appointment,
          text: str, dim: str, accent: str) -> None:
    """นัดถัดไป — การ์ดใบเดียวของหน้า และเป็นช่องหน้าต่างที่มองไปยังฟ้าของชั่วโมงที่นัดจะเกิด

    สีที่ส่งเข้ามาคือชุดของหน้า (ปกติ/เทาเมื่อหลุดลิงก์) การ์ดที่มีฉากจะเขียนทับด้วยชุด
    ของช่วงเวลาตัวเอง เพราะพื้นสว่างของใบกลางวันรับตัวหนังสือสีเดิมไม่ได้เลย
    """
    cal = L.calendar
    x0, x1 = cal.hero_pad, L.screen.width - cal.hero_pad - 1
    phase = card_phase(c, first)
    if phase is None:
        draw.rectangle([x0, cal.hero_y, x1, cal.hero_y + cal.hero_h - 1],
                       fill=quantize565(PAL.bg_slot))
    else:
        fill, edge, text, dim, accent = CARD[phase]
        _card_sky(draw, phase, fill, edge)
    draw.text((cal.hero_time_x, cal.hero_y + cal.hero_time_dy + 12), first.time,
              font=screen.font(cal.hero_time_font_pil), fill=quantize565(text), anchor="lm")
    # ชื่อวันติดเวลาและอยู่ตลอด — เวลาที่ไม่มีวันกำกับอ่านเป็นวันนี้เสมอ
    screen.line(draw, (cal.hero_day_x, cal.hero_y + cal.hero_sub_dy), first.day,
                pil=12, board=14, fill=dim, anchor="lt", max_w=cal.hero_day_w)
    sub = hero_sub(c)
    if sub is not None:
        screen.line(draw, (L.screen.width - cal.hero_sub_right, cal.hero_y + cal.hero_sub_dy),
                    sub, pil=12, board=14, fill=accent, anchor="rt", max_w=cal.hero_sub_w)
    lines = screen.wrap(draw, first.title, pil=12, board=14, max_w=cal.hero_title_w,
                        max_lines=cal.hero_title_lines)
    top = cal.hero_y + hero_title_top(len(lines))
    for i, part in enumerate(lines):
        screen.line(draw, (cal.hero_title_x, top + i * cal.hero_title_line_h),
                    part, pil=12, board=14, fill=text, anchor="lt")


def spine_bottom(rows: int) -> int:
    """ก้นสันเวลาของ `rows` แถว — ต้องตรงกับ spine_bottom() ใน ct_calendar_ui.c"""
    return L.calendar.row_y + rows * L.calendar.row_h - L.calendar.spine_pad


def _spine(draw: ImageDraw.ImageDraw, c: Calendar, rows: int) -> None:
    """เส้นตั้งที่กั้นคอลัมน์เวลากับคอลัมน์ชื่อของแถวใต้การ์ด"""
    cal = L.calendar
    draw.rectangle(
        [cal.spine_x, cal.spine_top, cal.spine_x + cal.spine_w - 1, spine_bottom(rows) - 1],
        fill=quantize565(PAL.gray_dark if c.connected else PAL.ink))


def _footer(draw: ImageDraw.ImageDraw, c: Calendar, pos: footer.Pos | None,
            phase: float, cycle: int, *, has_frame: bool = True) -> None:
    footer.draw(draw, pos or footer.Pos(), secs=c.age, refresh_s=L.calendar.refresh_s,
                state=c.mascot_state, connected=c.connected, phase=phase, cycle=cycle,
                has_frame=has_frame)


def render(c: Calendar, phase: float = 0.0, cycle: int = 0,
           pos: footer.Pos | None = None) -> Image.Image:
    img = Image.new("RGB", (L.screen.width, L.screen.height), quantize565(PAL.bg))
    draw = ImageDraw.Draw(img)
    # หน้านี้ไม่เคยแสดงเวลาหรือโควตาเอง แถบจึงพูดครบเสมอ (ดู `topbar.draw`)
    topbar.draw(draw, c.bar, page=pages.LABELS["calendar"], connected=c.connected)

    events = c.events[: L.calendar.rows] if c.has_frame and c.state == OK else []
    if not events:
        _empty(draw, c)
        _footer(draw, c, pos, phase, cycle, has_frame=c.has_frame)
        return img

    text = PAL.text if c.connected else PAL.gray
    dim = PAL.text_dim if c.connected else PAL.gray
    accent = PAL.clay if c.connected else PAL.gray

    _hero(draw, c, events[0], text, dim, accent)
    rest = events[1 : 1 + L.calendar.list_rows]
    if rest:
        _spine(draw, c, len(rest))
    cal = L.calendar
    for i, event in enumerate(rest):
        top = cal.row_y + i * cal.row_h
        # เวลาชิดซ้าย: "all day" ที่ยาวกว่า HH:MM ต้องเริ่มที่เดิม ไม่ใช่ล้นไปทางซ้าย
        screen.line(draw, (cal.time_x, top + cal.time_dy), event.time,
                    pil=12, board=cal.time_font, fill=text, anchor="lt", max_w=cal.time_w)
        # ชื่อวันอยู่ *ใต้* เวลาในคอลัมน์เดียวกัน ไม่ใช่ข้างๆ — "Tomorrow" กว้างกว่าที่ว่าง
        # ที่เหลือข้างเวลาเสมอ · ทุกแถวบอกวันของตัวเอง เคยซ่อนไว้ตอนวันไม่เปลี่ยนแล้ว
        # แถวที่ถูกซ่อนอ่านเป็น "ไม่มีวัน" ไม่ใช่ "วันเดียวกับข้างบน" ซึ่งผิดได้ทั้งสัปดาห์
        screen.line(draw, (cal.day_x, top + cal.day_dy), event.day,
                    pil=10, board=cal.day_font, fill=dim, anchor="lt", max_w=cal.day_w)
        screen.line(draw, (cal.title_x, top + cal.title_dy), event.title,
                    pil=10, board=cal.title_font, fill=text, anchor="lt", max_w=cal.title_w)

    _footer(draw, c, pos, phase, cycle)
    return img
