"""หน้าคริปโตทั้งใบ — พอร์ตคู่กับ firmware/main/ct_crypto_ui.c

ค่าคงที่ทั้งหมดมาจาก layout.toml ชุดเดียวกับ firmware ถ้าภาพที่นี่ต่างจากบนบอร์ด
แปลว่าเป็นบั๊ก renderer ไม่ใช่ค่าคงที่ไม่ตรงกัน
"""

from __future__ import annotations

from dataclasses import dataclass, field

from PIL import Image, ImageDraw

from . import age, screen
from .config import L, PAL
from .rects import Rect, RectList
from .render import draw_rects, quantize565


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


def tone(change: int, connected: bool = True) -> str:
    """สีของแถวหนึ่ง — ทั้งลูกศรและตัวเลขเปอร์เซ็นต์อ่านจากที่เดียวกัน

    ต้องตรงกับ tone() ใน ct_crypto_ui.c
    """
    if not connected:
        return PAL.gray
    if change > 0:
        return PAL.good
    if change < 0:
        return PAL.alert
    return PAL.text_dim


def arrow(change: int, connected: bool = True) -> RectList:
    """ลูกศรขึ้น/ลง — ต้องตรงกับ build_arrow() ใน ct_crypto_ui.c

    สีอย่างเดียวไม่พอ: ตาบอดสีแดง-เขียวคือคนกลุ่มใหญ่ที่สุดที่ *ต้อง* แยกกำไรกับขาดทุน
    ออกโดยไม่อ่านตัวเลข รูปทรงจึงเป็นตัวบอกหลัก ส่วนสีเป็นตัวช่วยที่สอง
    """
    color = tone(change, connected)

    if change == 0:
        # นิ่งคือขีดเดียว ไม่ใช่ลูกศรแบนๆ — สามเหลี่ยมที่ชี้ไปไหนไม่ได้อ่านเป็นลูกศรเสีย
        return [Rect(0.5, 1.75, 3.0, 0.5, color)]
    out: RectList = []
    for i in range(3):
        w = 1.0 + i
        x = 2.0 - w / 2.0
        y = 0.5 + i if change > 0 else 3.5 - i - 1.0
        out.append(Rect(x, y, w, 1.0, color))
    return out


def pct_text(change: int) -> str:
    """เปอร์เซ็นต์คูณสิบ -> ข้อความที่มีเครื่องหมายเสมอ

    "+1.1%" กับ "1.1%" ต่างกันตรงที่อันหลังต้องอ่านสีหรือลูกศรก่อนถึงจะรู้ว่าขึ้นหรือลง
    ต้องตรงกับ pct_text() ใน ct_crypto_ui.c
    """
    sign = "+" if change > 0 else ("-" if change < 0 else "")
    return f"{sign}{abs(change) // 10}.{abs(change) % 10}%"


@dataclass(slots=True)
class Crypto:
    """หน้าคริปโตหนึ่งใบ — `has_frame=False` คือยังไม่เคยได้ข้อมูลเลย"""

    coins: list[Coin] = field(default_factory=list)
    age: int = 35
    # มี snapshot สดอยู่ไหม — ตรงกับ ct_crypto_ui_set_connected
    connected: bool = True
    # เคยได้ page frame ของหน้านี้แล้วหรือยัง (ADR-0002)
    has_frame: bool = True


def render(c: Crypto) -> Image.Image:
    img = Image.new("RGB", (L.screen.width, L.screen.height), quantize565(PAL.bg))
    draw = ImageDraw.Draw(img)

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
