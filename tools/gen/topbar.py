"""แถบบนของ *ทุก* หน้า — พอร์ตคู่กับ firmware/main/ct_topbar.c

อยู่ที่นี่ที่เดียวด้วยเหตุผลเดียวกับ `age.py` และ `mini.py`: เวลา โควตา และสถานะลิงก์
เป็นสัญญากับผู้ใช้ ไม่ใช่รายละเอียดของหน้าใดหน้าหนึ่ง คนที่ปัดจากหุ้นไปปฏิทินต้องเจอ
คำตอบของ "กี่โมง · ใช้โควตาไปเท่าไร · จอยังคุยกับ Mac อยู่ไหม" ที่เดิมเสมอ

กติกาที่ต้องเป็นจริงพร้อมกันทั้งสองฝั่ง: **แถบไม่พูดซ้ำสิ่งที่หน้านั้นแสดงใหญ่กว่าอยู่แล้ว**
หน้ามาสคอตตอน idle มีนาฬิกาตัวใหญ่กลางจอ และตอนไม่มีการ์ดมีแผงโควตาเต็ม สองอย่างนั้น
ชนะแถบเสมอ ส่วนหน้าอื่นไม่เคยแสดงเวลาหรือโควตาเอง จึงได้ครบตลอด
"""

from __future__ import annotations

from dataclasses import dataclass

from PIL import ImageDraw

from . import screen
from .config import L, PAL
from .render import quantize565

# ไอคอนลิงก์ — ต้องตรงกับ ICON_* ใน firmware/main/ct_topbar.c เป๊ะ
# BLE = แท่งไต่ขึ้น (ทางหลัก) · WiFi = คลื่นซ้อน (ทางสำรอง) · ขาด = ขีดเดียวจางๆ
# สามรูปทรงคนละวงศ์ ไม่ใช่รูปเดียวคนละสี — จอนี้ถูกมองจากอีกฝั่งห้องเป็นหลัก
_ICON_BLE = [(0, 6, 3, 3), (4, 3, 3, 6), (8, 0, 3, 9)]
_ICON_WIFI = [(0, 0, 11, 2), (2, 3, 7, 2), (4, 6, 3, 3)]
_ICON_NONE = [(1, 4, 9, 2)]


@dataclass(slots=True)
class Bar:
    """สิ่งที่แถบวาด — ทั้งหมดมาจาก snapshot ของหน้ามาสคอต ไม่ว่าหน้าไหนจะแสดงอยู่

    หน้ามาสคอตปิดไม่ได้ (`Pages.swift`) แถบจึงมีแหล่งข้อมูลเสมอ ไม่มีสภาพ "ไร้เวลาถาวร"
    """

    clock: str = "14:32"
    # ลิงก์ BLE ขึ้นอยู่ไหม — None = เหมือน connected (ฉากที่คุยกันทาง BLE ล้วน)
    ble: bool | None = None
    wifi: bool = False
    # session ที่ล้นจากสามช่องของหน้ามาสคอต — ยังมีความหมายบนหน้าอื่น ("มีอะไรรออยู่")
    overflow: int = 0
    # เคยได้ตัวเลขโควตามาไหม — แยกจาก `pct` เพราะ None คือ "ไม่รู้ค่า" ซึ่งเป็นคนละเรื่อง
    has_usage: bool = False
    # หน้าต่าง 5 ชม. เท่านั้น ตัวที่ขยับเร็วพอจะเปลี่ยนการตัดสินใจภายในวันเดียว
    pct: int | None = None
    # วินาทีถึงรีเซ็ต — บอร์ดนับถอยลงเอง ไม่ได้มากับ snapshot ทุกวินาที
    # มีอยู่ที่นี่เพราะแถบบนต้องตอบด้วยภาษาเดียวกับแผงเต็ม ไม่ใช่แค่เปอร์เซ็นต์เปล่าๆ
    remaining: int | None = None

    def ble_link(self, connected: bool) -> bool:
        return connected if self.ble is None else self.ble


def _link_icon(draw: ImageDraw.ImageDraw, bar: Bar, connected: bool) -> None:
    if bar.ble_link(connected):
        parts, col = _ICON_BLE, PAL.good
    elif bar.wifi:
        parts, col = _ICON_WIFI, PAL.accent
    else:
        parts, col = _ICON_NONE, PAL.text_dim
    x0 = L.screen.width - 6 - L.topbar.link_icon_w
    y0 = (L.topbar.height - L.topbar.link_icon_h) // 2
    for x, y, w, h in parts:
        draw.rectangle([x0 + x, y0 + y, x0 + x + w - 1, y0 + y + h - 1],
                       fill=quantize565(col))


def draw(draw_: ImageDraw.ImageDraw, bar: Bar, *, page: str, connected: bool,
         page_shows_clock: bool = False, page_shows_usage: bool = False) -> None:
    """`page` คือชื่อหน้าที่แสดงอยู่ (`gen/pages.py:LABELS`) — ผู้เรียกคือหน้านั้นเอง

    ชื่อหน้าอยู่ตรงที่เดิมกับที่เคยเป็นชื่ออุปกรณ์/IP: ผู้ใช้ที่เห็นจอหมุนเองต้องรู้ว่ากำลังดู
    อะไรอยู่โดยไม่ต้องตีความจากเนื้อหา ส่วน IP ย้ายไปอยู่ที่หน้าตั้งค่าบน Mac ที่เดียว
    — มันมีค่าตอน setup ซึ่งคือตอนที่นั่งอยู่หน้า Mac พอดี
    """
    h = L.topbar.height
    draw_.rectangle([0, 0, L.screen.width - 1, h - 1], fill=quantize565(PAL.bg_slot))
    dot = PAL.good if connected else PAL.gray
    draw_.rectangle([6, h // 2 - 3, 11, h // 2 + 2], fill=quantize565(dot))
    # ป้ายบอกว่ากำลังดูหน้าไหน ส่วนสีบอกว่าข้อมูลสดไหม — สองคำถามคนละอัน
    # `no link` ชนะชื่อหน้าเพราะมันคือสิ่งเดียวบนแถบที่ต้องอ่านเป็น *คำ* จุดเทากับไอคอน
    # ขีดเดียวเป็นสัญญาณเงียบที่คนเหลือบผ่านแล้วไม่ทันสังเกต และตัวเลขที่ค้างบนหน้าย่อย
    # (ราคา อุณหภูมิ) อ่านผิดง่ายที่สุดตอนนั้นพอดี (ต้องตรงกับ ct_topbar_set_link)
    draw_.text((17, h // 2), page if connected else "no link", font=screen.font(11),
               fill=quantize565(PAL.text if connected else PAL.text_dim), anchor="lm")
    _link_icon(draw_, bar, connected)

    # ไอคอนลิงก์จองขวาสุดไว้ถาวร ทุกอย่างบนแถบจึงเริ่มนับจากซ้ายของมัน
    right = L.screen.width - 6 - L.topbar.link_icon_w - L.topbar.link_icon_gap
    if not page_shows_clock:
        # เลขที่ค้างเป็นเทา ไม่ใช่ `--:--` — เทา = ค้าง ไม่ใช่หาย เหมือนมาสคอตที่หลุด
        # และเหมือนสัญลักษณ์อากาศที่หลุด ส่วนคำว่าทำไมอยู่ที่ป้ายซ้ายแล้ว
        draw_.text((right, h // 2), bar.clock, font=screen.font(12),
                   fill=quantize565(PAL.text if connected else PAL.gray), anchor="rm")
        right -= 38
    if bar.overflow:
        draw_.text((right, h // 2), f"+{bar.overflow}", font=screen.font(11),
                   fill=quantize565(PAL.accent), anchor="rm")
        right -= 26

    # โควตาบนแถบไม่มีป้ายกำกับเพราะมีค่าเดียว ไม่ต้องบอกว่าตัวไหน — เอาพื้นที่นั้นไปทำ
    # แถบสั้นแทน ซึ่งเหลือบแล้วรู้ทันทีโดยไม่ต้องอ่านตัวเลข
    # หลุดลิงก์แล้วหายทั้งชุด (ไม่ใช่แค่หรี่เหมือนนาฬิกา): เปอร์เซ็นต์ที่ค้างอ่านผิดเป็นเงินได้
    # ส่วนเวลาที่ผิดรู้ทันที — ตรงกับ Screen.shown_usage()
    if not connected or not bar.has_usage or page_shows_usage:
        return
    # ตัวเลขเดียวกันต้องพูดภาษาเดียวกันทั้งสองที่ — สีมาจาก `usage_bar_color` ตัวเดียว
    # กับที่แผงเต็มใช้ ไม่ใช่ `usage_color` ที่ดูแค่เกณฑ์ % · แถบบนที่ยังเขียวอยู่ขณะที่
    # แผงเต็มแดงเพราะใช้เร็วเกินเวลา คือจอที่บอกสองอย่างเกี่ยวกับเลขตัวเดียวกัน
    u = screen.Usage("", L.usage.session_window, bar.pct, bar.remaining)
    col = screen.usage_bar_color(u)
    draw_.text((right, h // 2), "--%" if bar.pct is None else f"{bar.pct}%",
               font=screen.font(11), fill=quantize565(col), anchor="rm")
    right -= 30

    # แถบสั้นให้เหลือบแล้วรู้ทันทีว่าเหลือเท่าไร โดยไม่ต้องอ่านตัวเลข
    # สูง 6px บนแถบ 22px อ่านออก — ที่อ่านไม่ออกคือแถบบางในแผงเต็ม ไม่ใช่ตรงนี้
    # กรอบขาวรอบราง — พื้นรางสีเดียวกับพื้นหลังจอ ทำให้ส่วนที่ยังไม่ถูกใช้กลืนหาย
    # เห็นแต่ "ใช้ไปเท่าไร" ไม่เห็น "เหลือเท่าไร" กรอบตีขอบให้รู้ความยาวเต็ม
    bw, bh = 34, 6
    ox, oy = right - bw - 2, h // 2 - (bh + 2) // 2
    draw_.rectangle([ox, oy, ox + bw + 1, oy + bh + 1],
                    fill=quantize565(PAL.bg), outline=quantize565(PAL.outline), width=1)
    bx, by = ox + 1, oy + 1
    if bar.pct is not None:
        fill_w = round(bw * min(max(bar.pct, 0), 100) / 100)
        if fill_w:
            draw_.rectangle([bx, by, bx + fill_w - 1, by + bh - 1], fill=quantize565(col))

    # ขีด pace — แผงเต็มมีมาตลอด แถบบนไม่มี ทั้งที่เป็นตัวเลขตัวเดียวกัน · "88%"
    # ที่เพิ่งเริ่มหน้าต่างกับ "88%" ที่เหลืออีกสิบนาทีเป็นคนละเรื่องกันสิ้นเชิง และ
    # แถบเปล่าตอบไม่ได้ · สีบอกแทนไม่ได้เพราะ alert กับ good เทาเท่ากันเมื่อเป็นขาวดำ
    #
    # ขีดหนาขึ้นตอนใช้เร็วเกิน เหมือนแผงเต็ม — สีบอกแทนไม่ได้เมื่อภาพเป็นขาวดำ
    # (alert L 0.30 กับ good L 0.33 เทาเท่ากัน) ความหนาคือแกนที่ไม่พึ่งสีเลย
    #
    # ในกรอบ 34px ขีดต้องไม่ทับกรอบขาวเอง ไม่งั้นตอนต้น/ปลายหน้าต่างมันหายไปกับขอบ
    # จึงหนีบไว้ให้เหลือขอบข้างละ 1px — ตำแหน่งเพี้ยนหนึ่งพิกเซลดีกว่าขีดที่มองไม่เห็น
    if bar.remaining is not None and bar.remaining > 0:
        window = L.usage.session_window
        elapsed = max(0, min(window, window - bar.remaining))
        # "over" มาจากสูตรตรงๆ ไม่ใช่จากสีที่ได้ — สีแดงมาจากเกณฑ์ % ได้ด้วย
        # ขีดหนาต้องแปลว่า "เร็วเกินเวลา" อย่างเดียว ไม่งั้นสองแกนก็เล่าเรื่องเดียวกันซ้ำ
        half = 1 if bar.pct is not None and bar.pct * window > elapsed * 100 else 0
        mx = round((bw - 1) * elapsed / window)
        mx = min(max(mx, half + 1), bw - 2 - half)
        draw_.rectangle([bx + mx - half, by, bx + mx + half, by + bh - 1],
                        fill=quantize565(PAL.outline))
