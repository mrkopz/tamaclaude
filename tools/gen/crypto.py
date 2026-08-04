"""หน้าคริปโตทั้งใบ — พอร์ตคู่กับ firmware/main/ct_crypto_ui.c

ค่าคงที่ทั้งหมดมาจาก layout.toml ชุดเดียวกับ firmware ถ้าภาพที่นี่ต่างจากบนบอร์ด
แปลว่าเป็นบั๊ก renderer ไม่ใช่ค่าคงที่ไม่ตรงกัน
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


@dataclass(slots=True)
class Coin:
    """หนึ่งแถวอย่างที่มันมาถึงบอร์ด — ราคาเป็นสตริงที่ Mac จัดรูปมาแล้ว

    จำนวนทศนิยมขึ้นกับขนาดของราคา และเป็นสิ่งที่ Mac ลดลงเองตอนบีบเฟรมให้พอดี MTU
    (ดู `CryptoFrame.encoded` ฝั่ง Swift) บอร์ดจึงไม่จัดรูปเลขเอง
    """

    symbol: str
    price: str
    # เปอร์เซ็นต์คูณสิบ เหมือนที่เดินทางบนสาย
    change: int


@dataclass(slots=True)
class Crypto:
    """หน้าคริปโตหนึ่งใบ — `has_frame=False` คือยังไม่เคยได้ข้อมูลเลย"""

    coins: list[Coin] = field(default_factory=list)
    age: int = 35
    # มี snapshot สดอยู่ไหม — ตรงกับ ct_crypto_ui_set_connected
    connected: bool = True
    # เคยได้ page frame ของหน้านี้แล้วหรือยัง (ADR-0002)
    has_frame: bool = True
    # ท่าของมาสคอตจิ๋วมุมจอ — None = ไม่มี session เลย ซึ่งคือท่าหลับ
    mascot_state: str | None = None


def render(c: Crypto, phase: float = 0.0, cycle: int = 0) -> Image.Image:
    img = Image.new("RGB", (L.screen.width, L.screen.height), quantize565(PAL.bg))
    draw = ImageDraw.Draw(img)

    # มาสคอตอยู่แถบบนของทุกหน้า รวมหน้าที่ยังไม่เคยได้ข้อมูล — สถานะ session ไม่ได้ขึ้นกับ
    # ว่าหน้านี้มีตัวเลขให้ดูหรือยัง
    mini.draw_mini(draw, c.mascot_state, c.connected, phase, cycle)

    coins = c.coins[: L.crypto.rows] if c.has_frame else []
    if not coins:
        # ยังไม่เคยได้ข้อมูลของหน้านี้ ต้องมีหน้าตาของตัวเอง ห้ามเป็นจอเปล่า (ADR-0002)
        screen.line(draw, (L.crypto.sym_x, L.crypto.empty_y + 7), "No coins yet",
                    pil=12, board=14, fill=PAL.text, anchor="lm")
        screen.line(draw, (L.crypto.sym_x, L.crypto.empty_sub_y + 6),
                    "add coins in the mac app", pil=10, board=12,
                    fill=PAL.text_dim, anchor="lm")
        if c.has_frame:
            age.draw_age(draw, c.age, L.crypto.refresh_s)
        return img

    text = PAL.text if c.connected else PAL.gray
    for i, coin in enumerate(coins):
        top = L.crypto.row_y + i * L.crypto.row_h
        screen.line(draw, (L.crypto.sym_x, top + L.crypto.sym_dy + 7), coin.symbol,
                    pil=12, board=14, fill=text, anchor="lm", max_w=L.crypto.sym_w)
        # ราคาชิดขวา หลักหน่วยของทุกแถวจึงเรียงตรงกัน และเทียบข้ามแถวได้ด้วยการกวาดตา
        draw.text((L.crypto.price_x + L.crypto.price_w, top + L.crypto.price_dy + 12),
                  coin.price, font=screen.font(L.crypto.price_font_pil),
                  fill=quantize565(text), anchor="rm")

        screen.line(draw, (L.crypto.pct_x + L.crypto.pct_w, top + L.crypto.pct_dy + 7),
                    pct_text(coin.change), pil=12, board=14,
                    fill=tone(coin.change, c.connected), anchor="rm")
        draw_rects(draw, arrow(coin.change, c.connected), L.crypto.arrow_px,
                   L.crypto.arrow_x, top + L.crypto.arrow_dy)

    age.draw_age(draw, c.age, L.crypto.refresh_s)
    return img
