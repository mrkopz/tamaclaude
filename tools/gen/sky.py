"""ท้องฟ้าตามช่วงเวลาและสภาพอากาศ — ฉากเต็มจอใต้แถบบน

ฟ้าอยู่ 22..119 แล้วพื้นดินยาวลงไปถึงก้นจอ: card วาดพื้นทึบของตัวเองอยู่แล้ว
ส่วนแผงโควตากับนาฬิกาใหญ่วางตัวอักษรลงบนพื้นดินตรงๆ สีพื้นดินทุกช่วงจึงต้องเข้ม
(luminance ~0.04) ไม่ใช่สีหญ้าจริง ความเขียวไปอยู่ที่กอหญ้าเล็กๆ บนเส้นขอบฟ้าแทน

เส้นขอบฟ้าอยู่ที่เส้นฝ่าเท้าพอดี — มาสคอตยืนบนพื้น ไม่ลอย ไม่จม ป้ายชื่อโปรเจกต์
ตกลงไปอยู่บนพื้นดินใต้เท้า

เวลามาจาก `snapshot.clock` ที่มีอยู่แล้ว ส่วนสภาพอากาศมาจากเฟรมของ *หน้าอากาศ*
ที่บอร์ดแคชไว้ (ADR-0012) — ทั้งคู่ไม่มีอะไรเพิ่มบนสาย BLE · ต้องตรงกับฝั่ง firmware
ใน `firmware/main/ct_ui.c`

`bucket()` กับ `DECK_COLOR` อยู่ที่นี่ ไม่ใช่ที่ `weather.py` เพราะมีคนใช้สองหน้าแล้ว
เหตุผลเดียวกับที่ `phase_at` ย้ายมาอยู่ `ct_sky.h` ฝั่ง C — สำเนาสองใบจะเลื่อนจากกัน
เงียบๆ แล้ววันหนึ่ง 61 ก็เป็นฝนบนหน้าหนึ่งและเป็นเมฆบนอีกหน้า · และทิศ import ก็ถูก
ทางนี้ทางเดียว: `weather.py` ดึงจาก `sky.py` อยู่แล้ว ทางกลับเป็นวงกลมทันที
"""

from __future__ import annotations

import math

from PIL import ImageDraw

from .config import L, PAL
from .render import quantize565

# ฟ้าเริ่มใต้แถบบน ไม่ใช่ที่ขอบบนของแถบมาสคอต — แถบมาสคอตนั่งต่ำกว่านั้นลงมามาก
# ที่ว่างเหนือหัวคือท้องฟ้าที่ดวงอาทิตย์เดินผ่าน
SKY_TOP = L.topbar.height
HORIZON = L.sky.horizon
GROUND_BOTTOM = L.screen.height

SKY_COLOR = {
    "night": PAL.sky_night,
    "dawn": PAL.sky_dawn,
    "day": PAL.sky_day,
    "dusk": PAL.sky_dusk,
}
GROUND_COLOR = {
    "night": PAL.ground_night,
    "dawn": PAL.ground_dawn,
    "day": PAL.ground_day,
    "dusk": PAL.ground_dusk,
}
CLOUD_COLOR = {
    "dawn": PAL.cloud_dawn,
    "day": PAL.cloud_day,
    "dusk": PAL.cloud_dusk,
}
GRASS_COLOR = {
    "night": PAL.grass_night,
    "dawn": PAL.grass_dawn,
    "day": PAL.grass_day,
    "dusk": PAL.grass_dusk,
}
SHADOW_COLOR = {
    "night": PAL.shadow_night,
    "dawn": PAL.shadow_dawn,
    "day": PAL.shadow_day,
    "dusk": PAL.shadow_dusk,
}
DECK_COLOR = {
    "night": PAL.wx_deck_night,
    "dawn": PAL.wx_deck_dawn,
    "day": PAL.wx_deck_day,
    "dusk": PAL.wx_deck_dusk,
}
# กลุ่มที่มีแนวเมฆปิดฟ้า — `clear` ไม่มีอะไรปิด ส่วน `fog` เป็นแถบนอน ไม่ใช่เพดาน
DECK_KINDS = ("cloud", "rain", "snow", "storm")
# กลุ่มที่มีอะไรปิดฟ้าอยู่แต่ยังไม่ใช่พายุ — หมอกนับด้วยทั้งที่ไม่มีเพดาน
DULL_KINDS = ("cloud", "fog", "rain", "snow")


def _dull(phase: str, kind: str) -> bool:
    """กลางวันที่ฟ้าถูกปิด — ใช้ชุดสี `wx_dull_*` แทนสีของช่วงเวลา

    เฉพาะ day: กลางคืน/เช้ามืด/พลบค่ำ ฟ้าเข้มอยู่แล้ว สีที่จูนไว้กับมันยังจริง และ
    ความขัดแย้งที่สายตาจับได้ ("ฟ้าใสใต้เพดานเทา") มีแค่ตอนกลางวัน
    """
    return phase == "day" and kind in DULL_KINDS


def bucket(code: int) -> str:
    """รหัส WMO -> กลุ่มสภาพอากาศ — ต้องตรงกับ ct_sky_bucket() ใน ct_sky.h

    รหัสมีหลายสิบค่า แต่จอ 2.8 นิ้วที่มองจากอีกฝั่งห้องแยกได้จริงราวหกกลุ่ม
    หมอกกับหมอกน้ำแข็งคนละรูปคือรายละเอียดที่ไม่มีใครอ่านออก
    """
    if code >= 95:
        return "storm"
    if 71 <= code <= 77 or code in (85, 86):
        return "snow"
    if 51 <= code <= 67 or 80 <= code <= 82:
        return "rain"
    if code in (45, 48):
        return "fog"
    if code >= 2:
        return "cloud"
    return "clear"


def shadow_color(clock: str, connected: bool, code: int | None = None) -> str | None:
    """สีเงาใต้เท้าของช่วงเวลานี้ — None เมื่อไม่มีฉาก (ไม่ต่อลิงก์ / ยังไม่รู้เวลา)

    ไม่มีพื้นก็ไม่มีเงา: เงาบนพื้นจอเปล่าอ่านเป็นคราบ ไม่ใช่เงา

    พายุใช้เงาของ night เพราะพื้นดินของมันคือ `ground_night` — เงาจับคู่กับพื้นที่มัน
    ทาบอยู่ ไม่ใช่กับชั่วโมง ถ้าใช้ของช่วงเวลาต่อไปจะได้คราบม่วงบนพื้นเทากลางพายุตอนเย็น
    """
    if not connected:
        return None
    h = hours(clock)
    if h is None:
        return None
    if code is not None and bucket(code) == "storm":
        return SHADOW_COLOR["night"]
    return SHADOW_COLOR[phase_at(h)]


def hours(clock: str) -> float | None:
    """"14:32" -> 14.533 · คืน None เมื่ออ่านไม่ได้

    None ไม่ใช่เที่ยงคืน — มันคือ "ยังไม่รู้เวลา" ซึ่งต้องไม่มีท้องฟ้าเลย
    ตอนบูตก่อน sync ครั้งแรก clock เป็น "--:--" และต้องตกมาทางนี้
    """
    if len(clock) < 5 or clock[2] != ":":
        return None
    if not (clock[0:2].isdigit() and clock[3:5].isdigit()):
        return None
    h, m = int(clock[0:2]), int(clock[3:5])
    if h > 23 or m > 59:
        return None
    return h + m / 60.0


def phase_at(t: float) -> str:
    """ชั่วโมง -> ชื่อช่วง — กระโดดที่ขอบ ไม่ผสมสีระหว่างช่วง"""
    if t < L.sky.dawn_hour or t >= L.sky.night_hour:
        return "night"
    if t < L.sky.day_hour:
        return "dawn"
    if t < L.sky.dusk_hour:
        return "day"
    return "dusk"


def _arc(u: float) -> tuple[float, float]:
    """สัดส่วนของเส้นทาง (0..1) -> จุดกึ่งกลางดวงบนส่วนโค้ง

    ที่ u=0 และ u=1 ดวงอยู่บนเส้นขอบฟ้าพอดี (จมครึ่งดวง) และอยู่นอกจอทั้งสองข้าง

    ความสูงไม่ใช่ sin ล้วน แต่เป็น `sqrt(sin)` — ดวงไต่ขึ้นเร็วกว่าตอนเช้าแล้วค้างสูง
    เพื่อให้มันพ้นหัวมาสคอต (แถบ y 53..120) ตลอดกลางวันจริงๆ ไม่ใช่แค่สี่ชั่วโมงกลางวัน
    · x ยังเป็นเส้นตรงตามเวลา สิ่งที่แบกข้อมูลเวลาจึงไม่ถูกแตะ (ดู layout.toml)
    """
    x = -L.sky.arc_pad + u * (L.screen.width + 2 * L.sky.arc_pad)
    y = HORIZON - math.sqrt(math.sin(math.pi * u)) * L.sky.arc_peak
    return x, y


def disc(t: float) -> tuple[float, float, str]:
    """ชั่วโมง -> (x, y, สี) ของดวงที่อยู่บนฟ้าตอนนั้น

    ดวงอาทิตย์ 05:00->19:00 · ดวงจันทร์ 19:00->05:00 — มีดวงใดดวงหนึ่งเสมอ
    """
    dawn, night = L.sky.dawn_hour, L.sky.night_hour
    if dawn <= t < night:
        x, y = _arc((t - dawn) / (night - dawn))
        low = phase_at(t) in ("dawn", "dusk")
        return x, y, PAL.sun_low if low else PAL.sun
    span = 24 - night + dawn
    u = ((t - night) % 24) / span
    x, y = _arc(u)
    return x, y, PAL.moon


def _draw_disc(draw: ImageDraw.ImageDraw, x: float, y: float, color: str) -> None:
    r = L.sky.disc_r
    x0, y0 = round(x) - r, round(y) - r
    # ตัดที่เส้นขอบฟ้า — ครึ่งล่างของดวงต้องหายไปใต้พื้น ไม่ใช่วาดทับพื้นดิน
    draw.ellipse([x0, y0, x0 + 2 * r, y0 + 2 * r], fill=quantize565(color))


def draw_stars(draw: ImageDraw.ImageDraw, phase: str, cycle: int, kind: str) -> None:
    """ดาวของย่านฟ้า — หน้าอากาศเรียกตัวเดียวกันนี้ ไม่ได้มีสำเนาของตัวเอง

    ใช้ร่วมได้ทั้งดวงเพราะทุกอย่างที่มันตัดสินใจอยู่ใน `[sky]` ล้วน: ตารางดาว จำนวนที่
    กะพริบ และขั้นของ ramp · เส้นขอบฟ้าที่ต่างกันสองหน้าไม่เกี่ยว ดาวทุกดวงอยู่เหนือ
    เส้นที่สูงกว่าอยู่แล้ว
    """
    # พายุไม่มีดาวไม่ว่ากี่โมง — กติกาเดียวกับหน้าอากาศ
    if phase == "day" or kind == "storm":
        return
    stars = L.sky.stars
    base = L.sky.star_px

    def dot(x: int, y: int, color: str, size: int = 0) -> None:
        s = size or base
        # โตออกจากกึ่งกลาง ไม่ใช่ยืดลงขวา — ไม่งั้นดวงที่โตขึ้นอ่านเป็นดาวเลื่อนที่
        off = (s - base) // 2
        draw.rectangle([x - off, y - off, x - off + s - 1, y - off + s - 1],
                       fill=quantize565(color))

    if phase != "night":
        # ฟ้ายังสว่างเกินกว่าจะเห็นทั้งหมด — ดวงแรกๆ สีหรี่ ไม่กะพริบ
        for x, y in stars[: L.sky.low_star_n]:
            dot(x, y, PAL.star_dim)
        return
    # ฟ้าที่ถูกเมฆปิดก็เห็นไม่ครบเหมือนกัน — เหตุที่สอง ไม่ใช่กฎที่สอง: คืนฝนที่ดาวเต็มฟ้า
    # อ่านผิดพอๆ กับดาวเต็มฟ้าตอนหกโมงเย็น · แต่ยังกะพริบ ต่างจากทาง dawn/dusk ข้างบน
    # เพราะกลางคืนที่ bucket เป็น `cloud` ไม่มีทั้งเมฆลอย (กลางคืนไม่มี) และของที่ตกลงมา
    # ดาวที่หยุดกะพริบด้วยจะทำให้จอนิ่งสนิททั้งคืน
    n = L.sky.low_star_n if kind in DECK_KINDS else len(stars)
    # ดวงที่กะพริบไล่สว่างขึ้นแล้วหรี่ลง: dim -> mid -> star(โต) -> mid ขั้นละ 1 วินาที
    # ตั้งต้นที่หรี่แล้วสว่างขึ้น ไม่ใช่ตั้งต้นสว่างแล้วดับ — ดาวดับอ่านเป็นจอเสีย
    # ขั้นสว่างสุดโตเป็น star_peak_px ด้วย: บนแผงจริงความต่างของสีอย่างเดียวจางเกินกว่าจะจับได้
    # i * 3 ทำให้สี่ดวงเริ่มคนละขั้น (0,3,2,1) ไม่กะพริบพร้อมกันเป็นจังหวะเดียว
    peak = L.sky.star_peak_px
    ramp = ((PAL.star_dim, base), (PAL.star_mid, base),
            (PAL.star, peak), (PAL.star_mid, base))
    for i, (x, y) in enumerate(stars[:n]):
        if i < L.sky.twinkle_n:
            dot(x, y, *ramp[(cycle + i * 3) % 4])
        else:
            dot(x, y, PAL.star)


def cloud_color(phase: str, kind: str) -> str | None:
    """สีของก้อนลอยบนหน้ามาสคอต — None คือช่วงที่ไม่มีก้อนลอยเลย

    ก้อนลอยยืมสีของแนวเมฆทุกครั้งที่ฟ้าถูกปิด ไม่ใช่สีเมฆของช่วงเวลา — `cloud_day`
    เกือบขาวสนิท บนฟ้าครึ้มหรือฟ้าพายุมันอ่านเป็นรูรั่วบนเพดาน ไม่ใช่เมฆ

    กลางคืนไม่มีเมฆ และมันเป็นข้อเท็จจริงของ *สี* ไม่ใช่ของตัววาด: `CLOUD_COLOR` ไม่มี
    ช่อง night ตั้งแต่ต้น การถามหาสีเมฆกลางคืนจึงไม่มีคำตอบที่ถูก
    """
    if phase == "night":
        return None
    return _deck_color(phase, kind) if kind != "clear" else CLOUD_COLOR[phase]


def draw_clouds(draw: ImageDraw.ImageDraw, t: float, color: str | None) -> None:
    """ก้อนเมฆลอยผ่านย่านฟ้า — หน้าอากาศเรียกตัวเดียวกันนี้

    รับ *สี* มา ไม่ใช่ `kind` ทั้งที่ทุกตัวเรียกก็หาสีจาก kind อยู่ดี — เพราะสองหน้าหา
    คนละแบบ: หน้ามาสคอตมีชุดฟ้าครึ้ม (`_dull`) หน้าอากาศไม่มี รับ kind มาแล้วหาสีเองที่นี่
    แปลว่าต้องรู้ว่าใครเรียก ซึ่งเป็นวิธีที่สำเนาสองใบเริ่มเลื่อนจากกัน · `None` = ไม่มีเมฆ
    """
    if color is None:
        return
    # ที่ยังต้องมีก้อนลอยอยู่เพราะวันที่ปิดสนิทไม่มีทั้งดาวและของที่ตกลงมา (สายฟ้าไม่กะพริบ)
    # มันจึงเป็นสิ่งเดียวที่ขยับ
    color = quantize565(color)
    pad, span = L.sky.cloud_pad, L.screen.width + 2 * L.sky.cloud_pad
    for base_x, y, w in L.sky.clouds:
        x = (base_x + t * L.sky.cloud_speed_px_s) % span - pad
        # ปัดเป็นพิกเซลเต็มตรงนี้ ไม่ปล่อยให้ backend ตัดสิน — ฝั่ง LVGL รับ int เท่านั้น
        # ถ้า preview วาดที่ x เศษส่วน ตำแหน่งเมฆจะเลื่อนจากบนบอร์ดได้ถึงหนึ่งพิกเซล
        xi = round(x)
        draw.rounded_rectangle([xi, y, xi + w, y + 9], radius=4, fill=color)
        # ก้อนบนทำให้อ่านเป็นเมฆ ไม่ใช่แถบ — เยื้องซ้ายของกึ่งกลาง ไม่ใช่สมมาตร
        bx, bw = round(x + w * 0.2), round(w * 0.45)
        draw.rounded_rectangle([bx, y - 5, bx + bw, y + 4], radius=4, fill=color)


def _deck_color(phase: str, kind: str) -> str:
    """สีของแนวเมฆ/แถบหมอก — สามทาง ไม่ใช่สองทาง ตั้งแต่มีฟ้าครึ้ม"""
    if kind == "storm":
        return PAL.wx_storm_deck
    return PAL.wx_dull_deck if _dull(phase, kind) else DECK_COLOR[phase]


def _draw_deck(draw: ImageDraw.ImageDraw, phase: str, kind: str) -> None:
    """แนวเมฆที่ปิดฟ้าลงมาถึง `deck_bottom` พร้อมก้อนที่ห้อยลงจากก้นแนว

    ตื้นกว่าของหน้าอากาศมาก และเป็นค่าเดียวทุกสภาพ — เหตุผลอยู่ที่ `deck_bottom`
    ใน layout.toml (สรุป: ลึกกว่านี้แล้วฟ้าเลิกบอกเวลา)
    """
    color = quantize565(_deck_color(phase, kind))
    bottom = L.sky.deck_bottom
    draw.rectangle([0, SKY_TOP, L.screen.width - 1, bottom - 1], fill=color)
    for x, w, h in L.sky.deck_lumps:
        # รัศมีเท่าครึ่งความสูงของกล่อง — ก้อนจึงเป็นวงกลมพอดีเมื่อ w == 2h ซึ่งเป็นกฎของ
        # ตารางนี้ (ดู deck_lumps ใน layout.toml) · กว้างกว่านั้นจะได้แคปซูลก้นแบน
        draw.rounded_rectangle([x, bottom - h, x + w - 1, bottom + h - 1], radius=h, fill=color)


def fall_shift(t: float, speed: int) -> int:
    """ของที่ตกเลื่อนลงมากี่พิกเซลแล้ว ณ วินาทีที่ `t` — หน้าอากาศเรียกตัวเดียวกันนี้

    ตัดเป็นจำนวนเต็มตรงนี้แล้วบวกด้วยเลขจำนวนเต็ม ไม่ใช่บวกทศนิยมแล้วค่อยปัด —
    ความเร็วเป็นจำนวนเต็มพิกเซลต่อเฟรมอยู่แล้ว การปัดสองฝั่งจึงไม่มีอะไรให้เถียงกัน
    """
    return int(t * speed)


def _draw_fall(draw: ImageDraw.ImageDraw, phase: str, kind: str, t: float) -> None:
    """สิ่งที่กำลังตกลงมาจากแนวเมฆ — ฝนเป็นแท่งตั้ง หิมะเป็นสี่เหลี่ยมจัตุรัส

    ต่างจากหน้าอากาศที่ฉากนิ่ง: หน้านี้เป็นหน้า idle ที่ค้างอยู่ทั้งคืน (ดู `rain` ใน
    layout.toml) · เม็ดที่เลยเส้นขอบฟ้าถูกพื้นดินตัดเองตอนวาด ไม่ต้องตัดตรงนี้
    """
    top = L.sky.deck_bottom
    span = HORIZON - top
    if kind == "rain":
        color = quantize565(PAL.steel)
        w = L.sky.rain_w
        shift = fall_shift(t, L.sky.rain_speed_px_s)
        for x, base_y, length in L.sky.rain:
            y = top + (base_y - top + shift) % span
            draw.rectangle([x, y, x + w - 1, y + length - 1], fill=color)
        return
    # หิมะบนฟ้าที่สว่างต้องเป็นหมึกเข้ม ไม่ใช่ขาวบนขาว — กติกาเดียวกับหน้าอากาศ
    # แต่ที่นี่เงื่อนไขสั้นกว่า: `sky_is_light` ที่นั่นต้องกันฟ้าพายุออกด้วย ส่วนที่นี่
    # พายุกับหิมะเป็นคนละ bucket อยู่แล้ว เหลือแค่ "ช่วง day ไหม"
    color = quantize565(PAL.wx_flake_ink if phase == "day" else PAL.wx_flake)
    shift = fall_shift(t, L.sky.snow_speed_px_s)
    for x, base_y, s in L.sky.snow:
        y = top + (base_y - top + shift) % span
        draw.rectangle([x, y, x + s - 1, y + s - 1], fill=color)


def _draw_fog(draw: ImageDraw.ImageDraw, phase: str) -> None:
    """แถบหมอกนอนขวางจอ — ไม่มีแนวเมฆ หมอกคือสิ่งที่ *ไม่* มีรูปร่าง"""
    color = quantize565(_deck_color(phase, "fog"))
    for y, h in L.sky.fog_bands:
        draw.rectangle([0, y, L.screen.width - 1, y + h - 1], fill=color)


def _draw_bolt(draw: ImageDraw.ImageDraw) -> None:
    color = quantize565(PAL.accent)
    for x, y, w, h in L.sky.bolt:
        draw.rectangle([x, y, x + w - 1, y + h - 1], fill=color)


def _draw_grass(draw_ctx: ImageDraw.ImageDraw, phase: str, override: str | None = None) -> None:
    """กอหญ้างอกขึ้นจากเส้นขอบฟ้าไปในฟ้า — ก้านกลางสูงสุด ขนาบด้วยก้านสั้นสองข้าง

    งอกขึ้น ไม่ใช่ห้อยลง: หญ้าที่ยื่นลงไปในพื้นอ่านเป็นรอยขีดบนดิน ไม่ใช่ต้นไม้
    และอยู่แค่แถวเดียวบนเส้นขอบฟ้า ไม่ปูลงมาทั้งพื้น เพราะพื้นล่างมีตัวอักษรของ
    แผงโควตาและนาฬิกาใหญ่ทับอยู่ ลายบนพื้นตรงนั้นจะแย่งกับตัวอักษร
    """
    color = quantize565(override or GRASS_COLOR[phase])
    y = HORIZON - 1  # แถวบนสุดของหญ้าอยู่เหนือเส้นขอบฟ้าหนึ่งพิกเซล = โคนติดพื้นพอดี
    for i, x in enumerate(L.sky.grass_x):
        # ความสูงวนตามลำดับกอ — กอสูงเท่ากันหมดอ่านเป็นรั้ว ไม่ใช่หญ้า
        main, side = 3 + i % 4, 2 + i % 3
        # ก้านหนา 2px เว้นช่อง 1px — ก้าน 1px หายไปเลยบนแผงจริง (ต่างจาก preview
        # ที่ขยาย 3 เท่า) และช่องว่าง 1px คือสิ่งที่ทำให้ยังอ่านเป็นกอ ไม่ใช่แถบทึบ
        draw_ctx.rectangle([x, y - main, x + 1, y], fill=color)
        draw_ctx.rectangle([x - 3, y - side, x - 2, y], fill=color)
        draw_ctx.rectangle([x + 3, y - (2 + (side + 1) % 3), x + 4, y], fill=color)


def draw(draw_ctx: ImageDraw.ImageDraw, clock: str, connected: bool, t: float,
         code: int | None = None) -> None:
    """วาดท้องฟ้า + พื้นดินลงในแถบ slot

    `t` = เวลาสัมบูรณ์เป็นวินาทีของฉาก ใช้กับเมฆ การกะพริบ และของที่ตกลงมา
    ส่วนช่วงเวลาของฟ้ามาจาก `clock` ล้วนๆ

    `code` = รหัส WMO จากเฟรมของหน้าอากาศที่บอร์ดแคชไว้ · **None คือไม่มีอากาศที่ใช้ได้**
    ซึ่งเกิดได้สามทางและทั้งสามทางต้องได้ผลเดียวกันคือฟ้าตามเวลาแบบเดิม: ยังไม่เคยได้
    เฟรมเลย · ผู้ใช้ปิดหน้าอากาศ · หรือเฟรมเก่าเกิน `ct_weather_is_stale` (2.5 ชม.)
    ข้อสุดท้ายสำคัญที่สุด — หน้านี้ไม่มีบรรทัดอายุมาแก้ต่างให้แบบหน้าอากาศ ฝนที่หยุดไป
    สามชั่วโมงแล้วจึงเป็นคำโกหกที่ไม่มีอะไรมาถ่วง

    ไม่ต่อลิงก์ = ไม่วาดอะไรเลย ปล่อยให้เป็นพื้นจอเดิม — clock ที่ค้างอยู่ไม่ใช่เวลาจริง
    อีกต่อไป ท้องฟ้าที่ยังสวยอยู่จะกลบสัญญาณว่าขาดการติดต่อ และโกหกเรื่องเวลาด้วย
    """
    if not connected:
        return
    h = hours(clock)
    if h is None:
        return
    phase = phase_at(h)
    kind = "clear" if code is None else bucket(code)
    W = L.screen.width
    # ฟ้าพายุแทนสีของช่วงเวลาทั้งย่าน เหมือนหน้าอากาศเป๊ะ — ผู้ใช้ปัดระหว่างสองหน้านี้
    # พายุที่มืดสนิทหน้าหนึ่งแต่ฟ้าใสอีกหน้าอ่านเป็นข้อมูลขัดกัน ไม่ใช่สองมุมมอง
    # ที่นี่ไม่มีตัวอักษรอยู่ในย่านฟ้าเลย (card.top = 144, แผงโควตา/นาฬิกาอยู่บนพื้นดิน)
    # การกลับขั้วหมึกแบบ ADR-0009 จึงไม่ลามมาถึงหน้านี้ สิ่งเดียวที่ยืนบนฟ้าคือมาสคอต
    base = PAL.wx_storm_sky if kind == "storm" else (
        PAL.wx_dull_sky if _dull(phase, kind) else SKY_COLOR[phase])
    draw_ctx.rectangle([0, SKY_TOP, W - 1, HORIZON - 1], fill=quantize565(base))

    draw_stars(draw_ctx, phase, int(t), kind)
    # เมฆก่อนดวง ไม่ใช่ดวงก่อนเมฆ — ตำแหน่งดวงคือเวลา ส่วนเมฆเป็นของประดับที่ลอยผ่าน
    # เมื่อส่วนโค้งถูกดันขึ้น ดวงกับเมฆก้อนสูงมาอยู่ย่านเดียวกัน แล้วเมฆขาวก็กินดวงไป
    # ทั้งดวงนานหลายสิบวินาทีต่อรอบ · ของที่บังนาฬิกาได้มีได้อย่างเดียวคือตัวละคร
    draw_clouds(draw_ctx, t, cloud_color(phase, kind))
    x, y, color = disc(h)
    # ตอนพายุดวงอาทิตย์ใช้สีของดวงที่เตี้ย ไม่ใช่สีเที่ยงวัน — ดวงยังต้องอยู่เพราะมันคือ
    # นาฬิกา แต่ดวงสีเต็มบนฟ้าพายุอ่านเป็นข้อผิดพลาด ไม่ใช่แดดที่ส่องผ่านเมฆหนา
    # ดวงจันทร์ไม่ต้องแตะ มันหรี่อยู่แล้วและกลางคืนไม่มีเมฆลอยมาเทียบให้เห็นความสว่าง
    if kind == "storm" and color == PAL.sun:
        color = PAL.sun_low
    _draw_disc(draw_ctx, x, y, color)

    # แนวเมฆเป็นข้อยกเว้นเดียวของกติกา "ห้ามอะไรบังดวง" — และมันบังได้ *ทั้งดวง*
    # ฟ้าที่ปิดสนิทแต่ยังเห็นดวงอาทิตย์คือฟ้าที่ขัดแย้งกับตัวเอง ฉากนี้บอกสภาพตอนนี้
    # ส่วนเวลามีนาฬิกาบนแถบบนอยู่แล้ว (เคยตั้งเพดานไว้ไม่ให้บังหมด แล้วกลับคำ — ดู
    # `deck_bottom` ใน layout.toml) · เมฆลอยยังอยู่ใต้ deck ตามเดิม ไม่ได้ถูกแทน:
    # กลางวันที่ฟ้าปิดและไม่มีอะไรตกลงมาต้องยังมีอะไรขยับ ไม่งั้นจอนิ่งสนิททั้งวัน
    if kind in DECK_KINDS:
        _draw_deck(draw_ctx, phase, kind)
    if kind in ("rain", "snow"):
        _draw_fall(draw_ctx, phase, kind, t)
    if kind == "fog":
        _draw_fog(draw_ctx, phase)
    if kind == "storm":
        _draw_bolt(draw_ctx)

    # พื้นดินวาดทับหลังสุด — ครึ่งล่างของดวงและเมฆที่ต่ำเกินไปจึงถูกตัดที่เส้นขอบฟ้าเอง
    # และฝนที่ตกถึงพื้นก็หายไปที่เส้นนั้นเอง ไม่ต้องมีใครตัดให้
    ground = PAL.ground_night if kind == "storm" else GROUND_COLOR[phase]
    draw_ctx.rectangle([0, HORIZON, W - 1, GROUND_BOTTOM - 1], fill=quantize565(ground))
    # พายุยืมหญ้าของ dusk ไม่ใช่ของ night ด้วยเหตุผลที่หน้าอากาศบันทึกไว้แล้ว:
    # เกณฑ์ของสีหญ้าคือ 2:1 กับฟ้าของช่วงนั้น และฟ้าพายุที่ขอบฟ้าคือแถบสว่างค้าง
    if kind == "storm":
        _draw_grass(draw_ctx, "dusk")
    elif _dull(phase, kind):
        # หญ้าของฟ้าครึ้มไม่ใช่หญ้าของช่วงไหนเลย — เกณฑ์คือ 2:1 กับฟ้า *ที่มันยืนอยู่หน้า*
        _draw_grass(draw_ctx, phase, PAL.wx_dull_grass)
    else:
        _draw_grass(draw_ctx, phase)
