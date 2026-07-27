"""ประกอบจอทั้งใบ 320x240 — ตัวแทนของหน้าจอจริงตอน dev

จูน layout ที่นี่ได้ทันทีโดยไม่ต้องแฟลชบอร์ด
ค่าคงที่ทั้งหมดมาจาก layout.toml ชุดเดียวกับ firmware
"""

from __future__ import annotations

from dataclasses import dataclass, field

from PIL import Image, ImageDraw, ImageFont

from . import mascot
from .config import L, PAL
from .props import BOX_X0, BOX_X1, BOX_Y1
from .render import draw_rects, quantize565

_FONTS: dict[int, ImageFont.FreeTypeFont] = {}


def font(size: int) -> ImageFont.FreeTypeFont:
    if size not in _FONTS:
        _FONTS[size] = ImageFont.load_default(size=size)
    return _FONTS[size]


@dataclass(slots=True)
class Session:
    project: str
    state: str = "idle"
    phase_offset: float = 0.0


@dataclass(slots=True)
class Card:
    title: str
    body: str
    kind: str = "info"  # info | alert | done


@dataclass(slots=True)
class Usage:
    """หนึ่งหน้าต่างโควตา — ตรงกับ `rate_limits.five_hour` / `.seven_day` ที่ Claude Code ป้อน

    `pct` และ `remaining` เป็น None แยกกันได้ — เอกสารระบุว่าแต่ละหน้าต่างหายอิสระต่อกัน
    None คือ "ไม่รู้" ไม่ใช่ศูนย์ ศูนย์เป็นค่าจริง (ADR-0001: reported, never derived)
    """

    label: str
    window: int  # ความยาวหน้าต่างเป็นวินาที — ค่าคงที่ ใช้หาตำแหน่งขีด pace
    pct: int | None = None
    remaining: int | None = None  # วินาทีถึงรีเซ็ต — บอร์ดนับถอยลงเอง


@dataclass(slots=True)
class Screen:
    sessions: list[Session] = field(default_factory=list)
    overflow: int = 0
    clock: str = "14:32"
    date: str = "Mon 27 Jul"
    connected: bool = True
    # ใหม่สุดอยู่บน — session ที่เกิน 4 ตัวไม่มีมาสคอต แต่การเตือนยังมาโผล่ตรงนี้
    cards: list[Card] = field(default_factory=list)
    # None = ไม่เคยได้ข้อมูลเลย -> ถอยไปเป็นนาฬิกาตั้งโต๊ะ ไม่ใช่โครงเปล่าที่ดูเหมือนพัง
    usage: list[Usage] | None = None


def _fit(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.FreeTypeFont, max_w: int) -> str:
    """ตัดข้อความให้พอดีความกว้าง — daemon ต้องทำแบบเดียวกันก่อนส่งบน BLE"""
    if draw.textlength(text, font=f) <= max_w:
        return text
    ell = "..."
    while text and draw.textlength(text + ell, font=f) > max_w:
        text = text[:-1]
    return text + ell


def _topbar(draw: ImageDraw.ImageDraw, s: Screen) -> None:
    h = L.topbar.height
    draw.rectangle([0, 0, L.screen.width - 1, h - 1], fill=quantize565(PAL.bg_slot))
    dot = PAL.good if s.connected else PAL.gray
    draw.rectangle([6, h // 2 - 3, 11, h // 2 + 2], fill=quantize565(dot))
    label = "claude" if s.connected else "no link"
    draw.text((17, h // 2), label, font=font(11),
              fill=quantize565(PAL.text if s.connected else PAL.text_dim), anchor="lm")
    # นาฬิกาบนแถบโผล่เมื่อพื้นที่ล่างถูกยึดไป (card หรือ usage) — ไม่ใช่ "เมื่อมี card"
    # อย่างเดิม เพราะตอนนี้มีผู้ยึดสองราย ถ้าเช็คแค่ card จะได้นาฬิกาซ้ำสองที่ในฉาก idle
    right = L.screen.width - 6
    if s.cards or s.usage:
        draw.text((right, h // 2), s.clock, font=font(12),
                  fill=quantize565(PAL.text), anchor="rm")
        right -= 38
    if s.overflow:
        draw.text((right, h // 2), f"+{s.overflow}", font=font(11),
                  fill=quantize565(PAL.accent), anchor="rm")
        right -= 26

    # การ์ดยึดพื้นที่ล่างไปแล้ว แต่โควตาไม่ควรหายไปทั้งหมด — ย่อเหลือหน้าต่าง 5 ชม.
    # อย่างเดียวมาไว้บนแถบ ไม่มีป้ายกำกับเพราะบนแถบมีค่าเดียว ไม่ต้องแยกว่าตัวไหน
    # ไม่แสดงตอนไม่มีการ์ด เพราะแผงเต็มโชว์ตัวเลขเดียวกันอยู่แล้ว
    if s.cards and s.usage:
        u = s.usage[0]
        col = usage_color(u.pct)
        pct_text = "--%" if u.pct is None else f"{u.pct}%"
        draw.text((right, h // 2), pct_text, font=font(11), fill=quantize565(col), anchor="rm")
        right -= 30

        # แถบสั้นให้เหลือบแล้วรู้ทันทีว่าเหลือเท่าไร โดยไม่ต้องอ่านตัวเลข
        # สูง 6px บนแถบ 22px อ่านออก — ที่อ่านไม่ออกคือแถบบางในแผงเต็ม ไม่ใช่ตรงนี้
        bw, bh = 34, 6
        bx, by = right - bw, h // 2 - bh // 2
        draw.rectangle([bx, by, bx + bw - 1, by + bh - 1], fill=quantize565(PAL.bg))
        if u.pct is not None:
            fill_w = round(bw * min(max(u.pct, 0), 100) / 100)
            if fill_w:
                draw.rectangle([bx, by, bx + fill_w - 1, by + bh - 1], fill=quantize565(col))


def slot_x(i: int, n: int) -> int:
    """ขอบซ้ายของ slot ที่ i เมื่อกำลังแสดง session อยู่ n ตัว

    ระยะห่างคงที่ 80px เสมอ แต่ยกทั้งกลุ่มมาไว้กึ่งกลางจอ
    สิ่งที่ต้องนิ่งคือ *ลำดับ* ซ้าย→ขวา ไม่ใช่พิกัดสัมบูรณ์ — ตัวละครไม่เคยสลับที่กัน
    มีแค่ทั้งกลุ่มเลื่อนพร้อมกันตอนมี session เข้า/ออก
    """
    return round((L.screen.width - n * L.slots.width) / 2) + i * L.slots.width


def _slot(draw: ImageDraw.ImageDraw, i: int, sess: Session | None, s: Screen,
          phase: float, cycle: int, n: int) -> None:
    sw, top, sh = L.slots.width, L.slots.top, L.slots.height
    if sess is None:
        return
    x = slot_x(i, n)
    # ไม่สลับสีพื้นหลัง slot — เส้นคั่นบางๆ พอ พื้นหลังเป็นแถบทำให้ prop
    # ของตัวหนึ่งไปตกบนพื้นของอีก slot แล้วอ่านผิดว่าเป็นของตัวข้างๆ
    if i:  # เส้นคั่นเฉพาะระหว่างตัวที่อยู่ติดกัน
        draw.rectangle([x, top + 12, x, top + sh - 24], fill=quantize565(PAL.bg_slot))

    px = L.slots.unit_px
    foot_px = top + sh - L.slots.baseline_pad
    oy = foot_px - BOX_Y1 * px
    ox = x + sw / 2 - (BOX_X0 + BOX_X1) / 2 * px

    p = phase + sess.phase_offset
    rects = mascot.build_centered(sess.state, p % 1.0, s.connected, cycle + int(p))
    draw_rects(draw, rects, px, ox, oy)

    f = font(9)
    name = _fit(draw, sess.project, f, sw - 8)
    draw.text((x + sw / 2, foot_px + 11), name, font=f,
              fill=quantize565(PAL.text if s.connected else PAL.text_dim), anchor="mm")


CARD_H = 36
CARD_GAP = 4
CARD_MAX = 3


def _card(draw: ImageDraw.ImageDraw, c: Card, y: int) -> None:
    pad, w = L.card.pad, L.screen.width
    draw.rectangle([pad, y, w - pad - 1, y + CARD_H - 1], fill=quantize565(PAL.bg_slot))
    accent = {"alert": PAL.alert, "done": PAL.good}.get(c.kind, PAL.accent)
    draw.rectangle([pad, y, pad + 2, y + CARD_H - 1], fill=quantize565(accent))

    tx = pad + 9
    tw = w - pad - 8 - tx
    ft, fb = font(12), font(10)
    draw.text((tx, y + 11), _fit(draw, c.title, ft, tw), font=ft,
              fill=quantize565(PAL.text), anchor="lm")
    draw.text((tx, y + 25), _fit(draw, c.body, fb, tw), font=fb,
              fill=quantize565(PAL.text_dim), anchor="lm")


def _cards(draw: ImageDraw.ImageDraw, cards: list[Card]) -> None:
    y = L.card.top + L.card.pad
    for c in cards[:CARD_MAX]:
        _card(draw, c, y)
        y += CARD_H + CARD_GAP


def fmt_remaining(secs: int | None) -> str:
    """วินาทีที่เหลือ -> ข้อความสั้นที่สุดที่ยังบอกได้ว่าควรรีบไหม

    ระดับความละเอียดลดลงตามระยะ: ใกล้ = นาที, ไกล = ชั่วโมง/วัน
    ที่ 0 ไม่ใช่ "0m" แต่เป็น "resetting" เพราะ % ที่ถืออยู่หมดอายุไปแล้ว
    """
    if secs is None:
        return "no data"  # `--` ลอยเดี่ยวบนบรรทัดข้อความอ่านเป็นขยะ ไม่ใช่สถานะ
    if secs <= 0:
        return "resetting"
    d, rem = divmod(secs, 86400)
    h, rem = divmod(rem, 3600)
    m = rem // 60
    if d:
        return f"{d}d {h}h"
    if h:
        return f"{h}h {m:02d}m"
    return f"{m}m"


def usage_color(pct: int | None) -> str:
    if pct is None:
        return PAL.text_dim
    if pct >= L.usage.crit_pct:
        return PAL.alert
    if pct >= L.usage.warn_pct:
        return PAL.accent
    return PAL.good


def _usage_row(draw: ImageDraw.ImageDraw, u: Usage, y: int) -> None:
    pad, w = L.card.pad, L.screen.width
    x0, x1 = pad + 8, w - pad - 8
    col = usage_color(u.pct)

    # เปอร์เซ็นต์ตัวใหญ่ — สิ่งเดียวที่ต้องอ่านออกจากอีกฝั่งห้อง
    # 28 ตรงกับ lv_font_montserrat_28 บนบอร์ด — ฟอนต์คนละตัวแต่ขนาดต้องไม่หลุดกัน
    big = "--%" if u.pct is None else f"{u.pct}%"
    draw.text((x0, y + 14), big, font=font(28),
              fill=quantize565(col if u.pct is not None else PAL.text_dim), anchor="lm")

    # ป้ายชื่อหน้าต่างชิดขวา — สีคงที่เป็นกลาง ไม่ตามระดับ
    # ป้ายบอก *ว่านี่คือหน้าต่างไหน* ซึ่งไม่เคยเปลี่ยน การให้มันเปลี่ยนสีตาม %
    # ทำให้แถวทั้งแถวเป็นสีเดียวตอนวิกฤต แล้วสีหยุดเป็นสัญญาณ กลายเป็นพื้นหลัง
    fl = font(11)
    lw = draw.textlength(u.label, font=fl)
    px0 = x1 - lw - 14
    draw.rounded_rectangle([px0, y + 5, x1, y + 23], radius=9, fill=quantize565(PAL.gray_dark))
    draw.text(((px0 + x1) / 2, y + 14), u.label, font=fl,
              fill=quantize565(PAL.text), anchor="mm")

    # แถบ
    bh = L.usage.bar_h
    by = y + 30
    draw.rectangle([x0, by, x1, by + bh - 1], fill=quantize565(PAL.bg_slot))
    if u.pct is not None:
        fill_w = round((x1 - x0) * min(max(u.pct, 0), 100) / 100)
        if fill_w > 0:
            draw.rectangle([x0, by, x0 + fill_w, by + bh - 1], fill=quantize565(col))

    # ขีด pace — "ควรใช้ถึงไหนแล้ว" ตามเวลาที่ผ่านไปในหน้าต่าง
    # ขีดอยู่ขวาของเนื้อแถบ = ใช้ช้ากว่าเวลา · อยู่ซ้าย = ใช้เร็วเกินไป
    if u.remaining is not None and u.remaining > 0:
        elapsed = max(0, min(u.window, u.window - u.remaining))
        mx = x0 + round((x1 - x0) * elapsed / u.window)
        draw.rectangle([mx, by - 2, mx, by + bh + 1], fill=quantize565(PAL.outline))

    # "resetting" / "--" ยืนลำพัง — เติม "Resets in" ข้างหน้าแล้วอ่านไม่เป็นภาษา
    left = fmt_remaining(u.remaining)
    txt = f"Resets in {left}" if u.remaining and u.remaining > 0 else left
    draw.text((x0, y + 47), txt, font=font(11), fill=quantize565(PAL.text_dim), anchor="lm")


def _usage(draw: ImageDraw.ImageDraw, rows: list[Usage]) -> None:
    y = L.card.top + L.card.pad
    for u in rows[:2]:
        _usage_row(draw, u, y)
        y += L.usage.row_h + L.usage.gap


def _idle_clock(draw: ImageDraw.ImageDraw, s: Screen) -> None:
    """ไม่มีอะไรต้องเตือน = ให้พื้นที่นี้ทำหน้าที่นาฬิกาตั้งโต๊ะแทน

    นี่คือสิ่งที่จอเป็นอยู่เกือบตลอดเวลา ถ้าปล่อยว่างจะดูเหมือนอุปกรณ์พัง
    """
    cx = L.screen.width // 2
    cy = L.card.top + L.card.height // 2
    draw.text((cx, cy - 8), s.clock, font=font(46),
              fill=quantize565(PAL.text if s.connected else PAL.gray), anchor="mm")
    if s.date:
        draw.text((cx, cy + 26), s.date, font=font(12),
                  fill=quantize565(PAL.text_dim), anchor="mm")


def render(s: Screen, phase: float = 0.0, cycle: int = 0) -> Image.Image:
    img = Image.new("RGB", (L.screen.width, L.screen.height), quantize565(PAL.bg))
    draw = ImageDraw.Draw(img)
    _topbar(draw, s)
    n = min(len(s.sessions), L.slots.count)
    for i in range(n):
        _slot(draw, i, s.sessions[i], s, phase, cycle, n)
    # ลำดับความสำคัญของพื้นที่ล่าง: การเตือน > โควตา > นาฬิกา
    # โควตาไม่เคยชนะ card เพราะ card คือสิ่งที่ต้องการการกระทำจากผู้ใช้
    if s.cards:
        _cards(draw, s.cards)
    elif s.usage:
        _usage(draw, s.usage)
    else:
        _idle_clock(draw, s)
    return img
