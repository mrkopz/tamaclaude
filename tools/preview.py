#!/usr/bin/env python3
"""เรนเดอร์ทุกสถานะและจอทั้งใบเป็น PNG/GIF — dev loop ที่ไม่ต้องแตะบอร์ด

    python3 tools/preview.py           สร้างทุกอย่างลง out/
    python3 tools/preview.py --sheet   เฉพาะ contact sheet
    python3 tools/preview.py --limits  วัดว่าแต่ละป้ายรับได้กี่ช่อง (ที่มาของ Text.Limit)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))

from gen import calendar, crypto, mascot, screen, stocks, topbar, weather  # noqa: E402
from gen.config import L, PAL, REPO_DIR  # noqa: E402
from gen.props import BOX_X0, BOX_X1, BOX_Y0, BOX_Y1  # noqa: E402
from gen.render import quantize565, render_rects  # noqa: E402

OUT = REPO_DIR / "out"
# BOX_Y1 คือระดับฝ่าเท้าพอดี และไม่มีอะไรยื่นต่ำกว่านั้นอีกแล้ว
BOX = (BOX_X0, BOX_Y0, BOX_X1, BOX_Y1)
SESSION_WINDOW = L.usage.session_window
WEEKLY_WINDOW = L.usage.weekly_window
FRAMES = 12  # เฟรมต่อหนึ่งลูป (~1 วินาที)
LOOPS = 4  # GIF ยาวหลายลูป ไม่งั้นจะไม่มีวันเห็นการกะพริบตา
# ฉากมาสคอตเดินเล่น: หนึ่งเที่ยว = (320 + 2*96) / 34 + 2.5 ~ 17.6 วินาที
STROLL_LOOPS = 18


def _cell(state: str, phase: float, px: int, connected: bool = True,
          cycle: int = 0) -> Image.Image:
    return render_rects(
        mascot.build_centered(state, phase, connected, cycle), px, BOX, PAL.bg_slot
    )


def contact_sheet(px: int = 7, cols: int = 6) -> Image.Image:
    """ทุกสถานะเรียงในภาพเดียว — ใช้ตัดสินว่ามาสคอตสื่ออารมณ์ได้จริงไหม"""
    states = mascot.all_states()
    cw = round((BOX_X1 - BOX_X0) * px)
    ch = round((BOX_Y1 - BOX_Y0) * px)
    pad, label_h = 8, 16
    rows = (len(states) + cols - 1) // cols
    W = cols * (cw + pad) + pad
    H = rows * (ch + label_h + pad) + pad
    sheet = Image.new("RGB", (W, H), quantize565(PAL.bg))
    draw = ImageDraw.Draw(sheet)
    for i, st in enumerate(states):
        cx = pad + (i % cols) * (cw + pad)
        cy = pad + (i // cols) * (ch + label_h + pad)
        sheet.paste(_cell(st, 0.25, px), (cx, cy))
        draw.text((cx + cw / 2, cy + ch + label_h / 2), st, font=screen.font(12),
                  fill=quantize565(PAL.text), anchor="mm")
    return sheet


def state_gif(state: str, px: int = 7, connected: bool = True) -> list[Image.Image]:
    return [
        _cell(state, (f % FRAMES) / FRAMES, px, connected, f // FRAMES)
        for f in range(FRAMES * LOOPS)
    ]


SCENES: dict[str, screen.Screen] = {
    "busy": screen.Screen(
        sessions=[
            screen.Session("tamaclaude", "writing", 0.0),
            screen.Session("tamaclaude", "building", 0.3),
            screen.Session("sprite-gen", "reading", 0.6),
        ],
        overflow=3,
        cards=[
            screen.Card("tamaclaude", "needs permission to run git push", "alert"),
            screen.Card("infra-scripts", "Stopped - waiting for your reply", "info"),
            screen.Card("sprite-gen", "Build finished, 0 warnings", "done"),
        ],
        usage=[
            screen.Usage("Current", SESSION_WINDOW, 88, 42 * 60),
            screen.Usage("Weekly", WEEKLY_WINDOW, 61, 3 * 86400),
        ],
    ),
    "idle": screen.Screen(
        sessions=[screen.Session("tamaclaude", "sleeping", 0.0)],
        clock="02:14",
    ),
    # โควตาปกติ — สภาพที่จอจะเป็นเกือบตลอดเวลาที่ไม่มีอะไรต้องเตือน
    "usage": screen.Screen(
        sessions=[
            screen.Session("tamaclaude", "writing", 0.0),
            screen.Session("docs", "reading", 0.4),
        ],
        clock="17:04",
        usage=[
            screen.Usage("Current", SESSION_WINDOW, 35, 3 * 3600 + 5 * 60),
            screen.Usage("Weekly", WEEKLY_WINDOW, 48, 31 * 3600),
        ],
    ),
    # ใกล้เต็มทั้งคู่ + ใช้เร็วกว่าเวลา (ขีด pace อยู่ซ้ายของเนื้อแถบ)
    "usage_hot": screen.Screen(
        sessions=[screen.Session("tamaclaude", "building", 0.0)],
        clock="09:41",
        usage=[
            screen.Usage("Current", SESSION_WINDOW, 92, 4 * 3600 + 20 * 60),
            screen.Usage("Weekly", WEEKLY_WINDOW, 71, 2 * 86400 + 5 * 3600),
        ],
    ),
    # หน้าต่างหมุนไปแล้ว + weekly หายไปทั้งตัว — ทั้งคู่ต้องเป็น `--` ห้ามเดา
    "usage_unknown": screen.Screen(
        sessions=[screen.Session("tamaclaude", "idle", 0.0)],
        clock="06:20",
        usage=[
            screen.Usage("Current", SESSION_WINDOW, None, 0),
            screen.Usage("Weekly", WEEKLY_WINDOW, None, None),
        ],
    ),
    # ภาษาไทยบนการ์ด — วาดด้วยฟอนต์บิตแมปตัวเดียวกับที่แฟลชลงบอร์ด ไม่ใช่ TTF ต้นฉบับ
    # (ADR-0008) ฉากนี้คือที่ที่ตำแหน่งวรรณยุกต์ถูกตัดสินก่อนเห็นของจริง: ที่ (วรรณยุกต์
    # เหนือสระบน) · ปั๊ (ฐานหางสูง) · ญู (สระล่างใต้ฐานหางยาว) อยู่ในบรรทัดเดียวกันหมด
    "thai": screen.Screen(
        sessions=[screen.Session("tamaclaude", "thinking", 0.0)],
        clock="09:41",
        cards=[
            screen.Card("ประชุมทีม", "ที่ปั๊มน้ำมัน 10:30", "info"),
            screen.Card("กตัญญู", "ฝั่งโน้น ญู ฐู ฟ้า ปี", "alert"),
        ],
    ),
    "done": screen.Screen(
        sessions=[
            screen.Session("tamaclaude", "celebrate", 0.0),
            screen.Session("docs", "idle", 0.4),
        ],
        cards=[screen.Card("tamaclaude", "Build finished, 0 warnings", "done")],
    ),
    # มีทั้งการ์ดและตัวเลขโควตาค้างอยู่ในมือ แต่ต้องไม่ขึ้นจอสักอย่าง — หลุดลิงก์แล้ว
    # ไม่มีใครรับรองว่ายังจริง รวมถึงตัวนาฬิกาเอง กลางจอจึงเหลือระยะเวลาที่หลุด
    # (บอร์ดนับเอง) กับเวลาล่าสุดที่เคยได้ยิน พูดเป็นอดีตกาล
    "offline": screen.Screen(
        sessions=[
            screen.Session("tamaclaude", "idle", 0.0),
            screen.Session("docs", "idle", 0.5),
        ],
        connected=False,
        offline_s=4 * 60,
        cards=[screen.Card("tamaclaude", "Needs your answer", "alert")],
        usage=[
            screen.Usage("Current", SESSION_WINDOW, 43, 1 * 3600 + 40 * 60),
            screen.Usage("Weekly", WEEKLY_WINDOW, 8, 5 * 86400 + 8 * 3600),
        ],
    ),
    # BLE หลุด บอร์ดขึ้นเน็ตแล้วแต่ Mac ยังหาไม่เจอ — ข้อมูลบนจอตายเหมือน "offline"
    # ต่างกันที่ไอคอนซึ่งเป็นคลื่น WiFi ส่วนป้ายซ้ายพูดว่า "no link" เหมือนกัน: ที่อยู่ของบอร์ด
    # อยู่ในหน้าตั้งค่าบน Mac ที่เดียว ซึ่งคือที่ที่ผู้ใช้ต้องเอาไปกรอกอยู่แล้ว
    "wifi": screen.Screen(
        sessions=[screen.Session("tamaclaude", "idle", 0.0)],
        connected=False,
        wifi=True,
        offline_s=3 * 3600 + 12 * 60,
        cards=[screen.Card("tamaclaude", "Needs your answer", "alert")],
    ),
    # เพิ่งแฟลชเสร็จ ยังไม่เคยจับคู่กับ Mac เลย — จอแรกที่ผู้ใช้ใหม่เห็น ไม่มีเวลาให้อ้างถึง
    # และตัวเลขที่เดินคือเวลาตั้งแต่เสียบไฟ ซึ่งเป็นคำตอบที่ถูกของ "รออะไรอยู่"
    "cold": screen.Screen(
        sessions=[],
        connected=False,
        clock=screen.CLOCK_UNKNOWN,
        date="",
        offline_s=48,
    ),
    # BLE หลุดแต่ snapshot ยังเดินทางมาทาง LAN — ข้อมูลสดทั้งจอ ไอคอนเป็นคลื่น WiFi
    "lan": screen.Screen(
        sessions=[
            screen.Session("tamaclaude", "writing", 0.0),
            screen.Session("docs", "idle", 0.5),
        ],
        connected=True,
        ble=False,
        wifi=True,
        usage=[
            screen.Usage("Current", SESSION_WINDOW, 43, 1 * 3600 + 40 * 60),
            screen.Usage("Weekly", WEEKLY_WINDOW, 8, 5 * 86400 + 8 * 3600),
        ],
    ),
    # ไม่มี session เลย — มาสคอตเดินข้ามแถบ slot ที่ว่างอยู่
    "empty": screen.Screen(
        sessions=[],
        clock="14:22",
        date="Mon 27 Jul",
        usage=[
            screen.Usage("Current", SESSION_WINDOW, 35, 3 * 3600 + 5 * 60),
            screen.Usage("Weekly", WEEKLY_WINDOW, 48, 31 * 3600),
        ],
    ),
    "waiting": screen.Screen(
        sessions=[
            screen.Session("tamaclaude", "waiting", 0.0),
            screen.Session("tamaclaude", "searching", 0.5),
            screen.Session("sprite-gen", "alert", 0.25),
        ],
        cards=[
            screen.Card("sprite-gen", "Stopped: test suite failed (3 failing)", "alert"),
            screen.Card("tamaclaude", "needs permission to write layout.h", "info"),
        ],
    ),
}


# หน้าอากาศ — หน้าที่สองของจอ วาดจากค่าคงที่ชุดเดียวกับ firmware
# ฉากถูกเลือกให้ครบสิ่งที่ต้องตัดสินด้วยตา: สัญลักษณ์ทุกกลุ่ม · ชื่อเมืองภาษาไทย ·
# อายุข้อมูลที่ยังปกติกับที่เก่าจนต้องตะโกน · หน้าที่ยังไม่เคยได้ข้อมูล · ลิงก์หลุด
WEATHER_SCENES: dict[str, weather.Weather] = {
    "rain": weather.Weather(mascot_state="writing"),
    "clear": weather.Weather(place="Chiang Mai", temp=36, high=38, low=27, code=0,
                             age=45, mascot_state="waiting"),
    "cold": weather.Weather(place="Sapporo", temp=28, high=31, low=19, code=73, unit="F",
                            age=40 * 60, mascot_state="sleeping"),
    "storm": weather.Weather(place="กรุงเทพ", temp=29,
                             high=33, low=26, code=95, age=12 * 60, mascot_state="alert"),
    # เก่าเกิน 10 เท่าของรอบดึง — ตัวเลขยังอ่านได้ แต่ต้องไม่มีใครเข้าใจว่ามันสด
    "stale": weather.Weather(place="Bangkok", temp=31, high=34, low=26, code=3,
                             age=4 * 3600, mascot_state="thinking",
                             # BLE ตายแต่ snapshot ยังมาทาง LAN — ไอคอนเป็นคลื่น ป้ายยังเป็นชื่อหน้า
                             bar=topbar.Bar(clock="21:15", ble=False, wifi=True,
                                            has_usage=True, pct=61)),
    # ยังไม่เคยได้เฟรมของหน้านี้เลย — ห้ามเป็นจอเปล่าหรือโครงว่าง (ADR-0002)
    "empty": weather.Weather(has_frame=False, mascot_state="idle"),
    # Mac หายไป: ตัวเลขค้างอยู่แต่ไม่มีใครรับรองแล้ว และมาสคอตจิ๋วหายไปทั้งตัว
    # (หายไป = ไม่มี Mac · หลับ = ไม่มี session)
    "offline": weather.Weather(place="Bangkok", age=95 * 60, connected=False),
}


# หน้าคริปโต — ใบแรกที่มี watchlist หน้าหุ้นจะยืมโครงนี้ไปใช้ต่อ
# ฉากถูกเลือกให้ครบสิ่งที่ต้องตัดสินด้วยตา: ราคาที่ยาวไม่เท่ากันเรียงหลักตรงกัน · ขึ้น ลง
# และนิ่งในจอเดียว · watchlist ที่ไม่เต็มห้าตัว · หน้าที่ยังไม่เคยได้ข้อมูล · ลิงก์หลุด
CRYPTO_SCENES: dict[str, crypto.Crypto] = {
    "full": crypto.Crypto(coins=[
        crypto.Coin("BTC", "64230", -21),
        crypto.Coin("ETH", "3125", 11),
        crypto.Coin("SOL", "172.05", 30),
        crypto.Coin("DOGE", "0.1423", -5),
        crypto.Coin("PEPE", "0.000008", 140),
    ], mascot_state="writing"),
    # สามตัวต้องดูเหมือน watchlist สามตัว ไม่ใช่ห้าตัวที่หายไปสอง
    # แถวเต็มความกว้างที่สุดของหน้านี้อยู่ใต้มาสคอตพอดี — ฉากนี้พิสูจน์ว่ามันไม่ทับกัน
    "short": crypto.Crypto(coins=[
        crypto.Coin("BTC", "64230", 0),
        crypto.Coin("ETH", "3125", -152),
        crypto.Coin("XRP", "2.41", 3),
    ], age=8, mascot_state="waiting",
        bar=topbar.Bar(clock="17:04", overflow=3, has_usage=True, pct=92)),
    # เก่าเกิน 10 เท่าของรอบดึง — ราคายังอ่านได้ แต่ต้องไม่มีใครเข้าใจว่ามันสด
    "stale": crypto.Crypto(coins=[
        crypto.Coin("BTC", "64230", -21),
        crypto.Coin("ETH", "3125", 11),
    ], age=3 * 3600),
    # ยังไม่เคยได้เฟรมของหน้านี้เลย — ห้ามเป็นจอเปล่าหรือโครงว่าง (ADR-0002)
    "empty": crypto.Crypto(has_frame=False),
    # Mac หายไป: ตัวเลขค้างอยู่แต่ไม่มีใครรับรองแล้ว ลูกศรยังบอกทิศได้โดยไม่ต้องมีสี
    "offline": crypto.Crypto(coins=[
        crypto.Coin("BTC", "64230", -21),
        crypto.Coin("ETH", "3125", 11),
    ], age=45 * 60, connected=False),
}


# หน้าหุ้น — โครงเดียวกับหน้าคริปโต บวกสิ่งที่หุ้นมีแต่คริปโตไม่มี: ตลาดที่ปิดได้
# ฉากถูกเลือกให้ครบสิ่งที่ต้องตัดสินด้วยตา: ขึ้น ลง นิ่งในจอเดียว · ตลาดปิดที่ต้องไม่อ่าน
# ว่าท่อพัง · เฟรมที่ถูกบีบจนไม่มีคอลัมน์เปอร์เซ็นต์ · หน้าที่ยังไม่เคยได้ข้อมูล · ลิงก์หลุด
STOCK_SCENES: dict[str, stocks.Stocks] = {
    "full": stocks.Stocks(rows=[
        stocks.Stock("AAPL", "189.44", -21),
        stocks.Stock("MSFT", "412.90", 11),
        stocks.Stock("NVDA", "1204.55", 30),
        stocks.Stock("TSLA", "177.02", -152),
        stocks.Stock("BRK.B", "412.10", 0),
    ], age=25, mascot_state="thinking"),
    # สองตัวต้องดูเหมือน watchlist สองตัว ไม่ใช่ห้าตัวที่หายไปสาม
    "short": stocks.Stocks(rows=[
        stocks.Stock("AAPL", "189.44", 3),
        stocks.Stock("SPY", "534.21", -8),
    ], age=8),
    # ตลาดปิด: ราคาเก่าเป็นชั่วโมงคือเรื่องปกติ บรรทัดล่างต้องอธิบาย ไม่ใช่ตะโกนว่า stale
    "closed": stocks.Stocks(rows=[
        stocks.Stock("AAPL", "189.44", -21),
        stocks.Stock("MSFT", "412.90", 11),
        stocks.Stock("NVDA", "1204.55", 30),
    ], age=11 * 3600, market_closed=True, mascot_state="sleeping"),
    # เฟรมที่ถูกบีบจนต้องทิ้งคอลัมน์เปอร์เซ็นต์ — ราคายังครบ ทิศทางหายไปทั้งหน้า
    "no_pct": stocks.Stocks(rows=[
        stocks.Stock("AAPL", "189.44", None),
        stocks.Stock("MSFT", "412.90", None),
        stocks.Stock("NVDA", "1204.55", None),
    ], age=40, bar=topbar.Bar(clock="06:20", has_usage=True, pct=None)),
    # ยังไม่เคยได้เฟรมของหน้านี้เลย — ห้ามเป็นจอเปล่าหรือโครงว่าง (ADR-0002)
    "empty": stocks.Stocks(has_frame=False),
    # Mac หายไป: ตัวเลขค้างอยู่แต่ไม่มีใครรับรองแล้ว ลูกศรยังบอกทิศได้โดยไม่ต้องมีสี
    "offline": stocks.Stocks(rows=[
        stocks.Stock("AAPL", "189.44", -21),
        stocks.Stock("MSFT", "412.90", 11),
    ], age=45 * 60, connected=False),
}


# หน้าปฏิทิน — ใบเดียวที่อ่านข้อมูลจากเครื่องเอง ไม่ใช่จากเน็ต (ADR-0005)
# ฉากถูกเลือกให้ครบสิ่งที่ต้องตัดสินด้วยตา: ชื่อนัดภาษาไทยที่มีวรรณยุกต์เหนือสระบน ·
# ชื่อที่ยาวจนถูกตัด · นัดทั้งวันที่ไม่มีเวลา · ทุกสภาพที่ไม่มีนัดให้แสดง · ลิงก์หลุด
CALENDAR_SCENES: dict[str, calendar.Calendar] = {
    "full": calendar.Calendar(events=[
        calendar.Appointment("Today", "09:30", "ประชุมทีมที่ปั๊มน้ำมัน"),
        calendar.Appointment("Today", "14:00", "1:1 with Ann"),
        calendar.Appointment("Tomorrow", "all day", "กตัญญู ฝั่งโน้น ฐู ฟ้า ปี"),
        calendar.Appointment("Fri", "08:15", "Flight BKK -> CNX"),
    ], age=95, mascot_state="alert"),
    # นัดเดียวต้องดูเหมือนนัดเดียว ไม่ใช่สี่นัดที่หายไปสาม
    "one": calendar.Calendar(events=[
        calendar.Appointment("Tomorrow", "10:00", "หมอฟัน"),
    ], age=12),
    # ชื่อที่ถูกตัดมาแล้วฝั่ง Mac — จุดไข่ปลาอยู่ท้ายคลัสเตอร์ ไม่ใช่กลางวรรณยุกต์
    "long": calendar.Calendar(events=[
        calendar.Appointment("Today", "16:45", "ที่ปั๊มน้ำมันกับผู้รับเหมาเรื..."),
    ], age=200),
    # สัปดาห์ที่ว่างจริงๆ — หน้านี้กลายเป็นปฏิทินตั้งโต๊ะ ไม่ใช่ประโยคบอกว่าไม่มีอะไร
    "empty": calendar.Calendar(state=calendar.EMPTY, age=60),
    # ว่างเหมือนกันแต่ยังไม่เคยได้ snapshot เลย จึงยังไม่รู้ว่าวันนี้วันอะไร — ถอยกลับไป
    # สองบรรทัดเดิม ห้ามโชว์ช่องว่างตัวใหญ่กลางจอ
    "empty_nodate": calendar.Calendar(state=calendar.EMPTY, age=60, date=""),
    # วันที่ก็ค้างเป็นเทาเหมือนนาฬิกาเมื่อ Mac หายไป ไม่ใช่หายไปทั้งบรรทัด
    "empty_offline": calendar.Calendar(state=calendar.EMPTY, age=40 * 60, connected=False),
    # ถูกปฏิเสธสิทธิ์ TCC ไปแล้ว — ทางแก้อยู่ที่ System Settings เท่านั้น
    # สิทธิ์ปฏิทินไม่เกี่ยวกับสถานะ session — มาสคอตยังต้องอยู่บนหน้าที่บอกว่าอ่านไม่ได้
    "denied": calendar.Calendar(state=calendar.NEEDS_ACCESS, age=20, mascot_state="writing"),
    # ยังไม่เคยถูกถามเลย — ก้าวถัดไปคือปุ่มในแอป ไม่ใช่ System Settings ที่ยังไม่มีแถวให้กด
    "unasked": calendar.Calendar(state=calendar.NOT_ASKED, age=20),
    # ได้สิทธิ์แล้วแต่ยังไม่ได้ติ๊กปฏิทินสักใบ (จอนี้วางให้คนอื่นเห็นได้)
    "unpicked": calendar.Calendar(state=calendar.NO_CALENDARS, age=20),
    # Mac หายไป: นัดที่ค้างอยู่เป็นเทา เหมือนราคาบนหน้าคริปโต
    "offline": calendar.Calendar(events=[
        calendar.Appointment("Today", "09:30", "ประชุมทีมที่ปั๊มน้ำมัน"),
        calendar.Appointment("Wed", "13:00", "Design review"),
    ], age=50 * 60, connected=False),
}


# แถบบนของหน้าย่อย — มาจาก snapshot ของหน้ามาสคอต ไม่ใช่จากเฟรมของหน้านั้น
# ฉากส่วนใหญ่ใช้ใบเดียวกัน เพราะแถบไม่ใช่สิ่งที่ฉากเหล่านั้นทดสอบ ส่วนฉากที่ตั้ง `bar` เอง
# คือฉากที่ตรวจตัวแถบตรงๆ: ลิงก์ที่วิ่งบน LAN · โควตาที่ไม่รู้ค่า · session ที่ล้นสามช่อง
PAGE_BAR = topbar.Bar(clock="09:41", has_usage=True, pct=35)


def _fill_bars() -> None:
    blank = topbar.Bar()
    for scenes in (WEATHER_SCENES, CRYPTO_SCENES, STOCK_SCENES, CALENDAR_SCENES):
        for sc in scenes.values():
            if sc.bar == blank:
                sc.bar = PAGE_BAR


_fill_bars()


# ฉากตรวจท้องฟ้า — ไม่มี session เลย ซึ่งเป็นสภาพที่จอเป็นเกือบตลอดเวลา
# และเป็นตอนที่ฟ้าโล่งที่สุด ส่วนตอนถูกมาสคอตบังดูได้จาก screen_busy/waiting
SKY_CLOCKS = {"dawn": "05:40", "day": "12:00", "dusk": "18:10", "night": "02:14"}


def sky_scene(clock: str) -> screen.Screen:
    return screen.Screen(
        sessions=[],
        clock=clock,
        date="Mon 27 Jul",
        usage=[
            screen.Usage("Current", SESSION_WINDOW, 35, 3 * 3600 + 5 * 60),
            screen.Usage("Weekly", WEEKLY_WINDOW, 48, 31 * 3600),
        ],
    )


# ป้ายที่ daemon ต้องตัดข้อความเองก่อนส่ง — (ชื่อใน Text.Limit, กว้างกี่พิกเซล, ฟอนต์บนบอร์ด)
#
# ความกว้างมาจากค่าที่ ct_ui.c ตั้งให้ป้ายจริง ไม่ใช่ค่าที่ preview อยากให้เป็น: ป้ายบนบอร์ด
# ตัดด้วย LV_LABEL_LONG_DOT อยู่แล้ว เลขที่สูงเกินจึงไม่ทำให้ข้อความล้นทับอะไร แต่มันแปลว่า
# daemon จ่ายไบต์ (ไทยตัวละ 3) ให้ตัวอักษรที่ไม่มีวันขึ้นจอ และการตัดไปอยู่ที่บอร์ดแทนที่จะ
# อยู่ที่เดียวกับ "..." ที่ daemon เติม
LABELS = (
    ("project", screen.PROJECT_W, 12),
    ("cardTitle", screen.CARD_TEXT_W, 14),
    ("cardBody", screen.CARD_TEXT_W, 12),
    ("Weather.placeLimit", L.weather.icon_x - L.weather.place_x - 8, 14),
    ("Calendar.titleLimit", L.calendar.title_w, 14),
)


def print_limits() -> None:
    """วัดว่าแต่ละป้ายรับได้กี่ช่อง — ที่มาของตัวเลขใน host/Sources/TamaCore/Text.swift

    ฝั่งไทยวัดได้ *เป๊ะ* เพราะฟอนต์บิตแมปที่แฟลชลงบอร์ดคือไฟล์เดียวกับที่อ่านตรงนี้ และทุก
    ช่องกว้างเท่ากันหมด (สระบนกับวรรณยุกต์กว้างศูนย์ จึงไม่กินที่ของใคร)
    ฝั่ง ASCII เป็นค่าประมาณ เพราะบอร์ดวาดด้วย Montserrat ซึ่ง preview ไม่มีตัวจริง —
    นั่นคือเหตุผลที่สองภาษาถือเลขคนละตัว ไม่ใช่เลขเดียวที่ประนีประนอมทั้งคู่
    """
    d = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    print(f"{'label':<20} {'width':>6} {'font':>5} {'thai':>5} {'ascii~':>7}")
    for name, width, board in LABELS:
        bf = screen.bitmapfont.font(board)
        # ช่องไทยกว้างคงที่ วัดจากพยัญชนะตัวไหนก็ได้
        thai_cell = bf.length("ก")
        pil = {12: 9, 14: 12}[board]
        f = screen.font(pil)
        letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
        ascii_cell = sum(d.textlength(c, font=f) for c in letters) / len(letters)
        print(f"{name:<20} {width:>6} {board:>5} {int(width // thai_cell):>5} "
              f"{int(width // ascii_cell):>7}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", action="store_true", help="เฉพาะ contact sheet")
    ap.add_argument("--limits", action="store_true", help="วัดความยาวสูงสุดของแต่ละป้าย")
    ap.add_argument("--scale", type=int, default=3, help="ขยายภาพจอตอน export")
    args = ap.parse_args()

    if args.limits:
        print_limits()
        return

    OUT.mkdir(exist_ok=True)
    (OUT / "anim").mkdir(exist_ok=True)

    sheet = contact_sheet()
    sheet.save(OUT / "states.png")
    print(f"states.png            {sheet.width}x{sheet.height}  {len(mascot.all_states())} states")
    if args.sheet:
        return

    for st in mascot.all_states():
        frames = state_gif(st)
        frames[0].save(OUT / "anim" / f"{st}.gif", save_all=True,
                       append_images=frames[1:], duration=90, loop=0)
    print(f"anim/*.gif            {len(mascot.all_states())} ไฟล์")

    for name, sc in SCENES.items():
        img = screen.render(sc, 0.25)
        img.save(OUT / f"screen_{name}.png")
        big = img.resize((img.width * args.scale, img.height * args.scale), Image.NEAREST)
        big.save(OUT / f"screen_{name}@{args.scale}x.png")
        # ฉากที่ไม่มี session ใช้ลูปยาวกว่า — เที่ยวเดินหนึ่งรอบกินเวลาหลายสิบวินาที
        # ถ้าตัดที่ 4 ลูปเหมือนฉากอื่นจะเห็นแค่มาสคอตขยับทีละไม่กี่พิกเซล
        loops = STROLL_LOOPS if not sc.sessions else LOOPS
        frames = [
            screen.render(sc, (f % FRAMES) / FRAMES, f // FRAMES)
            for f in range(FRAMES * loops)
        ]
        frames[0].save(OUT / f"screen_{name}.gif", save_all=True,
                       append_images=frames[1:], duration=90, loop=0)
    print(f"screen_*.png/gif      {len(SCENES)} ฉาก  (320x240)")

    for name, w in WEATHER_SCENES.items():
        img = weather.render(w, 0.25)
        img.save(OUT / f"weather_{name}.png")
        big = img.resize((img.width * args.scale, img.height * args.scale), Image.NEAREST)
        big.save(OUT / f"weather_{name}@{args.scale}x.png")
        frames = [
            weather.render(w, (f % FRAMES) / FRAMES, f // FRAMES)
            for f in range(FRAMES * LOOPS)
        ]
        frames[0].save(OUT / f"weather_{name}.gif", save_all=True,
                       append_images=frames[1:], duration=90, loop=0)
    print(f"weather_*.png/gif     {len(WEATHER_SCENES)} ฉาก  (320x240)")

    # GIF ของหน้าที่เรียงเป็นแถวมีไว้ดูมาสคอตจิ๋วอย่างเดียว — แถวเองไม่ขยับ แต่ท่าที่
    # กระโดดออกนอกกรอบจะไปทับแถวแรก ซึ่งเป็นสิ่งเดียวบนหน้านี้ที่ภาพนิ่งพิสูจน์ไม่ได้
    for name, c in CRYPTO_SCENES.items():
        img = crypto.render(c, 0.25)
        img.save(OUT / f"crypto_{name}.png")
        big = img.resize((img.width * args.scale, img.height * args.scale), Image.NEAREST)
        big.save(OUT / f"crypto_{name}@{args.scale}x.png")
        frames = [
            crypto.render(c, (f % FRAMES) / FRAMES, f // FRAMES)
            for f in range(FRAMES * LOOPS)
        ]
        frames[0].save(OUT / f"crypto_{name}.gif", save_all=True,
                       append_images=frames[1:], duration=90, loop=0)
    print(f"crypto_*.png/gif      {len(CRYPTO_SCENES)} ฉาก  (320x240)")

    for name, s_ in STOCK_SCENES.items():
        img = stocks.render(s_, 0.25)
        img.save(OUT / f"stocks_{name}.png")
        big = img.resize((img.width * args.scale, img.height * args.scale), Image.NEAREST)
        big.save(OUT / f"stocks_{name}@{args.scale}x.png")
        frames = [
            stocks.render(s_, (f % FRAMES) / FRAMES, f // FRAMES)
            for f in range(FRAMES * LOOPS)
        ]
        frames[0].save(OUT / f"stocks_{name}.gif", save_all=True,
                       append_images=frames[1:], duration=90, loop=0)
    print(f"stocks_*.png/gif      {len(STOCK_SCENES)} ฉาก  (320x240)")

    for name, c in CALENDAR_SCENES.items():
        img = calendar.render(c, 0.25)
        img.save(OUT / f"calendar_{name}.png")
        big = img.resize((img.width * args.scale, img.height * args.scale), Image.NEAREST)
        big.save(OUT / f"calendar_{name}@{args.scale}x.png")
        frames = [
            calendar.render(c, (f % FRAMES) / FRAMES, f // FRAMES)
            for f in range(FRAMES * LOOPS)
        ]
        frames[0].save(OUT / f"calendar_{name}.gif", save_all=True,
                       append_images=frames[1:], duration=90, loop=0)
    print(f"calendar_*.png/gif    {len(CALENDAR_SCENES)} ฉาก  (320x240)")

    for name, clock in SKY_CLOCKS.items():
        sc = sky_scene(clock)
        # cycle 6 = จังหวะที่มาสคอตเดินมาถึงกลางจอพอดี — ที่ cycle 0 มันยังอยู่นอกจอ
        # แล้วภาพตรวจจะไม่มีสิ่งที่ต้องตรวจ (มาสคอตยืนบนพื้น + contrast กับฟ้า)
        img = screen.render(sc, 0.25, 6)
        img.save(OUT / f"sky_{name}.png")
        big = img.resize((img.width * args.scale, img.height * args.scale), Image.NEAREST)
        big.save(OUT / f"sky_{name}@{args.scale}x.png")
        frames = [
            screen.render(sc, (f % FRAMES) / FRAMES, f // FRAMES)
            for f in range(FRAMES * STROLL_LOOPS)
        ]
        frames[0].save(OUT / f"sky_{name}.gif", save_all=True,
                       append_images=frames[1:], duration=90, loop=0)
    print(f"sky_*.png/gif         {len(SKY_CLOCKS)} ช่วงเวลา")
    print(f"\nout/ -> {OUT}")


if __name__ == "__main__":
    main()
