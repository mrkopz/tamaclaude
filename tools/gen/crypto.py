"""หน้าคริปโตทั้งใบ — พอร์ตคู่กับ firmware/main/ct_crypto_ui.c

ค่าคงที่ทั้งหมดมาจาก layout.toml ชุดเดียวกับ firmware ถ้าภาพที่นี่ต่างจากบนบอร์ด
แปลว่าเป็นบั๊ก renderer ไม่ใช่ค่าคงที่ไม่ตรงกัน
"""

from __future__ import annotations

from dataclasses import dataclass, field

from PIL import Image, ImageDraw

from . import age, logos, mini, pages, screen, topbar, trend
from .config import L, PAL
from .render import draw_arrow, draw_rects, quantize565

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


def _window(draw: ImageDraw.ImageDraw, text: str, arrow_x: float, cfg, connected: bool) -> None:
    """แคปซูลบอกหน้าต่างเวลาของเปอร์เซ็นต์ — เกาะขอบซ้ายของลูกศร

    `gen/stocks.py` มีตัวคู่ขนานที่เขียนแยกกัน ด้วยเหตุผลเดียวกับ `_hero` — และที่นั่น
    คำในแคปซูลเป็นคนละคำจริงๆ ("today") ไม่ใช่แค่ค่าคงที่คนละตัว
    """
    col = quantize565(PAL.text_dim if connected else PAL.gray)
    x1 = arrow_x - cfg.win_gap
    x0 = x1 - cfg.win_w
    y1 = cfg.win_y + cfg.win_h - 1
    draw.rounded_rectangle([x0, cfg.win_y, x1 - 1, y1], radius=cfg.win_r, outline=col, width=1)
    # กึ่งกลางกล่อง ไม่ใช่เส้นฐาน — ข้างในแคปซูลไม่มีอะไรให้เรียงเส้นฐานด้วย
    draw.text(((x0 + x1) / 2, (cfg.win_y + y1) / 2 + 1), text,
              font=screen.font(cfg.win_font_pil), fill=col, anchor="mm")


def _hero(img: Image.Image, draw: ImageDraw.ImageDraw, coin: Coin, connected: bool) -> None:
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

    # logo หลังการ์ด ก่อนตัวหนังสือ — มันนั่งบนพื้นการ์ดที่เพิ่งวาด และอัลฟาของมันต้อง
    # ผสมกับพื้นสีนั้น ไม่ใช่กับพื้นจอ (พื้นการ์ดเปลี่ยนสีตามทิศทางขึ้น/ลง)
    logos.paste(img, coin.symbol, cfg.icon_x, cfg.icon_y, cfg.icon_px, connected)

    # ไม่ผ่าน `screen.line` ด้วยเหตุผลเดียวกับราคาและเปอร์เซ็นต์ข้างล่าง — ฟอนต์ 24 ไม่มี
    # บิตแมปไทย และสัญลักษณ์เป็น ASCII ที่บริการเป็นคนบอก ไม่ใช่ข้อความที่ผู้ใช้พิมพ์
    # ไม่ตัดด้วย `sym_w` เพราะ `CryptoFrame.symbolLimit` = 5 ตัว ซึ่งที่ 22px กว้าง ~70px
    # ในกรอบ 100px — ด่านอยู่ต้นทางแล้ว
    draw.text((cfg.sym_x, cfg.sym_base_y), coin.symbol, font=screen.font(cfg.sym_font_pil),
              fill=quantize565(text), anchor="ls")

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
    draw_arrow(img, draw, arrow(coin.change, connected), cfg.arrow_px, ax, cfg.arrow_y)

    # แคปซูลบอกหน้าต่างเวลา — ต้องตรงกับ CT_CRYPTO_WINDOW_TEXT ใน ct_crypto_ui.c
    # ค่าที่ CoinGecko ให้คือ price_change_percentage_24h ตรงๆ ไม่ใช่ที่เราคำนวณเอง
    _window(draw, "24h", ax, cfg, connected)

    # จำนวนเต็มใหญ่ ทศนิยมเล็ก นั่งเส้นฐานเดียวกัน — ทั้งสองก้อนวาดจากเส้นฐาน (anchor "s")
    # ไม่ใช่จากขอบบน ฟอนต์คนละขนาดที่จัดชิดขอบบนจะลอยคนละระดับ
    head, tail = trend.split_price(coin.price, cfg.int_digits_max)
    x = cfg.price_x
    if head:
        big = screen.font(cfg.int_font_pil)
        screen.price_text(draw, (x, cfg.price_base_y), head, big, text)
        x += draw.textlength(head, font=big)
    screen.price_text(draw, (x, cfg.price_base_y), tail, screen.font(cfg.frac_font_pil), text)

    draw_rects(draw, trend.spark(coin.spark or [], w=cfg.spark_w, h=cfg.spark_h,
                                 cols=cfg.spark_cols, pitch=cfg.spark_pitch,
                                 bar=cfg.spark_bar, connected=connected),
               1.0, cfg.spark_x, cfg.spark_y)


def _rows_arrow_x(draw: ImageDraw.ImageDraw, coins: list[Coin], cfg) -> float:
    """พิกัดลูกศรที่แถวเล็ก *ทุกแถว* ใช้ร่วมกัน — วัดจากเปอร์เซ็นต์ที่ยาวที่สุดในหน้านั้น

    ลูกศรของแถวใหญ่เกาะตัวเลขของตัวเอง เพราะมันมีใบเดียว ไม่มีอะไรให้เรียงด้วย แต่ในลิสต์
    ที่มีหลายแถว การเกาะตัวเลขแยกใครแยกมันทำให้ลูกศรเยื้องกันตามความยาวเลข ("+1.1%" กับ
    "+12.4%" ต่างกันเกือบหนึ่งตัวอักษร) แล้วคอลัมน์ที่ควรอ่านด้วยการกวาดตาลงมาก็เป็นฟันหลอ
    · เลือกวัดจากตัวที่ยาวที่สุดแทนพิกัดตายตัว เพราะพิกัดตายตัวจะทิ้งช่องว่างค้างไว้เสมอ
    ในหน้าที่ทุกแถวเป็นเลขสั้น (และต้องเดาความกว้างฟอนต์บอร์ดล่วงหน้าด้วย)
    ต้องตรงกับที่ ct_crypto_ui.c คิดใน ct_crypto_ui_redraw()
    """
    f = screen.font(cfg.row_font_pil)
    widest = max((draw.textlength(pct_text(c.change), font=f) for c in coins), default=0.0)
    return cfg.row_pct_x - widest - cfg.row_arrow_gap - cfg.row_arrow_grid * cfg.row_arrow_px


def _row(img: Image.Image, draw: ImageDraw.ImageDraw, coin: Coin, top: int,
         connected: bool, arrow_x: float) -> None:
    """หนึ่งแถวเล็กใต้การ์ด — `gen/stocks.py` มีตัวคู่ขนานที่เขียนแยกกัน (ดู `_hero`)"""
    cfg = L.crypto
    text = PAL.text if connected else PAL.gray
    ty = top + cfg.row_text_dy
    logos.paste(img, coin.symbol, cfg.row_icon_x, top + cfg.row_icon_dy, cfg.row_icon_px,
                connected)
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
    draw_arrow(img, draw, arrow(coin.change, connected), cfg.row_arrow_px, arrow_x,
               top + cfg.row_arrow_dy)


def render(c: Crypto, phase: float = 0.0, cycle: int = 0) -> Image.Image:
    img = Image.new("RGB", (L.screen.width, L.screen.height), quantize565(PAL.bg))
    draw = ImageDraw.Draw(img)
    # หน้านี้ไม่เคยแสดงเวลาหรือโควตาเอง แถบจึงพูดครบเสมอ (ดู `topbar.draw`)
    topbar.draw(draw, c.bar, page=pages.LABELS["crypto"], connected=c.connected)

    # มาสคอตอยู่แถบบนของทุกหน้า รวมหน้าที่ยังไม่เคยได้ข้อมูล — สถานะ session ไม่ได้ขึ้นกับ
    # ว่าหน้านี้มีตัวเลขให้ดูหรือยัง
    mini.draw_mini(draw, c.mascot_state, c.connected, phase, cycle)

    # ไม่ใช่ชื่อ `logos` — ชื่อนั้นเป็นของโมดูล logo ที่ไฟล์นี้ import มาแล้ว
    rows = c.coins[: L.crypto.rows] if c.has_frame else []
    if not rows:
        # ยังไม่เคยได้ข้อมูลของหน้านี้ ต้องมีหน้าตาของตัวเอง ห้ามเป็นจอเปล่า (ADR-0002)
        screen.line(draw, (L.crypto.empty_x, L.crypto.empty_y), "No coins yet",
                    pil=12, board=14, fill=PAL.text, anchor="lt")
        screen.line(draw, (L.crypto.empty_x, L.crypto.empty_sub_y),
                    "add coins in the mac app", pil=10, board=12,
                    fill=PAL.text_dim, anchor="lt")
        if c.has_frame:
            age.draw_age(draw, c.age, L.crypto.refresh_s)
        return img

    _hero(img, draw, rows[0], c.connected)
    ax = _rows_arrow_x(draw, rows[1:], L.crypto)
    for i, coin in enumerate(rows[1:]):
        _row(img, draw, coin, L.crypto.row_y + i * L.crypto.row_h, c.connected, ax)
    if len(rows) == 1:
        # ขึ้นเฉพาะตอนไม่มีแถวเล็กเลย ไม่ใช่ทุกครั้งที่เหลือช่องว่าง (ดู `hint_y`)
        screen.line(draw, (L.crypto.hint_x, L.crypto.hint_y), "add more in the mac app",
                    pil=10, board=12, fill=PAL.text_dim, anchor="lt")

    age.draw_age(draw, c.age, L.crypto.refresh_s)
    return img
