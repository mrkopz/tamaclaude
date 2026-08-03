#!/usr/bin/env python3
"""thai.toml + Sarabun -> ฟอนต์ของ firmware และฟอนต์ของ preview จากการวาดครั้งเดียวกัน

    python3 tools/export_thai_font.py

ออกสองทาง:
    firmware/main/ct_font_thai_{12,14}.c   lv_font_t ที่ LVGL วาดได้ตรงๆ
    tools/fonts/thai-{12,14}.json          บิตแมปชุดเดียวกันสำหรับ preview.py

ต้องเป็นการวาดครั้งเดียวกัน ไม่ใช่สองเส้นทางที่บังเอิญเหมือนกัน — ADR-0008 บอกว่า preview
ที่ใช้ TTF ต้นฉบับจะจัดวางสวยกว่าบอร์ดจริงแล้วกลายเป็นคำโกหกตรงจุดที่ต้องใช้ตัดสินใจ

**ไม่มี lv_font_conv ในเส้นทางนี้** — ร่างของ mark ต่างกันแค่ตำแหน่ง ตัวแปลงมาตรฐาน
สั่งเลื่อน glyph ไม่ได้ ถ้าจะใช้มันต้องไปดัด TTF ก่อน ซึ่งแพงกว่าการเขียน emitter ตรงนี้
รูปแบบไฟล์ที่ปล่อยออกมาเป็นของ LVGL 9.2 (bitmap format 0, bpp 4, ไม่มี kerning)
"""

from __future__ import annotations

import base64
import json
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

TOOLS_DIR = Path(__file__).resolve().parent
REPO_DIR = TOOLS_DIR.parent
THAI_TOML = TOOLS_DIR / "thai.toml"
FONT_DIR = TOOLS_DIR / "fonts"
FIRMWARE_DIR = REPO_DIR / "firmware" / "main"

BPP = 4


@dataclass
class Glyph:
    cp: int
    adv16: int  # ระยะก้าวแบบ 8.4 (พิกเซล * 16) ตามที่ LVGL เก็บ
    ofs_x: int
    ofs_y: int  # วัดจากเส้นฐาน บวก = สูงขึ้น เหมือนที่ lv_font_conv ปล่อยออกมา
    box_w: int
    box_h: int
    bits: bytes


def load() -> dict:
    with THAI_TOML.open("rb") as fh:
        return tomllib.load(fh)


def ranges(raw: dict) -> list[tuple[int, int]]:
    """ช่วง codepoint ที่ฟอนต์ต้องมี เรียงตามที่จะกลายเป็น cmap

    ไม่มี ASCII อยู่ในนี้ — บนบอร์ดฟอนต์นี้เป็น fallback ของ Montserrat ตัว ASCII จึงไม่มี
    ทางถูกถามถึง การใส่ไว้คือ 26KB ที่ไม่มีใครวาด และ preview ก็วาด ASCII ด้วยฟอนต์
    ฝั่ง PIL ตามบอร์ดอยู่แล้ว (ดู _cells ใน gen/screen.py)
    """
    pua = raw["font"]["pua_start"]
    count = sum(len(raw["mark"][v["class"]]) for v in raw["variant"])
    return [*[tuple(r) for r in raw["block"]["ranges"]], (pua, pua + count - 1)]


def variant_plan(raw: dict, size: int) -> dict[int, tuple[int, int, int]]:
    """codepoint ใน PUA -> (ต้นฉบับ, dx, dy) — ต้องแจกเลขให้ตรงกับ export_thai.py"""
    cp = raw["font"]["pua_start"]
    out: dict[int, tuple[int, int, int]] = {}
    for v in raw["variant"]:
        dx, dy = v["shift"][str(size)]
        for ch in raw["mark"][v["class"]]:
            out[cp] = (ord(ch), dx, dy)
            cp += 1
    return out


def mark_set(raw: dict) -> set[int]:
    return {ord(c) for k in ("above", "tone", "below") for c in raw["mark"][k]}


def raster(font: ImageFont.FreeTypeFont, cp: int, ascent: int, pad: int) -> tuple:
    """วาดหนึ่งตัวอักษรแล้วคืน (ofs_x, ofs_y, w, h, ค่าเทา)

    วาดด้วย anchor "ls" (ซ้าย-เส้นฐาน) แล้วหา ink bbox เอง ไม่เชื่อ getbbox ของ PIL
    เพราะมันรวมกล่อง layout ของ mark ที่ยืดลงไปถึงเส้นฐานมาด้วย
    """
    side = pad * 2 + font.size * 3
    img = Image.new("L", (side, side), 0)
    ImageDraw.Draw(img).text((pad, pad + ascent), chr(cp), font=font, fill=255, anchor="ls")
    box = img.getbbox()
    if box is None:
        return 0, 0, 0, 0, b""
    x0, y0, x1, y1 = box
    crop = img.crop(box).tobytes()
    return x0 - pad, (pad + ascent) - y1, x1 - x0, y1 - y0, crop


def pack(gray: bytes) -> bytes:
    """ค่าเทา 8 บิต -> สตรีม 4 บิตต่อพิกเซล ต่อเนื่องกันไม่ปัดขอบแถว

    ตรงกับที่ lv_font_conv ทำ: '!' ที่ box 3x9 กิน 14 ไบต์ = 27 nibble ปัดขึ้น
    ถ้าปัดทีละแถวจะได้ 18 ไบต์ แล้ว LVGL จะอ่านเพี้ยนทั้งฟอนต์
    """
    out = bytearray()
    acc = 0
    n = 0
    for v in gray:
        acc = (acc << 4) | (v >> 4)
        n += 1
        if n == 2:
            out.append(acc)
            acc = 0
            n = 0
    if n:
        out.append(acc << 4)
    return bytes(out)


def build(raw: dict, size: int) -> tuple[list[Glyph], int, int]:
    src = TOOLS_DIR / raw["font"]["source"]
    font = ImageFont.truetype(str(src), size)
    ascent, descent = font.getmetrics()
    marks = mark_set(raw)
    plan = variant_plan(raw, size)
    advance = raw["font"]["advance"][str(size)]
    pad = size * 2

    glyphs: list[Glyph] = []
    for lo, hi in ranges(raw):
        for cp in range(lo, hi + 1):
            if cp in plan:
                srccp, dx, dy = plan[cp]
                ox, oy, w, h, gray = raster(font, srccp, ascent, pad)
                base_mark = True
            else:
                srccp, dx, dy = cp, 0, 0
                ox, oy, w, h, gray = raster(font, cp, ascent, pad)
                base_mark = cp in marks
            if base_mark:
                # mark ไม่กินความกว้าง และวางกลางช่องของฐานที่เพิ่งผ่านไป — ทำได้เพราะ
                # พยัญชนะไทยทุกตัวถูกบังคับให้ก้าวเท่ากัน (ดูหมายเหตุใน thai.toml)
                adv16 = 0
                ox = -(advance + w) // 2
            else:
                # ช่องว่างในช่วง (0E3B..0E3E ไม่มีอักขระใน Unicode) ไม่ควรกินความกว้าง
                adv16 = advance * 16 if w else 0
            glyphs.append(Glyph(cp, adv16, ox + dx, oy - dy, w, h, pack(gray)))
    return glyphs, ascent + descent, descent


def _c_name(size: int) -> str:
    return f"ct_font_thai_{size}"


def emit_c(raw: dict, size: int, glyphs: list[Glyph], line_h: int, base_l: int) -> str:
    # bitmap เดียวกันใช้ร่วมกันได้ ร่างของ mark ต่างกันแค่ตำแหน่ง ไม่ใช่รูป
    blob = bytearray()
    index: dict[bytes, int] = {}
    rows: list[str] = []
    dsc = ["    {.bitmap_index = 0, .adv_w = 0, .box_w = 0, .box_h = 0, "
           ".ofs_x = 0, .ofs_y = 0} /* id = 0 reserved */,"]
    for g in glyphs:
        if g.bits and g.bits not in index:
            index[g.bits] = len(blob)
            blob.extend(g.bits)
            rows.append(f"    /* U+{g.cp:04X} */ "
                        + ", ".join(f"0x{b:02x}" for b in g.bits) + ",")
        at = index.get(g.bits, 0)
        dsc.append(
            f"    {{.bitmap_index = {at}, .adv_w = {g.adv16}, .box_w = {g.box_w}, "
            f".box_h = {g.box_h}, .ofs_x = {g.ofs_x}, .ofs_y = {g.ofs_y}}}, /* U+{g.cp:04X} */")

    cmaps = []
    gid = 1
    for lo, hi in ranges(raw):
        cmaps.append(
            f"    {{.range_start = {lo}, .range_length = {hi - lo + 1}, "
            f".glyph_id_start = {gid},\n     .unicode_list = NULL, .glyph_id_ofs_list = NULL, "
            f".list_length = 0, .type = LV_FONT_FMT_TXT_CMAP_FORMAT0_TINY}},")
        gid += hi - lo + 1

    name = _c_name(size)
    return f"""/*
 * generated by tools/export_thai_font.py — do not edit
 *
 * ฟอนต์: {raw["font"]["source"]} (SIL Open Font License 1.1 ดู tools/fonts/OFL.txt)
 * ขนาด {size}px · 4bpp · ไม่มี kerning · ร่างของสระบนและวรรณยุกต์อยู่ที่ U+F700 ขึ้นไป
 * ตารางเลือกร่างและระยะเลื่อนอยู่ใน tools/thai.toml — ที่นี่เป็นผลลัพธ์เท่านั้น
 */

#include "lvgl.h"

static LV_ATTRIBUTE_LARGE_CONST const uint8_t {name}_bitmap[] = {{
{chr(10).join(rows)}
}};

static const lv_font_fmt_txt_glyph_dsc_t {name}_dsc[] = {{
{chr(10).join(dsc)}
}};

static const lv_font_fmt_txt_cmap_t {name}_cmaps[] = {{
{chr(10).join(cmaps)}
}};

static const lv_font_fmt_txt_dsc_t {name}_font_dsc = {{
    .glyph_bitmap = {name}_bitmap,
    .glyph_dsc = {name}_dsc,
    .cmaps = {name}_cmaps,
    .kern_dsc = NULL,
    .kern_scale = 0,
    .cmap_num = {len(cmaps)},
    .bpp = {BPP},
    .kern_classes = 0,
    .bitmap_format = 0,
}};

const lv_font_t {name} = {{
    .get_glyph_dsc = lv_font_get_glyph_dsc_fmt_txt,
    .get_glyph_bitmap = lv_font_get_bitmap_fmt_txt,
    .line_height = {line_h},
    .base_line = {base_l},
    .subpx = LV_FONT_SUBPX_NONE,
    .underline_position = -1,
    .underline_thickness = 1,
    .dsc = &{name}_font_dsc,
}};
"""


def emit_header(raw: dict) -> str:
    decls = "\n".join(f"extern const lv_font_t {_c_name(s)};" for s in raw["font"]["sizes"])
    return f"""/*
 * generated by tools/export_thai_font.py — do not edit
 *
 * ฟอนต์ไทยที่ประกอบร่างมาแล้วจาก Mac (ADR-0008) firmware แค่วาด codepoint ที่ได้รับ
 * ไม่มีตรรกะภาษาไทยฝั่งนี้แม้บรรทัดเดียว
 */

#pragma once

#include "lvgl.h"

#ifdef __cplusplus
extern "C" {{
#endif

{decls}

#ifdef __cplusplus
}}
#endif
"""


def emit_json(size: int, glyphs: list[Glyph], line_h: int, base_l: int) -> str:
    return json.dumps(
        {
            "note": "generated by tools/export_thai_font.py — do not edit",
            "size": size,
            "line_height": line_h,
            "base_line": base_l,
            "bpp": BPP,
            "glyphs": {
                f"{g.cp:04X}": {
                    "adv": g.adv16 / 16,
                    "ofs_x": g.ofs_x,
                    "ofs_y": g.ofs_y,
                    "w": g.box_w,
                    "h": g.box_h,
                    "bits": base64.b64encode(g.bits).decode("ascii"),
                }
                for g in glyphs
                if g.box_w or g.adv16
            },
        },
        indent=0,
    )


def main() -> None:
    raw = load()
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    for size in raw["font"]["sizes"]:
        glyphs, line_h, base_l = build(raw, size)
        c_path = FIRMWARE_DIR / f"{_c_name(size)}.c"
        c_path.write_text(emit_c(raw, size, glyphs, line_h, base_l), encoding="utf-8")
        j_path = FONT_DIR / f"thai-{size}.json"
        j_path.write_text(emit_json(size, glyphs, line_h, base_l), encoding="utf-8")
        drawn = sum(1 for g in glyphs if g.box_w)
        print(f"{c_path.relative_to(REPO_DIR)}  {drawn} glyphs, {c_path.stat().st_size // 1024}K")
        print(f"{j_path.relative_to(REPO_DIR)}  {j_path.stat().st_size // 1024}K")
    (FIRMWARE_DIR / "ct_font_thai.h").write_text(emit_header(raw), encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
