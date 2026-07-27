"""มาสคอต Claude — สร้างเป็น rect list ล้วน ไม่มีบิตแมป

สองมิติที่แยกจากกัน (ตามที่ตกลงใน DESIGN.md):
  mood — ตา + ลำตัว + ขา   บอกว่า "รู้สึกยังไง"
  prop — ของที่ถือ/ลอยเหนือหัว  บอกว่า "ทำอะไรอยู่"

คูณกันได้อิสระ จึงได้ combination เยอะโดยวาดเพิ่มน้อย
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from functools import lru_cache

from .config import L, PAL
from .props import BOX_X0, BOX_X1, PROPS
from .rects import Rect, RectList, bounds, move, outline_pass

GW = L.mascot.grid_w  # 16 — ความกว้างซิลลูเอ็ตรวมปุ่มข้าง
GH = L.mascot.grid_h  # 11.2

# --- โครงร่าง (พิกัด unit) -------------------------------------------------
# สัดส่วนวัดจากภาพอ้างอิง ลำตัวกว้าง 14 เป็นฐานของทุกค่า
BODY = (1.0, 0.0, 14.0, 8.0)  # x, y, w, h
NUB_Y, NUB_H, NUB_W = 2.8, 1.9, 1.0
LEG_TOP, LEG_H = 8.0, 3.2
# ขาและช่องว่างวัดจากภาพอ้างอิง: ขานอกกว้างกว่าขาใน ช่องกลางกว้างกว่าช่องข้าง
LEG_SPANS = ((1.00, 2.46), (4.50, 2.20), (9.29, 2.20), (12.53, 2.46))  # x, w
EYE_L, EYE_R, EYE_Y, EYE_S = 3.36, 10.64, 2.10, 2.0

FOOT_Y = LEG_TOP + LEG_H  # 11.2 — ระดับที่มาสคอตยืน


# --- ตา --------------------------------------------------------------------
def _eye(x: float, kind: str, look: float, ink: str) -> RectList:
    """ตาหนึ่งข้าง กล่องฐาน EYE_S x EYE_S ที่ (x, EYE_Y) — ทุกค่าอิงสัดส่วน ไม่ฝังตัวเลขดิบ"""
    s, y = EYE_S, EYE_Y
    if kind == "sleep":
        return [Rect(x, y + s * 0.62, s, s * 0.3, ink)]
    if kind == "squint":
        return [Rect(x, y + s * 0.34, s, s * 0.42, ink)]
    if kind == "focus":
        m = s * 0.22
        return [Rect(x + m + look, y + m, s - 2 * m, s - 2 * m, ink)]
    if kind == "wide":
        m = s * 0.24
        return [Rect(x - m + look, y - m, s + 2 * m, s + 2 * m, ink)]
    if kind == "blink":
        return [Rect(x, y + s * 0.42, s, s * 0.28, ink)]
    if kind == "happy":  # ^ ^ — ต้องไม่ใช่ขีดแบน ไม่งั้นซ้ำกับตาหลับ
        u = s / 3.0
        return [Rect(x + i * u, y + j * u, u, u, ink) for i, j in ((0, 1), (1, 0), (2, 1))]
    if kind == "dead":  # x_x — บันไดขั้นละ 1 บล็อกทำเป็นกากบาท
        u = s / 3.0
        return [
            Rect(x + i * u, y + j * u, u, u, ink)
            for i, j in ((0, 0), (1, 1), (2, 2), (2, 0), (0, 2))
        ]
    return [Rect(x + look, y, s, s, ink)]  # open


# --- ขา --------------------------------------------------------------------
def _legs(gait: str, phase: float, color: str, extra_lift: float = 0.0) -> RectList:
    out: RectList = []
    for i, (lx, lw) in enumerate(LEG_SPANS):
        lift = extra_lift
        if gait == "walk":
            # ขาคู่ทแยง (0,2) กับ (1,3) สลับกันยก
            up = (phase < 0.5) == (i % 2 == 0)
            lift += LEG_H * 0.34 if up else 0.0
        elif gait == "sit":
            lift += LEG_H * 0.66
        out.append(Rect(lx, LEG_TOP, lw, max(LEG_H - lift, 0.6), color))
    return out


# --- ลำตัว -----------------------------------------------------------------
def _body(squash: float, color: str) -> RectList:
    """squash > 0 = เตี้ยลงกว้างขึ้น (ยึดฝ่าเท้าเป็นหลัก)"""
    bx, by, bw, bh = BODY
    nh = bh * (1.0 - squash)
    nw = bw * (1.0 + squash * 0.45)
    nx = bx - (nw - bw) / 2.0
    ny = by + (bh - nh)
    ncx = nx + nw
    return [
        Rect(nx, ny, nw, nh, color),
        Rect(nx - NUB_W, ny + (NUB_Y - by) * (nh / bh), NUB_W, NUB_H, color),
        Rect(ncx, ny + (NUB_Y - by) * (nh / bh), NUB_W, NUB_H, color),
    ]


# --- อารมณ์ ----------------------------------------------------------------
@dataclass(frozen=True, slots=True)
class Mood:
    eye: str = "open"
    gait: str = "stand"
    squash: float = 0.0
    bob: float = 0.0  # ระยะแกว่งขึ้นลง (unit)
    bob_hz: float = 1.0
    shake: float = 0.0
    look: float = 0.0
    blink: bool = True  # ตาลืมเท่านั้นที่กะพริบได้
    sink: float = 0.0  # >0 = จมลงดินตามความคืบหน้าของ phase (ท่ามุดหาย)


# ช่วง phase ที่ตากะพริบ — สั้นมากโดยตั้งใจ กะพริบนานกว่านี้จะดูเหมือนง่วง
BLINK_FROM, BLINK_TO = 0.88, 0.94
# กะพริบทุกกี่รอบลูป — ลูปเดียวยาวราว 1 วินาที กะพริบทุกวินาทีจะดูกระวนกระวาย
BLINK_EVERY = 4


MOODS: dict[str, Mood] = {
    "idle":      Mood(eye="open",   bob=0.20, bob_hz=1.0),
    "working":   Mood(eye="focus",  bob=0.15, bob_hz=2.4, squash=0.03),
    "walking":   Mood(eye="open",   gait="walk", bob=0.22, bob_hz=2.0),
    "waiting":   Mood(eye="open",   bob=0.28, bob_hz=0.7, look=0.40),
    "sleeping":  Mood(eye="sleep",  gait="sit", squash=0.10, bob=0.10, bob_hz=0.35,
                      blink=False),
    "alert":     Mood(eye="wide",   bob=0.48, bob_hz=3.2, shake=0.20, blink=False),
    "celebrate": Mood(eye="happy",  bob=0.88, bob_hz=2.6, squash=-0.05, blink=False),
    "error":     Mood(eye="dead",   gait="sit", squash=0.12, shake=0.08, blink=False),
    # ท่าเปลี่ยนผ่าน — phase ทำหน้าที่เป็นความคืบหน้า 0→1 ไม่ใช่ลูปวน
    "entering":  Mood(eye="open",   gait="walk", bob=0.30, bob_hz=4.0),
    "leaving":   Mood(eye="squint", gait="sit", squash=0.30, sink=1.0, blink=False),
}


# --- visual state = mood + prop ---------------------------------------------
# enum นี้ต้องตรงกับ firmware ทุกตัว (daemon ส่งชื่อพวกนี้มาบน BLE)
STATES: dict[str, tuple[str, str | None]] = {
    "idle":      ("idle", None),
    "reading":   ("working", "magnifier"),
    "writing":   ("working", "pencil"),
    "building":  ("working", "hammer"),
    "searching": ("working", "globe"),
    "thinking":  ("idle", "dots"),
    "waiting":   ("waiting", "query"),
    "sleeping":  ("sleeping", "zzz"),
    "alert":     ("alert", "bang"),
    "celebrate": ("celebrate", "sparkle"),
    "error":     ("error", None),
    "entering":  ("entering", None),
    "leaving":   ("leaving", None),
    # ต่อท้ายเสมอ — ลำดับใน dict นี้คือค่าตัวเลขของ enum ใน layout.h
    "conducting": ("working", "crew"),
}


def _skin(connected: bool, state: str) -> tuple[str, str, str]:
    """คืน (สีตัว, สีตา, สีขอบ)"""
    if not connected:
        return PAL.gray, PAL.gray_dark, PAL.text_dim
    if state == "sleeping":
        # หรี่ลงเล็กน้อยเท่านั้น — ถ้าเปลี่ยนสีแรงจะไปชนกับสัญญาณ "หลุดการเชื่อมต่อ"
        return PAL.clay_dark, PAL.ink, PAL.outline
    return PAL.clay, PAL.ink, PAL.outline


def build(
    state: str, phase: float = 0.0, connected: bool = True, cycle: int = 0
) -> RectList:
    """สร้าง rect list ของมาสคอตหนึ่งตัว เรียงจากหลังไปหน้า

    phase  ความคืบหน้าในลูปอนิเมชัน 0..1 (ลูปหนึ่งราว 1 วินาที)
    cycle  ลูปที่เท่าไรแล้ว — ใช้กับจังหวะที่ช้ากว่าหนึ่งลูป เช่นการกะพริบตา

    พิกัดอยู่ในตาราง 16 x 11.2 unit ฝ่าเท้าอยู่ที่ y = 11.2
    """
    if state not in STATES:
        raise KeyError(f"unknown visual state: {state!r}")
    mood_name, prop_name = STATES[state]
    m = MOODS[mood_name]
    skin, ink, edge = _skin(connected, state)

    dy = -abs(math.sin(phase * math.pi * m.bob_hz)) * m.bob
    dx = math.sin(phase * math.pi * 12.0) * m.shake

    # ท่ามุดหาย: ยิ่ง phase เดินหน้า ยิ่งแบนลงติดพื้นและขาหด
    squash = m.squash + m.sink * phase * 0.60
    silhouette = _body(squash, skin) + _legs(
        m.gait, phase, skin, m.sink * phase * LEG_H * 0.9
    )
    silhouette = move(silhouette, dx, dy)

    eye_kind = m.eye
    if m.blink and cycle % BLINK_EVERY == BLINK_EVERY - 1 and BLINK_FROM <= phase < BLINK_TO:
        eye_kind = "blink"

    # ตาเลื่อนตามลำตัวที่ถูก squash
    eye_dy = dy + BODY[3] * squash
    look = m.look * math.sin(phase * math.pi * 2.0)
    eyes = _eye(EYE_L, eye_kind, look, ink) + _eye(EYE_R, eye_kind, look, ink)
    eyes = move(eyes, dx, eye_dy)

    out: RectList = []
    if L.mascot.outline:
        out += outline_pass(silhouette, L.mascot.outline, edge)
    out += silhouette
    out += eyes
    if prop_name:
        out += move(PROPS[prop_name](phase, connected), dx, dy)
    return out


@lru_cache(maxsize=None)
def state_box(state: str) -> tuple[float, float, float, float]:
    """กรอบจริงของสถานะหนึ่ง รวมทุกเฟรมของอนิเมชัน

    ท่าที่ไม่มี prop ถือ จะแคบกว่าท่าที่มี — ถ้าจัดกึ่งกลางด้วยกรอบรวม
    ตัวละครจะเอียงไปทางซ้ายในท่าที่ไม่มี prop
    """
    acc: RectList = []
    for i in range(12):
        acc += build(state, i / 12.0)
    return bounds(acc)


def build_centered(
    state: str, phase: float = 0.0, connected: bool = True, cycle: int = 0
) -> RectList:
    """เหมือน build() แต่เลื่อนแนวนอนให้กรอบของสถานะนั้นอยู่กึ่งกลางกรอบวาดมาตรฐาน

    ระดับฝ่าเท้าไม่ขยับ — จัดกึ่งกลางเฉพาะแกน x
    """
    bx0, _, bx1, _ = state_box(state)
    dx = (BOX_X0 + BOX_X1) / 2.0 - (bx0 + bx1) / 2.0
    return move(build(state, phase, connected, cycle), dx, 0.0)


def all_states() -> list[str]:
    return list(STATES)
