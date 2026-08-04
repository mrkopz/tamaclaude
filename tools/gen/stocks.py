"""หน้าหุ้นทั้งใบ — พอร์ตคู่กับ firmware/main/ct_stocks_ui.c

ค่าคงที่ทั้งหมดมาจาก layout.toml ชุดเดียวกับ firmware ถ้าภาพที่นี่ต่างจากบนบอร์ด
แปลว่าเป็นบั๊ก renderer ไม่ใช่ค่าคงที่ไม่ตรงกัน

รูปเดียวกับหน้าคริปโตทุกส่วน ลูกศรกับสีมาจาก `trend` ซึ่งเป็นที่เดียวที่กติกา "ขึ้นกับลง
ต้องแยกออกโดยไม่อ่านตัวเลข" มีอยู่ — สองหน้านี้เรียกของตัวเดียวกัน ไม่ได้ลอกกันมา

ต่างกันข้อเดียวที่มองเห็น: บรรทัดล่างบอกได้ว่าตัวเลขค้างเพราะตลาดปิด ไม่ใช่เพราะท่อพัง
"""

from __future__ import annotations

from dataclasses import dataclass, field

from PIL import Image, ImageDraw

from . import age, mini, screen, trend
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


def render(s: Stocks, phase: float = 0.0, cycle: int = 0) -> Image.Image:
    img = Image.new("RGB", (L.screen.width, L.screen.height), quantize565(PAL.bg))
    draw = ImageDraw.Draw(img)
    frozen = CLOSED if s.market_closed else None

    # มาสคอตอยู่แถบบนของทุกหน้า รวมหน้าที่ยังไม่เคยได้ข้อมูล — สถานะ session ไม่ได้ขึ้นกับ
    # ว่าหน้านี้มีตัวเลขให้ดูหรือยัง
    mini.draw_mini(draw, s.mascot_state, s.connected, phase, cycle)

    rows = s.rows[: L.stocks.rows] if s.has_frame else []
    if not rows:
        # ยังไม่เคยได้ข้อมูลของหน้านี้ ต้องมีหน้าตาของตัวเอง ห้ามเป็นจอเปล่า (ADR-0002)
        screen.line(draw, (L.stocks.sym_x, L.stocks.empty_y + 7), "No stocks yet",
                    pil=12, board=14, fill=PAL.text, anchor="lm")
        screen.line(draw, (L.stocks.sym_x, L.stocks.empty_sub_y + 6),
                    "add symbols in the mac app", pil=10, board=12,
                    fill=PAL.text_dim, anchor="lm")
        if s.has_frame:
            age.draw_age(draw, s.age, L.stocks.refresh_s, frozen)
        return img

    text = PAL.text if s.connected else PAL.gray
    for i, row in enumerate(rows):
        top = L.stocks.row_y + i * L.stocks.row_h
        screen.line(draw, (L.stocks.sym_x, top + L.stocks.sym_dy + 7), row.symbol,
                    pil=12, board=14, fill=text, anchor="lm", max_w=L.stocks.sym_w)
        # ราคาชิดขวา หลักหน่วยของทุกแถวจึงเรียงตรงกัน และเทียบข้ามแถวได้ด้วยการกวาดตา
        draw.text((L.stocks.price_x + L.stocks.price_w, top + L.stocks.price_dy + 12),
                  row.price, font=screen.font(L.stocks.price_font_pil),
                  fill=quantize565(text), anchor="rm")

        # เปอร์เซ็นต์ที่ถูกบีบทิ้งคือช่องว่าง ไม่ใช่ขีดหรือศูนย์ — ทั้งสองอย่างนั้นอ่านว่า
        # "ราคานิ่ง" ซึ่งเป็นข้อมูลที่เราไม่มีในเฟรมนั้น
        if row.change is None:
            continue
        screen.line(draw, (L.stocks.pct_x + L.stocks.pct_w, top + L.stocks.pct_dy + 7),
                    pct_text(row.change), pil=12, board=14,
                    fill=tone(row.change, s.connected), anchor="rm")
        draw_rects(draw, arrow(row.change, s.connected), L.stocks.arrow_px,
                   L.stocks.arrow_x, top + L.stocks.arrow_dy)

    age.draw_age(draw, s.age, L.stocks.refresh_s, frozen)
    return img
