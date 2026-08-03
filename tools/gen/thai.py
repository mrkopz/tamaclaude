"""เดินคลัสเตอร์ไทยแล้วเลือกร่างของ glyph — คู่แฝดของ TamaCore/ThaiShaper.swift

ทั้งสองฝั่งต้องให้ผลเหมือนกันทุกตัวอักษร กันดริฟต์ด้วย golden vectors ชุดเดียวกัน
ที่ tools/thai-golden.json (ฝั่ง Python อ่านใน tools/test_thai.py ฝั่ง Swift อ่านใน tamatest)

ตารางทั้งหมดมาจาก thai.toml ผ่าน thai_table.py — ไฟล์นี้มีแต่อัลกอริทึม ไม่มีข้อมูล
"""

from __future__ import annotations

from .thai_table import (
    BLOCK_RANGES,
    CANONICAL,
    DESCENDER_BASES,
    MARK_CLASSES,
    TALL_BASES,
    VARIANTS,
)


def in_block(cp: int) -> bool:
    """อยู่ในช่วงอักขระไทยที่ฟอนต์บนบอร์ดมีจริงหรือไม่"""
    return any(lo <= cp <= hi for lo, hi in BLOCK_RANGES)


def mark_class(cp: int) -> str | None:
    return MARK_CLASSES.get(cp)


def _variant(cp: int, name: str) -> int:
    """ร่างที่เลือกไว้ ถ้าตารางไม่มีก็ใช้ร่างปกติ — ตัวอักษรหายไปแย่กว่าวางเพี้ยน"""
    return VARIANTS.get(name, {}).get(CANONICAL.get(cp, cp), cp)


def clusters(text: str) -> list[str]:
    """แตกข้อความเป็นคลัสเตอร์ที่ประกอบร่างแล้ว หนึ่งคลัสเตอร์ = หนึ่งช่องบนจอ

    ตัวอักษรที่ไม่ใช่ไทยกลายเป็นคลัสเตอร์ละตัว ความยาวที่ตาเห็นจึงเท่ากับจำนวนคลัสเตอร์
    เสมอ ไม่ว่าข้อความจะเป็นภาษาอะไร
    """
    out: list[str] = []
    cps = [ord(c) for c in text]
    i = 0
    n = len(cps)
    while i < n:
        base = cps[i]
        i += 1
        if mark_class(base) is not None:
            continue  # mark ที่ไม่มีฐาน — ทิ้ง ไม่มีที่ให้มันเกาะ
        above = tone = below = None
        while i < n:
            k = mark_class(cps[i])
            if k is None:
                break
            # ย้อนกลับเป็นร่างปกติก่อนเสมอ ข้อความที่ประกอบร่างแล้วจึงประกอบซ้ำได้ผลเดิม
            m = CANONICAL.get(cps[i], cps[i])
            if k == "above" and above is None:
                above = m
            elif k == "tone" and tone is None:
                tone = m
            elif k == "below" and below is None:
                below = m
            i += 1  # ตัวซ้ำในชั้นเดียวกันถูกทิ้ง ไม่วาดซ้อนกันเอง
        tall = base in TALL_BASES
        desc = base in DESCENDER_BASES
        piece = [base]
        if below is not None:
            piece.append(_variant(below, "below_descender") if desc else below)
        if above is not None:
            piece.append(_variant(above, "above_tall") if tall else above)
        if tone is not None:
            if above is not None:
                piece.append(_variant(tone, "tone_tall_high" if tall else "tone_high"))
            elif tall:
                piece.append(_variant(tone, "tone_tall"))
            else:
                piece.append(tone)
        out.append("".join(chr(c) for c in piece))
    return out


def shape(text: str) -> str:
    """ข้อความที่ประกอบร่างแล้ว — สิ่งที่ส่งขึ้นสายและสิ่งที่ preview วาด"""
    return "".join(clusters(text))


def display_width(text: str) -> int:
    """ความกว้างที่ตาเห็น หน่วยเป็นช่อง — สระบนและวรรณยุกต์กว้างศูนย์ จึงไม่ถูกนับ"""
    return len(clusters(text))
