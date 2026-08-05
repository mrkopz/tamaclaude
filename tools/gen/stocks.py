"""หน้าหุ้นทั้งใบ — พอร์ตคู่กับ firmware/main/ct_stocks_ui.c

ค่าคงที่ทั้งหมดมาจาก layout.toml ชุดเดียวกับ firmware ถ้าภาพที่นี่ต่างจากบนบอร์ด
แปลว่าเป็นบั๊ก renderer ไม่ใช่ค่าคงที่ไม่ตรงกัน

รูปเดียวกับหน้าคริปโตทุกส่วน: ตัวแรกได้การ์ด ที่เหลือเป็นแถวเล็ก · *กติกา* (สี ลูกศร
ถ้อยคำ การหั่นราคาเป็นสองขนาด) มาจาก `trend` ซึ่งเป็นที่เดียวที่มันอยู่ — สองหน้านี้
เรียกของตัวเดียวกัน ไม่ได้ลอกกันมา · ส่วน *วิธีวาง* เป็นสำเนาที่ตั้งใจให้แยกกัน ด้วยเหตุผล
ที่ [stocks] ใน layout.toml เขียนไว้: หน้านี้ต้องไม่พังเพราะมีคนแก้หน้าคริปโต

ต่างกันสามข้อที่มองเห็น:
- บรรทัดล่างบอกได้ว่าตัวเลขค้างเพราะตลาดปิด ไม่ใช่เพราะท่อพัง
- ตลาดปิด = ตัวเลขหยุดเดินโดยชอบธรรม การ์ดจึงกลับไปเป็นพื้นกลาง ทั้งที่ลิงก์ยังอยู่
  (คริปโตไม่มีสภาพนี้ ตลาดมันไม่มีเวลาปิด)
- **ไม่มีรูป 24 ชม.** เพราะไม่มีประวัติจะวาด (เหตุผลอยู่ที่ [stocks] ใน layout.toml)
  ช่องของมันเหลือว่างไว้ ไม่มีอะไรเลื่อนเข้าไปแทน
"""

from __future__ import annotations

from dataclasses import dataclass, field

from PIL import Image, ImageDraw

from . import age, mini, pages, screen, topbar, trend
from .config import L, PAL
from .render import draw_rects, quantize565

# ทิศทางขึ้น/ลงเป็นกติกาของทุกหน้า watchlist ไม่ใช่ของหน้านี้ — อยู่ที่ `trend` ที่เดียว
tone = trend.tone
arrow = trend.arrow
pct_text = trend.pct_text

# ข้อความที่บอกว่าทำไมตัวเลขถึงค้าง — ต้องตรงกับ ct_stocks_ui.c
CLOSED = "market closed"


@dataclass(slots=True)
class Stock:
    """หนึ่งแถวอย่างที่มันมาถึงบอร์ด — ราคาเป็นสตริงที่ Mac จัดรูปมาแล้ว

    `change=None` คือเฟรมที่ถูกบีบจนต้องทิ้งคอลัมน์เปอร์เซ็นต์ (ดู `StocksFrame.encoded`
    ฝั่ง Swift) แถวนั้นยังจริงทุกตัวอักษร แค่ไม่มีทิศทางให้ดู — ต่างจากแถวที่แสดง 0.0%
    ซึ่งแปลว่าราคานิ่ง
    """

    symbol: str
    price: str
    change: int | None


@dataclass(slots=True)
class Stocks:
    """หน้าหุ้นหนึ่งใบ — `has_frame=False` คือยังไม่เคยได้ข้อมูลเลย"""

    rows: list[Stock] = field(default_factory=list)
    age: int = 35
    # ตลาดปิดอยู่ตอนที่ Mac อ่านค่าชุดนี้มา
    market_closed: bool = False
    # มี snapshot สดอยู่ไหม — ตรงกับ ct_stocks_ui_set_connected
    connected: bool = True
    # เคยได้ page frame ของหน้านี้แล้วหรือยัง (ADR-0002)
    has_frame: bool = True
    # ท่าของมาสคอตจิ๋วมุมจอ — None = ไม่มี session เลย ซึ่งคือท่าหลับ
    mascot_state: str | None = None
    # แถบบน — มาจาก snapshot ของหน้ามาสคอต ไม่ใช่จากเฟรมของหน้านี้ (`gen/topbar.py`)
    bar: topbar.Bar = field(default_factory=topbar.Bar)


def _hero(draw: ImageDraw.ImageDraw, row: Stock, connected: bool, live: bool) -> None:
    """การ์ดของหุ้นตัวแรกในลิสต์ — คู่ขนานกับ `gen/crypto.py:_hero` ที่เขียนแยกกัน

    `live` = ตัวเลขชุดนี้ยังเดินอยู่จริงไหม ซึ่ง **ไม่ใช่** `connected`: ตลาดที่ปิดแล้ว
    ยังต่อลิงก์อยู่ แต่ราคาหยุดเดินโดยชอบธรรม การ์ดสีเขียวค้างทั้งคืนจะอ่านว่าหุ้นกำลังขึ้น
    อยู่ตอนตีสอง ซึ่งไม่จริง (หลัก "ไม่แกล้งทำเป็นสด")
    """
    cfg = L.stocks
    text = PAL.text if connected else PAL.gray
    # เปอร์เซ็นต์ที่ถูกบีบทิ้งไม่มีทิศทางให้ใช้เลย ทั้งพื้น ขอบ ลูกศร และตัวเลข —
    # ศูนย์กับขีดอ่านว่า "ราคานิ่ง" ซึ่งเป็นข้อมูลที่เฟรมนั้นไม่มี
    known = row.change if row.change is not None else 0
    draw.rectangle(
        [cfg.card_x, cfg.card_y, cfg.card_x + cfg.card_w - 1, cfg.card_y + cfg.card_h - 1],
        fill=quantize565(trend.card_fill(known, live and row.change is not None)),
        outline=quantize565(trend.card_edge(known, connected)), width=1)

    screen.line(draw, (cfg.sym_x, cfg.sym_y), row.symbol, pil=cfg.sym_font_pil,
                board=cfg.sym_font, fill=text, anchor="lt", max_w=cfg.sym_w)

    if row.change is not None:
        # เปอร์เซ็นต์กับราคาไม่ผ่าน `screen.line` — ฟอนต์ 24/48 ไม่มีบิตแมปไทย และไม่ต้องมี
        pct = pct_text(row.change)
        pf = screen.font(cfg.pct_font_pil)
        draw.text((cfg.pct_x, cfg.pct_base_y), pct, font=pf,
                  fill=quantize565(tone(row.change, connected)), anchor="rs")
        # ลูกศรเกาะตัวเลข วัดความกว้างจริงก่อนแล้วค่อยวาง (ฝั่ง LVGL คือ lv_obj_get_width)
        pw = draw.textlength(pct, font=pf)
        ax = cfg.pct_x - pw - cfg.arrow_gap - cfg.arrow_grid * cfg.arrow_px
        draw_rects(draw, arrow(row.change, connected), cfg.arrow_px, ax, cfg.arrow_y)

    # จำนวนเต็มใหญ่ ทศนิยมเล็ก นั่งเส้นฐานเดียวกัน (anchor "s") — ฟอนต์คนละขนาดที่จัด
    # ชิดขอบบนจะลอยคนละระดับ
    head, tail = trend.split_price(row.price, cfg.int_digits_max)
    x = cfg.price_x
    if head:
        big = screen.font(cfg.int_font_pil)
        draw.text((x, cfg.price_base_y), head, font=big, fill=quantize565(text), anchor="ls")
        x += draw.textlength(head, font=big)
    draw.text((x, cfg.price_base_y), tail, font=screen.font(cfg.frac_font_pil),
              fill=quantize565(text), anchor="ls")



def _row(draw: ImageDraw.ImageDraw, row: Stock, top: int, connected: bool) -> None:
    """หนึ่งแถวเล็กใต้การ์ด — คู่ขนานกับ `gen/crypto.py:_row` ที่เขียนแยกกัน"""
    cfg = L.stocks
    text = PAL.text if connected else PAL.gray
    ty = top + cfg.row_text_dy
    screen.line(draw, (cfg.row_sym_x, ty), row.symbol, pil=cfg.row_font_pil,
                board=cfg.row_font, fill=text, anchor="lt", max_w=cfg.row_sym_w)
    # ราคาชิดขวา หลักหน่วยของทุกแถวจึงเรียงตรงกัน และเทียบข้ามแถวได้ด้วยการกวาดตา
    screen.line(draw, (cfg.row_price_x, ty), row.price, pil=cfg.row_font_pil,
                board=cfg.row_font, fill=text, anchor="rt")

    # เปอร์เซ็นต์ที่ถูกบีบทิ้งคือช่องว่าง ไม่ใช่ขีดหรือศูนย์ — ทั้งสองอย่างนั้นอ่านว่า
    # "ราคานิ่ง" ซึ่งเป็นข้อมูลที่เราไม่มีในเฟรมนั้น
    if row.change is None:
        return
    pct = pct_text(row.change)
    screen.line(draw, (cfg.row_pct_x, ty), pct, pil=cfg.row_font_pil,
                board=cfg.row_font, fill=tone(row.change, connected), anchor="rt")
    pw = draw.textlength(pct, font=screen.font(cfg.row_font_pil))
    ax = cfg.row_pct_x - pw - cfg.row_arrow_gap - cfg.row_arrow_grid * cfg.row_arrow_px
    draw_rects(draw, arrow(row.change, connected), cfg.row_arrow_px, ax,
               top + cfg.row_arrow_dy)


def render(s: Stocks, phase: float = 0.0, cycle: int = 0) -> Image.Image:
    img = Image.new("RGB", (L.screen.width, L.screen.height), quantize565(PAL.bg))
    draw = ImageDraw.Draw(img)
    # หน้านี้ไม่เคยแสดงเวลาหรือโควตาเอง แถบจึงพูดครบเสมอ (ดู `topbar.draw`)
    topbar.draw(draw, s.bar, page=pages.LABELS["stocks"], connected=s.connected)
    frozen = CLOSED if s.market_closed else None

    # มาสคอตอยู่แถบบนของทุกหน้า รวมหน้าที่ยังไม่เคยได้ข้อมูล — สถานะ session ไม่ได้ขึ้นกับ
    # ว่าหน้านี้มีตัวเลขให้ดูหรือยัง
    mini.draw_mini(draw, s.mascot_state, s.connected, phase, cycle)

    rows = s.rows[: L.stocks.rows] if s.has_frame else []
    if not rows:
        # ยังไม่เคยได้ข้อมูลของหน้านี้ ต้องมีหน้าตาของตัวเอง ห้ามเป็นจอเปล่า (ADR-0002)
        screen.line(draw, (L.stocks.sym_x, L.stocks.empty_y), "No stocks yet",
                    pil=12, board=14, fill=PAL.text, anchor="lt")
        screen.line(draw, (L.stocks.sym_x, L.stocks.empty_sub_y),
                    "add symbols in the mac app", pil=10, board=12,
                    fill=PAL.text_dim, anchor="lt")
        if s.has_frame:
            age.draw_age(draw, s.age, L.stocks.refresh_s, frozen)
        return img

    _hero(draw, rows[0], s.connected, live=s.connected and not s.market_closed)
    for i, row in enumerate(rows[1:]):
        _row(draw, row, L.stocks.row_y + i * L.stocks.row_h, s.connected)
    if len(rows) == 1:
        # ขึ้นเฉพาะตอนไม่มีแถวเล็กเลย ไม่ใช่ทุกครั้งที่เหลือช่องว่าง (ดู `hint_y`)
        screen.line(draw, (L.stocks.hint_x, L.stocks.hint_y), "add more in the mac app",
                    pil=10, board=12, fill=PAL.text_dim, anchor="lt")

    age.draw_age(draw, s.age, L.stocks.refresh_s, frozen)
    return img
