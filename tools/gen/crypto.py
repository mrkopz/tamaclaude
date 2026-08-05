"""หน้าคริปโตทั้งใบ — พอร์ตคู่กับ firmware/main/ct_crypto_ui.c

ค่าคงที่ทั้งหมดมาจาก layout.toml ชุดเดียวกับ firmware ถ้าภาพที่นี่ต่างจากบนบอร์ด
แปลว่าเป็นบั๊ก renderer ไม่ใช่ค่าคงที่ไม่ตรงกัน
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
    # รูป 24 ชั่วโมงเป็นระดับ 0..15 · None = บริการไม่มีประวัติให้ หรือถูกตัดทิ้งตอนบีบเฟรม
    # ไม่ใช่ราคา — Mac quantize บน min..max ของแถวนั้นเอง บอร์ดจึงไม่เคยเห็นราคาในอดีต
    spark: list[int] | None = None


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
    # แถบบน — มาจาก snapshot ของหน้ามาสคอต ไม่ใช่จากเฟรมของหน้านี้ (`gen/topbar.py`)
    bar: topbar.Bar = field(default_factory=topbar.Bar)


def _hero(draw: ImageDraw.ImageDraw, coin: Coin, connected: bool) -> None:
    """การ์ดของเหรียญแรกในลิสต์

    `gen/stocks.py` มีตัวคู่ขนานของฟังก์ชันนี้ **ที่เขียนแยกกัน ไม่ใช่เรียกตัวนี้** —
    ด้วยเหตุผลเดียวกับที่ [stocks] ใน layout.toml ไม่ให้ฝั่ง C อ่านมาโคร CT_CRYPTO_*:
    หน้าหุ้นต้องไม่พังเพราะมีคนแก้หน้าคริปโตด้วยเหตุผลของหน้าคริปโต · ที่มีสำเนาเดียว
    จริงๆ คือ *กติกา* ซึ่งอยู่ใน `trend` แล้ว (สี ลูกศร รูป การหั่นราคา) ไม่ใช่วิธีวาง

    ตลาดคริปโตไม่มีเวลาปิด "ตัวเลขยังเดินอยู่ไหม" จึงเท่ากับ "ลิงก์ยังอยู่ไหม" พอดี
    หน้าหุ้นไม่ใช่แบบนั้น และนั่นคือที่เดียวที่สองหน้าต่างกันจริงๆ
    """
    cfg = L.crypto
    text = PAL.text if connected else PAL.gray
    accent = tone(coin.change, connected)
    draw.rectangle(
        [cfg.card_x, cfg.card_y, cfg.card_x + cfg.card_w - 1, cfg.card_y + cfg.card_h - 1],
        fill=quantize565(trend.card_fill(coin.change, connected)),
        outline=quantize565(trend.card_edge(coin.change, connected)), width=1)

    screen.line(draw, (cfg.sym_x, cfg.sym_y), coin.symbol,
                pil=cfg.sym_font_pil, board=cfg.sym_font, fill=text, anchor="lt",
                max_w=cfg.sym_w)

    # เปอร์เซ็นต์กับราคาไม่ผ่าน `screen.line` — ฟอนต์ 24/48 ไม่มีบิตแมปไทย และไม่ต้องมี
    # (ตัวเลขล้วน) ประตูสองภาษาเป็นของป้ายที่รับข้อความจากผู้ใช้ ไม่ใช่ของตัวเลขที่ Mac จัดรูปมา
    pct = pct_text(coin.change)
    pf = screen.font(cfg.pct_font_pil)
    draw.text((cfg.pct_x, cfg.pct_base_y), pct, font=pf, fill=quantize565(accent),
              anchor="rs")
    # ลูกศรเกาะตัวเลข: วัดความกว้างจริงก่อนแล้วค่อยวาง ไม่ใช่ตั้งพิกัดตายตัวไว้ทางซ้าย
    # (ฝั่ง LVGL คือ lv_obj_get_width ของป้ายเปอร์เซ็นต์หลัง lv_label_set_text)
    pw = draw.textlength(pct, font=pf)
    ax = cfg.pct_x - pw - cfg.arrow_gap - cfg.arrow_grid * cfg.arrow_px
    draw_rects(draw, arrow(coin.change, connected), cfg.arrow_px, ax, cfg.arrow_y)

    # จำนวนเต็มใหญ่ ทศนิยมเล็ก นั่งเส้นฐานเดียวกัน — ทั้งสองก้อนวาดจากเส้นฐาน (anchor "s")
    # ไม่ใช่จากขอบบน ฟอนต์คนละขนาดที่จัดชิดขอบบนจะลอยคนละระดับ
    head, tail = trend.split_price(coin.price, cfg.int_digits_max)
    x = cfg.price_x
    if head:
        big = screen.font(cfg.int_font_pil)
        draw.text((x, cfg.price_base_y), head, font=big, fill=quantize565(text), anchor="ls")
        x += draw.textlength(head, font=big)
    draw.text((x, cfg.price_base_y), tail, font=screen.font(cfg.frac_font_pil),
              fill=quantize565(text), anchor="ls")

    draw_rects(draw, trend.spark(coin.spark or [], w=cfg.spark_w, h=cfg.spark_h,
                                 cols=cfg.spark_cols, pitch=cfg.spark_pitch,
                                 bar=cfg.spark_bar, connected=connected),
               1.0, cfg.spark_x, cfg.spark_y)


def _row(draw: ImageDraw.ImageDraw, coin: Coin, top: int, connected: bool) -> None:
    """หนึ่งแถวเล็กใต้การ์ด — `gen/stocks.py` มีตัวคู่ขนานที่เขียนแยกกัน (ดู `_hero`)"""
    cfg = L.crypto
    text = PAL.text if connected else PAL.gray
    ty = top + cfg.row_text_dy
    screen.line(draw, (cfg.row_sym_x, ty), coin.symbol, pil=cfg.row_font_pil,
                board=cfg.row_font, fill=text, anchor="lt", max_w=cfg.row_sym_w)
    # ราคาชิดขวา หลักหน่วยของทุกแถวจึงเรียงตรงกัน และเทียบข้ามแถวได้ด้วยการกวาดตา
    screen.line(draw, (cfg.row_price_x, ty), coin.price, pil=cfg.row_font_pil,
                board=cfg.row_font, fill=text, anchor="rt")

    draw_rects(draw, trend.spark(coin.spark or [], w=cfg.row_spark_w, h=cfg.row_spark_h,
                                 cols=cfg.row_spark_cols, pitch=cfg.row_spark_pitch,
                                 bar=cfg.row_spark_bar, connected=connected),
               1.0, cfg.row_spark_x, top + cfg.row_spark_dy)

    pct = pct_text(coin.change)
    screen.line(draw, (cfg.row_pct_x, ty), pct, pil=cfg.row_font_pil,
                board=cfg.row_font, fill=tone(coin.change, connected), anchor="rt")
    pw = draw.textlength(pct, font=screen.font(cfg.row_font_pil))
    ax = cfg.row_pct_x - pw - cfg.row_arrow_gap - cfg.row_arrow_grid * cfg.row_arrow_px
    draw_rects(draw, arrow(coin.change, connected), cfg.row_arrow_px, ax,
               top + cfg.row_arrow_dy)


def render(c: Crypto, phase: float = 0.0, cycle: int = 0) -> Image.Image:
    img = Image.new("RGB", (L.screen.width, L.screen.height), quantize565(PAL.bg))
    draw = ImageDraw.Draw(img)
    # หน้านี้ไม่เคยแสดงเวลาหรือโควตาเอง แถบจึงพูดครบเสมอ (ดู `topbar.draw`)
    topbar.draw(draw, c.bar, page=pages.LABELS["crypto"], connected=c.connected)

    # มาสคอตอยู่แถบบนของทุกหน้า รวมหน้าที่ยังไม่เคยได้ข้อมูล — สถานะ session ไม่ได้ขึ้นกับ
    # ว่าหน้านี้มีตัวเลขให้ดูหรือยัง
    mini.draw_mini(draw, c.mascot_state, c.connected, phase, cycle)

    coins = c.coins[: L.crypto.rows] if c.has_frame else []
    if not coins:
        # ยังไม่เคยได้ข้อมูลของหน้านี้ ต้องมีหน้าตาของตัวเอง ห้ามเป็นจอเปล่า (ADR-0002)
        screen.line(draw, (L.crypto.sym_x, L.crypto.empty_y), "No coins yet",
                    pil=12, board=14, fill=PAL.text, anchor="lt")
        screen.line(draw, (L.crypto.sym_x, L.crypto.empty_sub_y),
                    "add coins in the mac app", pil=10, board=12,
                    fill=PAL.text_dim, anchor="lt")
        if c.has_frame:
            age.draw_age(draw, c.age, L.crypto.refresh_s)
        return img

    _hero(draw, coins[0], c.connected)
    for i, coin in enumerate(coins[1:]):
        _row(draw, coin, L.crypto.row_y + i * L.crypto.row_h, c.connected)
    if len(coins) == 1:
        # ขึ้นเฉพาะตอนไม่มีแถวเล็กเลย ไม่ใช่ทุกครั้งที่เหลือช่องว่าง (ดู `hint_y`)
        screen.line(draw, (L.crypto.hint_x, L.crypto.hint_y), "add more in the mac app",
                    pil=10, board=12, fill=PAL.text_dim, anchor="lt")

    age.draw_age(draw, c.age, L.crypto.refresh_s)
    return img
