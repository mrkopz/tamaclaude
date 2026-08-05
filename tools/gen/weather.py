"""หน้าอากาศทั้งใบ — พอร์ตคู่กับ firmware/main/ct_weather_ui.c

ค่าคงที่ทั้งหมดมาจาก layout.toml ชุดเดียวกับ firmware ถ้าภาพที่นี่ต่างจากบนบอร์ด
แปลว่าเป็นบั๊ก renderer ไม่ใช่ค่าคงที่ไม่ตรงกัน

หน้านี้มีสองย่านที่กติกาสีคนละชุด (ADR-0009): ย่านฟ้าซึ่งพื้นสว่างได้และหมึกต้องกลับขั้ว
กับย่านพื้นดินซึ่งเข้มเสมอ ทุกอย่างที่ตัดสินว่า "ย่านบนสว่างหรือยัง" อยู่ที่ `sky_is_light`
ที่เดียว และฝั่ง C ก็มีฟังก์ชันชื่อเดียวกัน
"""

from __future__ import annotations

from dataclasses import dataclass, field

from PIL import Image, ImageDraw

from . import footer, pages, screen, sky, topbar
from .config import L, PAL
from .rects import Rect, RectList
from .render import draw_rects, quantize565

# กลุ่มสภาพอากาศกับสีแนวเมฆอยู่ที่ `gen/sky.py` แล้ว ตั้งแต่หน้ามาสคอตใช้มันด้วย
# (ADR-0012) — ที่นี่แค่ยืมชื่อมาให้โค้ดเดิมในไฟล์นี้เรียกได้เหมือนเดิม
bucket = sky.bucket
DECK_COLOR = sky.DECK_COLOR


def _cloud(color: str) -> RectList:
    return [
        Rect(1.0, 3.6, 8.0, 2.8, color, 1.4),
        Rect(2.4, 2.0, 3.4, 3.0, color, 1.5),
        Rect(5.0, 2.6, 3.0, 2.6, color, 1.3),
    ]


def is_night(h: float | None) -> bool:
    """ชั่วโมงนี้ดวงบนฟ้าเป็นดวงจันทร์ไหม — ต้องตรงกับ is_night() ใน ct_weather_ui.c

    ขอบเดียวกับที่ `sky.disc` ใช้เลือกระหว่างดวงอาทิตย์กับดวงจันทร์ ไม่ใช่ขอบใหม่:
    ไอคอนที่มีดวงอาทิตย์อยู่ข้างฟ้ากลางคืนที่เต็มไปด้วยดาวคืออุปกรณ์ที่ขัดแย้งกับตัวเอง
    ไม่รู้เวลา (None) = กลางวัน ไม่ใช่กลางคืน — ดวงอาทิตย์เป็นรูปที่อ่านออกโดยไม่ต้องมีบริบท
    """
    return h is not None and not (L.sky.dawn_hour <= h < L.sky.night_hour)


def icon(code: int, connected: bool = True, night: bool = False) -> RectList:
    """สัญลักษณ์สภาพอากาศหนึ่งชุด — ต้องตรงกับ build_icon() ใน ct_weather_ui.c"""
    # หลุดลิงก์แล้วสัญลักษณ์เป็นเทา เหมือนมาสคอตที่หลุด — ตัวเลขที่ค้างอยู่ยังอ่านได้
    # แต่ต้องไม่อ่านว่าเป็นตอนนี้
    cloud = PAL.cloud_day if connected else PAL.gray
    sun = (PAL.moon if night else PAL.sun) if connected else PAL.gray
    wet = PAL.steel if connected else PAL.gray_dark
    bolt = PAL.accent if connected else PAL.gray_dark
    flake = PAL.text if connected else PAL.gray_dark

    kind = bucket(code)
    if kind == "clear":
        # ดวงกลมกับรังสีสี่ทิศ — ไม่ใช่แปดทิศ เพราะที่ 50px รังสีทแยงกลืนกับดวง
        # ดวงจันทร์ไม่มีรังสี: รังสีคือสิ่งที่ทำให้วงกลมอ่านเป็น "ดวงอาทิตย์" ไม่ใช่ "วงกลม"
        # ถ้าเหลือรังสีไว้แล้วเปลี่ยนแค่สี กลางคืนจะอ่านเป็นดวงอาทิตย์ซีด ไม่ใช่ดวงจันทร์
        if night:
            # ดวงจันทร์ + ดาวสามดวง — ดวงกลมเปล่าๆ ที่ 20px (คอลัมน์พยากรณ์) อ่านเป็นจุด
            # หัวข้อ ไม่ใช่ดวงจันทร์ · ดาวคือสิ่งที่บอกว่านี่คือ *ฟ้ากลางคืนที่โล่ง* และมันทำ
            # หน้าที่เดียวกับรังสีของดวงอาทิตย์: เปลี่ยนวงกลมให้เป็นเวลาของวัน
            # ไม่ใช้วิธีแหว่งเสี้ยว เพราะการแหว่งต้องวาดทับด้วยสีพื้นหลัง ซึ่งไอคอนนี้ไม่รู้
            # (มันอยู่บนฟ้าสี่ช่วงและบนพื้นดินอีกสี่สีในแถบพยากรณ์)
            return [
                Rect(2.2, 2.8, 5.0, 5.0, sun, 2.5),
                Rect(8.0, 1.0, 1.4, 1.4, flake, 0.2),
                Rect(6.8, 4.6, 1.0, 1.0, flake),
                Rect(8.4, 7.0, 1.2, 1.2, flake, 0.2),
            ]
        return [Rect(2.5, 2.5, 5.0, 5.0, sun, 2.5)] + [
            Rect(4.6, 0.2, 0.8, 1.6, sun),
            Rect(4.6, 8.2, 0.8, 1.6, sun),
            Rect(0.2, 4.6, 1.6, 0.8, sun),
            Rect(8.2, 4.6, 1.6, 0.8, sun),
        ]
    if kind == "cloud":
        # เมฆบังดวงบางส่วน — เมฆล้วนแยกไม่ออกจากหมอกที่ระยะโต๊ะ
        return [Rect(5.6, 0.2, 3.6, 3.6, sun, 1.8)] + _cloud(cloud)
    if kind == "fog":
        # สามขีดนอน ไม่มีเมฆ — หมอกคือสิ่งที่ *ไม่* มีรูปร่าง
        return [Rect(1.0 + (i % 2) * 0.8, 2.6 + i * 2.2, 7.4, 1.0, cloud, 0.5) for i in range(3)]
    if kind == "rain":
        return _cloud(cloud) + [
            Rect(2.2 + i * 2.4, 7.0, 0.9, 2.4, wet, 0.45) for i in range(3)
        ]
    if kind == "snow":
        return _cloud(cloud) + [
            Rect(2.2 + i * 2.4, 7.4, 1.4, 1.4, flake, 0.7) for i in range(3)
        ]
    # storm — สายฟ้าเป็นสองชิ้นเยื้องกัน ชิ้นเดียวอ่านเป็นเสาไฟ
    return _cloud(cloud) + [
        Rect(4.6, 6.8, 1.6, 1.8, bolt),
        Rect(3.8, 8.0, 1.6, 1.8, bolt),
    ]


# แนวเมฆของแต่ละกลุ่ม — ต้องตรงกับ DECK_BOTTOM ใน ct_weather_ui.c
# `clear` กับ `fog` ไม่มีแนวเมฆ: ฟ้าโล่งคือฟ้าที่ไม่มีอะไรปิด ส่วนหมอกเป็นแถบนอน
DECK_BOTTOM = {
    "cloud": L.weather.deck_cloud_y,
    "rain": L.weather.deck_wet_y,
    "snow": L.weather.deck_wet_y,
    "storm": L.weather.deck_storm_y,
}


@dataclass(slots=True)
class Hour:
    """หนึ่งช่องของแถบพยากรณ์ — ชั่วโมงมาจาก `hour_start` ของเฟรม ไม่ได้อยู่ในตัวมันเอง"""

    temp: int
    code: int


@dataclass(slots=True)
class Weather:
    """หน้าอากาศหนึ่งใบ — `place` ว่างและ `has_frame=False` คือยังไม่เคยได้ข้อมูลเลย"""

    place: str = "Bangkok"
    temp: int = 31
    high: int = 34
    low: int = 26
    code: int = 61
    unit: str = "C"
    age: int = 420
    # ชั่วโมงของช่องแรกในแถบพยากรณ์ (0..23) — -1 คือเฟรมนี้ไม่มีพยากรณ์มาด้วย
    # เป็นชั่วโมง *สัมบูรณ์* ไม่ใช่ offset จึงไม่เพี้ยนเมื่อเฟรมค้างอยู่นาน
    hour_start: int = 15
    hours: list[Hour] = field(default_factory=lambda: [
        Hour(32, 0), Hour(33, 1), Hour(33, 3), Hour(31, 61), Hour(30, 61),
    ])
    # มี snapshot สดอยู่ไหม — ตรงกับ ct_weather_ui_set_connected
    connected: bool = True
    # เคยได้ page frame ของหน้านี้แล้วหรือยัง (ADR-0002)
    has_frame: bool = True
    # ท่าของมาสคอตจิ๋วมุมจอ — None = ไม่มี session เลย ซึ่งคือท่าหลับ
    mascot_state: str | None = None
    # แถบบน — มาจาก snapshot ของหน้ามาสคอต ไม่ใช่จากเฟรมของหน้านี้ (`gen/topbar.py`)
    bar: topbar.Bar = field(default_factory=topbar.Bar)


def scene_phase(w: Weather) -> str | None:
    """ช่วงเวลาของฉาก — None = ไม่มีฉากเลย ปล่อยให้เป็นพื้นจอเปล่า

    ต้องตรงกับ scene_phase() ใน ct_weather_ui.c

    เวลามาจากนาฬิกาบนแถบบน ไม่ได้อยู่ในเฟรมของหน้านี้ — Mac ส่งเวลามาทุกวินาทีอยู่แล้ว
    ส่วนเฟรมอากาศมาทุก 15 นาที การใส่เวลาลงไปด้วยคือสำเนาที่เก่ากว่าอีกใบ

    หลุดลิงก์แล้วไม่มีฉาก กติกาเดียวกับ `sky.draw` และการ์ดปฏิทิน — ฉากที่ยังสวยอยู่จะกลบ
    สัญญาณว่าขาดการติดต่อ และโกหกเรื่องเวลาไปพร้อมกัน · ยังไม่เคยได้เฟรมก็ไม่มีฉาก:
    ฟ้าที่สวยรอบตัวเลขที่ไม่มีอยู่จริงอ่านเป็นหน้าที่โหลดไม่เสร็จ ไม่ใช่หน้าที่ยังไม่มีข้อมูล
    """
    if not w.connected or not w.has_frame:
        return None
    h = sky.hours(w.bar.clock)
    return None if h is None else sky.phase_at(h)


def sky_is_light(phase: str | None, kind: str) -> bool:
    """ย่านฟ้าตอนนี้พื้นสว่างหรือยัง — ต้องตรงกับ sky_is_light() ใน ct_weather_ui.c

    บรรทัดเดียวนี้คือทั้งหมดที่ตัดสินว่าตัวหนังสือในย่านฟ้าเป็นชุด `text` หรือชุด `ink`
    ถ้ามันแตกเป็นหลายเงื่อนไขเมื่อไร จะมีสภาพหนึ่งที่เลข 48px กลืนหายไปกับพื้นโดยไม่มีใคร
    เจอจนกว่าจะถึงชั่วโมงนั้นของวันที่อากาศแบบนั้นพอดี

    พายุไม่นับเป็นกลางวันไม่ว่ากี่โมง เพราะฉากพายุแทนที่สีฟ้าทั้งย่านด้วยฟ้ามืดของมันเอง
    (ดู `wx_storm_sky`) — ถ้าปล่อยให้พายุตอนเที่ยงยังใช้ฟ้าสว่าง เพดานดำจะกินแค่ครึ่งบน
    แล้วเลขใหญ่ก็ต้องเป็นสองสีพร้อมกัน
    """
    return phase == "day" and kind != "storm"


def _deck(draw: ImageDraw.ImageDraw, kind: str, phase: str, top: int) -> None:
    """แนวเมฆที่ปิดฟ้าลงมาถึง `DECK_BOTTOM[kind]` พร้อมก้อนที่ห้อยลงจากก้นแนว"""
    color = quantize565(PAL.wx_storm_deck if kind == "storm" else DECK_COLOR[phase])
    bottom = DECK_BOTTOM[kind]
    draw.rectangle([0, top, L.screen.width - 1, bottom - 1], fill=color)
    for x, w, h in L.weather.deck_lumps:
        # รัศมีเท่าครึ่งความลึก — ก้อนจึงเป็นครึ่งวงกลมพอดี ไม่ใช่สี่เหลี่ยมมุมมน
        draw.rounded_rectangle([x, bottom - h, x + w - 1, bottom + h - 1],
                               radius=h, fill=color)


def _fall(draw: ImageDraw.ImageDraw, kind: str, light: bool) -> None:
    """สิ่งที่กำลังตกลงมาจากแนวเมฆ — ฝนเป็นแท่งตั้ง หิมะเป็นสี่เหลี่ยมจัตุรัส"""
    if kind == "rain":
        color = quantize565(PAL.steel)
        w = L.weather.rain_w
        for x, y, length in L.weather.rain:
            draw.rectangle([x, y, x + w - 1, y + length - 1], fill=color)
        return
    color = quantize565(PAL.wx_flake_ink if light else PAL.wx_flake)
    for x, y, s in L.weather.snow:
        draw.rectangle([x, y, x + s - 1, y + s - 1], fill=color)


def _scene(draw: ImageDraw.ImageDraw, w: Weather, phase: str, kind: str) -> None:
    """ฟ้าของชั่วโมงนี้ + สภาพอากาศที่กำลังเกิดบนมัน + พื้นดินใต้เส้นขอบฟ้า

    ต้องตรงกับ draw_scene() ใน ct_weather_ui.c

    ทุกชิ้นวาดก่อนตัวหนังสือและทับกันได้ ไม่มีการกันพื้นที่ไว้ให้ — สิ่งที่ทำให้มันไม่กวนคือ
    ค่าความต่าง (แนวเมฆ ~1.8:1 กับฟ้า · ตัวหนังสือ 7:1 ขึ้นไป) หลักเดียวกับการ์ดปฏิทิน
    ฉากที่หลบตัวหนังสือจะเหลือแค่มุมจอ แล้วมันก็ไม่ใช่ฟ้าอีกต่อไป

    ฉากไม่ขยับ ต่างจากฟ้าหน้ามาสคอตที่เมฆลอยและดาวกะพริบ — หน้านั้นคือหน้า idle ที่การ
    เคลื่อนไหวเป็นสิ่งเดียวที่บอกว่าเครื่องยังมีชีวิต ส่วนหน้านี้อยู่บนจอรอบละ 20 วินาที
    และมีตัวเลขที่ต้องอ่านอยู่แล้ว · ฝนอ่านเป็นฝนจากทิศทางกับการซ้ำ ไม่ใช่จากการเคลื่อนที่
    """
    top, horizon = L.topbar.height, L.weather.horizon
    W = L.screen.width
    base = PAL.wx_storm_sky if kind == "storm" else sky.SKY_COLOR[phase]
    draw.rectangle([0, top, W - 1, horizon - 1], fill=quantize565(base))

    # ดาวก่อนแนวเมฆ — เมฆที่ปิดฟ้าต้องบังดาวได้ ไม่ใช่ลอยอยู่ใต้มัน
    # พายุไม่มีดาวไม่ว่ากี่โมง และกลางวันก็ไม่มีอยู่แล้ว
    if kind != "storm" and phase != "day":
        n = len(L.sky.stars) if phase == "night" else L.sky.low_star_n
        color = quantize565(PAL.star if phase == "night" else PAL.star_dim)
        s = L.sky.star_px
        for x, y in L.sky.stars[:n]:
            draw.rectangle([x, y, x + s - 1, y + s - 1], fill=color)

    if kind in DECK_BOTTOM:
        _deck(draw, kind, phase, top)
    if kind in ("rain", "snow"):
        _fall(draw, kind, sky_is_light(phase, kind))
    if kind == "fog":
        # หมอกไม่มีแนวเมฆ — แถบนอนที่หนาขึ้นเมื่อเข้าใกล้ขอบฟ้า
        color = quantize565(DECK_COLOR[phase])
        for y, h in L.weather.fog_bands:
            draw.rectangle([0, y, W - 1, y + h - 1], fill=color)
    if kind == "storm":
        color = quantize565(PAL.accent)
        for x, y, bw, bh in L.weather.bolt:
            draw.rectangle([x, y, x + bw - 1, y + bh - 1], fill=color)

    # พื้นดินวาดทับหลังสุด — สิ่งที่ตกต่ำเกินเส้นขอบฟ้าจึงถูกตัดที่เส้นนั้นเอง
    ground = PAL.ground_night if kind == "storm" else sky.GROUND_COLOR[phase]
    draw.rectangle([0, horizon, W - 1, L.screen.height - 1], fill=quantize565(ground))
    # กอหญ้าชุดเดียวกับหน้ามาสคอต แต่เส้นขอบฟ้าคนละเส้น — สีของมันถูกจูนให้ได้ 2:1 กับ
    # *ฟ้า* ของช่วงนั้น (ดู grass_* ใน palette) ซึ่งยังจริงอยู่ที่นี่ ฟ้าเป็นชุดเดียวกัน
    # พายุยืมหญ้าของ dusk ไม่ใช่ของ night ทั้งที่ฟ้ามัน *มืด* — เกณฑ์ของสีหญ้าคือ 2:1
    # กับฟ้าของช่วงนั้น (ดู grass_* ใน palette) และฟ้าพายุที่ขอบฟ้าคือแถบสว่างค้าง
    # ไม่ใช่ฟ้ากลางคืนที่เกือบดำ · grass_night ตรงนั้นได้ 1.2:1 คือหายไปทั้งแถว
    # ส่วน grass_dusk เป็นเงาตัดขอบ ซึ่งเป็นสิ่งที่ตาเห็นจริงเมื่อมีแสงค้างอยู่หลังต้นไม้
    grass = quantize565(PAL.grass_dusk if kind == "storm" else sky.GRASS_COLOR[phase])
    y = horizon - 1
    for i, x in enumerate(L.sky.grass_x):
        main, side = 3 + i % 4, 2 + i % 3
        draw.rectangle([x, y - main, x + 1, y], fill=grass)
        draw.rectangle([x - 3, y - side, x - 2, y], fill=grass)
        draw.rectangle([x + 3, y - (2 + (side + 1) % 3), x + 4, y], fill=grass)


def fc_center(i: int) -> int:
    """กึ่งกลางคอลัมน์ที่ i ของแถบพยากรณ์ — ต้องตรงกับ fc_center() ใน ct_weather_ui.c"""
    return i * L.weather.fc_col_w + L.weather.fc_col_w // 2


def _forecast(draw: ImageDraw.ImageDraw, w: Weather) -> None:
    """ห้าชั่วโมงข้างหน้าบนพื้นดิน — เข้มเสมอ จึงไม่ต้องสลับขั้วสีตามฟ้า

    เฟรมที่ไม่มีพยากรณ์ (host รุ่นก่อน หรือถูกบีบทิ้งเพราะชื่อเมืองยาว) ไม่วาดอะไรตรงนี้เลย
    ซึ่งไม่ใช่จอเปล่าตาม ADR-0002: ยังมีพื้นดิน กอหญ้า และบรรทัดอายุอยู่
    """
    if w.hour_start < 0 or not w.hours:
        return
    wx = L.weather
    text = PAL.text if w.connected else PAL.gray
    dim = PAL.text_dim if w.connected else PAL.gray_dark
    for i, hour in enumerate(w.hours[: wx.fc_cols]):
        cx = fc_center(i)
        # ชั่วโมงมีทวิภาคเสมอ — "15" เปล่าๆ อยู่เหนือ "32" อ่านเป็นตัวเลขสองแถวที่ต้องเดา
        # ว่าอันไหนคือเวลา ส่วน "15:00" ไม่มีใครอ่านเป็นอุณหภูมิ
        screen.line(draw, (cx, wx.fc_hour_y), f"{(w.hour_start + i) % 24:02d}:00",
                    pil=10, board=wx.fc_hour_font, fill=dim, anchor="mt")
        # แต่ละคอลัมน์รู้ชั่วโมงของตัวเอง จึงเลือกดวงของตัวเองได้ — แถบที่ข้ามพระอาทิตย์ตก
        # จะเห็นดวงอาทิตย์กลายเป็นดวงจันทร์ตรงชั่วโมงที่มันตกจริง
        rects = icon(hour.code, w.connected, is_night(float((w.hour_start + i) % 24)))
        draw_rects(draw, rects, wx.fc_icon_px,
                   cx - wx.icon_grid * wx.fc_icon_px / 2, wx.fc_icon_y)
        screen.line(draw, (cx, wx.fc_temp_y), str(hour.temp),
                    pil=12, board=wx.fc_temp_font, fill=text, anchor="mt")


def _footer(draw: ImageDraw.ImageDraw, w: Weather, pos: footer.Pos | None,
            phase: float, cycle: int, *, has_frame: bool = True) -> None:
    footer.draw(draw, pos or footer.Pos(), secs=w.age, refresh_s=L.weather.refresh_s,
                state=w.mascot_state, connected=w.connected, phase=phase, cycle=cycle,
                has_frame=has_frame)


def render(w: Weather, phase: float = 0.0, cycle: int = 0,
           pos: footer.Pos | None = None) -> Image.Image:
    img = Image.new("RGB", (L.screen.width, L.screen.height), quantize565(PAL.bg))
    draw = ImageDraw.Draw(img)

    kind = bucket(w.code) if w.has_frame else "cloud"
    scene = scene_phase(w)
    if scene is not None:
        _scene(draw, w, scene, kind)
    light = sky_is_light(scene, kind)

    # หน้านี้ไม่เคยแสดงเวลาหรือโควตาเอง แถบจึงพูดครบเสมอ (ดู `topbar.draw`)
    # วาดหลังฉากเพราะฉากกินตั้งแต่ขอบล่างของแถบลงมา ไม่ได้ทับแถบ แต่ต้องอยู่ชั้นบนเสมอ
    # ฝั่งบอร์ดแถบอยู่นอกทุกหน้าและสร้างเป็นตัวสุดท้าย ซึ่งให้ผลเดียวกัน
    topbar.draw(draw, w.bar, page=pages.LABELS["weather"], connected=w.connected)

    draw_rects(draw, icon(w.code if w.has_frame else 3, w.has_frame and w.connected,
                          is_night(sky.hours(w.bar.clock))),
               L.weather.icon_px, L.weather.icon_x, L.weather.icon_y)

    if not w.has_frame:
        # ยังไม่เคยได้ข้อมูลของหน้านี้ ต้องมีหน้าตาของตัวเอง ห้ามเป็นจอเปล่า (ADR-0002)
        screen.line(draw, (L.weather.temp_x, L.weather.empty_y), "No weather yet",
                    pil=12, board=14, fill=PAL.text, anchor="lt")
        screen.line(draw, (L.weather.temp_x, L.weather.empty_sub_y),
                    "the mac has not sent this page", pil=10, board=12,
                    fill=PAL.text_dim, anchor="lt")
        _footer(draw, w, pos, phase, cycle, has_frame=False)
        return img

    # ชุดสีของย่านฟ้า — กลับขั้วทั้งชุดเมื่อฟ้าสว่าง ไม่ใช่แค่ตัวหลัก
    if light:
        text, dim = PAL.ink, PAL.ink_dim
    else:
        text, dim = PAL.text, PAL.text_dim
    if not w.connected:
        text, dim = PAL.gray, PAL.gray

    screen.line(draw, (L.weather.place_x, L.weather.place_y), w.place,
                 pil=12, board=14, fill=text, anchor="lt",
                 max_w=L.weather.icon_x - L.weather.place_x - 8)
    # ไม่มีสัญลักษณ์องศาในฟอนต์บนบอร์ด และการประดิษฐ์วงแหวนจาก rect ขึ้นมาเองเพื่อสิ่งที่
    # ไม่มีใครอ่านผิดคือค่าใช้จ่ายที่ไม่คุ้ม — "31C" อ่านออกทันที
    draw.text((L.weather.temp_x, L.weather.temp_y + 24), f"{w.temp}{w.unit}",
              font=screen.font(L.weather.temp_font_pil),
              fill=quantize565(text), anchor="lm")
    screen.line(draw, (L.weather.hilo_x, L.weather.hilo_y),
                 f"H {w.high}   L {w.low}", pil=12, board=14, fill=dim, anchor="lt")

    _forecast(draw, w)
    _footer(draw, w, pos, phase, cycle)
    return img
