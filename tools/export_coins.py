#!/usr/bin/env python3
"""tools/coins/*.svg -> firmware/main/ct_coins.{c,h} + tools/coins/png/*.png

logo เหรียญเป็น asset **ชนิดที่สอง** ของโปรเจกต์ — ไม่ใช่ rect list เหมือนมาสคอตกับ
prop ทั้งหมด เหตุผลและทางที่ปฏิเสธอยู่ใน docs/adr/ (ย่อ: logo จริงไม่ได้ประกอบจาก
สี่เหลี่ยม และ mask สองสีทำให้ BTC/ETH/USDT กลายเป็นจานทึบที่แยกกันไม่ออก)

ต้นฉบับคือ SVG ในโฟลเดอร์นี้ ไม่ใช่ไฟล์ที่สคริปต์นี้คายออกมา — `ct_coins.c` กับ PNG
ทุกใบถูกเขียนทับทุกครั้งที่รัน แก้มือไปก็หายรอบหน้า

    python3 tools/export_coins.py

PNG ที่คายออกมามีผู้ใช้สองราย ทั้งคู่ต้องเห็นสีชุดเดียวกับบอร์ด:
  * `tools/gen/coins.py` (preview)
  * หน้าตั้งค่าของแอป Mac (`make-app.sh` ก๊อปเข้า Resources)
สีจึงถูกบีบเป็น RGB565 **ตั้งแต่ตอน raster** ไม่ใช่ตอนวาด — ถ้าปล่อยให้ PNG เก็บสี 8 บิต
เต็มไว้ หน้าตั้งค่าบน Mac จะสวยกว่าจอจริง แล้วผู้ใช้เลือกของที่เห็นแต่ได้ของอีกแบบ
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

from gen.config import REPO_DIR, TOOLS_DIR  # noqa: E402

SVG_DIR = TOOLS_DIR / "coins"
PNG_DIR = SVG_DIR / "png"
OUT_C = REPO_DIR / "firmware" / "main" / "ct_coins.c"
OUT_H = REPO_DIR / "firmware" / "main" / "ct_coins.h"

# ชื่อไฟล์คือ key ที่บอร์ดค้น ไม่มีตารางแม็ปแยก — ตารางแม็ปคือของที่ลืมอัปเดตได้
# ตัวที่ขึ้นต้นด้วย `_` ไม่ใช่เหรียญ: `_default.svg` คือรูปของเหรียญที่เราไม่รู้จัก
DEFAULT_NAME = "_default"

# สองขนาดที่หน้า watchlist ใช้ — ต้องตรงกับ [crypto] icon_px / row_icon_px ใน layout.toml
# raster **แยกขนาด** จาก SVG ตรงๆ ไม่ใช่ย่อ 32 ลงมาเป็น 16: การย่อ 2:1 ทำให้เส้นบาง
# (ข้าวหลามตัดของ ETH, เส้นขวางของ XRP) จางจนหายไปทั้งเส้น
SIZES = (32, 16)

# เพดานจำนวนเหรียญ — ทุกเหรียญกิน RGB565A8 เท่ากันเป๊ะ (32² + 16²) x 3 ไบต์ = 3,840 B
# จำนวนไฟล์จึงเป็นหน่วยที่ถูกต้องของงบ ไม่ใช่ตัวประมาณ · 32 เหรียญ = 123 KB บน
# partition `factory` 3 MB · ด่านอยู่ตรงนี้เพราะ "หย่อน SVG ลงโฟลเดอร์" เป็นท่าที่ง่าย
# จนโตไปเงียบๆ ได้ จนวันที่ flash ไม่ลง ซึ่งเป็นวันที่สายเกินจะรู้
MAX_COINS = 32
BYTES_PER_COIN = sum(px * px * 3 for px in SIZES)


# --- raster ---------------------------------------------------------------------
# ไม่มี backend ตัวไหนเป็นเงื่อนไขของการ *build* firmware หรือรัน preview — มันจำเป็น
# เฉพาะตอน export ซึ่งเกิดตอนเพิ่มเหรียญเท่านั้น (แบบเดียวกับที่ export_thai_font.py
# ต้องมีไฟล์ Sarabun อยู่) เครื่องที่แค่ดึงโค้ดมาคอมไพล์จึงไม่ต้องลงอะไรเลย
def _resvg(svg: Path, px: int, out: Path) -> bool:
    exe = shutil.which("resvg")
    if not exe:
        return False
    subprocess.run([exe, "--width", str(px), "--height", str(px), str(svg), str(out)],
                   check=True, capture_output=True)
    return True


def _rsvg_convert(svg: Path, px: int, out: Path) -> bool:
    exe = shutil.which("rsvg-convert")
    if not exe:
        return False
    subprocess.run([exe, "-w", str(px), "-h", str(px), "-o", str(out), str(svg)],
                   check=True, capture_output=True)
    return True


def _cairosvg(svg: Path, px: int, out: Path) -> bool:
    try:
        import cairosvg  # noqa: PLC0415
    except ImportError:
        return False
    cairosvg.svg2png(url=str(svg), write_to=str(out), output_width=px, output_height=px)
    return True


BACKENDS = (("resvg", _resvg), ("rsvg-convert", _rsvg_convert), ("cairosvg", _cairosvg))


def rasterize(svg: Path, px: int) -> Image.Image:
    """SVG -> ภาพ RGBA ขนาด px x px ที่บีบสีเป็น RGB565 แล้ว"""
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "o.png"
        for name, fn in BACKENDS:
            if fn(svg, px, out):
                break
        else:
            raise SystemExit(
                "ไม่พบตัวแปลง SVG สักตัว — ลงอันใดอันหนึ่ง:\n"
                "  brew install resvg          (แนะนำ: binary เดี่ยว ไม่มี native ext ให้พัง)\n"
                "  brew install librsvg\n"
                "  brew install cairo && pip install cairosvg")
        img = Image.open(out).convert("RGBA")
    if img.size != (px, px):
        # backend ที่ไม่เคารพ --width จะทำให้ stride ฝั่ง C ผิดโดยที่คอมไพล์ผ่าน
        raise SystemExit(f"{svg.name}: backend คืนขนาด {img.size} ไม่ใช่ {px}x{px}")
    return quantize565(img)


def quantize565(img: Image.Image) -> Image.Image:
    """บีบสีลง RGB565 แล้วขยายกลับ — สีที่ตาเห็นบนจอจริง

    เดินตามสูตรเดียวกับ `gen/render.quantize565` เป๊ะ (ปัดขึ้นครึ่งด้วย +15/+31)
    ถ้าสองที่นี้ปัดคนละแบบ preview กับบอร์ดจะเพี้ยนกันทีละ 1 LSB ทั้งจอโดยไม่มีใครเห็น
    """
    r, g, b, a = img.split()
    r = r.point(lambda v: ((v >> 3) * 255 + 15) // 31)
    g = g.point(lambda v: ((v >> 2) * 255 + 31) // 63)
    b = b.point(lambda v: ((v >> 3) * 255 + 15) // 31)
    return Image.merge("RGBA", (r, g, b, a))


# --- ฝั่ง C ----------------------------------------------------------------------
def rgb565a8(img: Image.Image) -> bytes:
    """RGBA -> LV_COLOR_FORMAT_RGB565A8

    LVGL เก็บสองระนาบต่อกัน ไม่ใช่สลับต่อพิกเซล: สี RGB565 ทั้งภาพก่อน (w*h*2 ไบต์)
    แล้วค่อยตามด้วยอัลฟา 8 บิตทั้งภาพ (w*h) · `stride` ในหัวจึงเป็นของระนาบสีอย่างเดียว
    """
    px = img.load()
    w, h = img.size
    color = bytearray()
    alpha = bytearray()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            v = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
            color += v.to_bytes(2, "little")  # LVGL อ่านเป็น uint16 บนเครื่อง little-endian
            alpha.append(a)
    return bytes(color + alpha)


def c_array(name: str, data: bytes) -> list[str]:
    lines = [f"static const uint8_t {name}[] = {{"]
    for i in range(0, len(data), 16):
        lines.append("    " + " ".join(f"0x{b:02X}," for b in data[i:i + 16]))
    lines += ["};", ""]
    return lines


def c_dsc(name: str, px: int, size: int) -> list[str]:
    return [
        f"static const lv_image_dsc_t {name} = {{",
        "    .header = {",
        "        .magic = LV_IMAGE_HEADER_MAGIC,",
        "        .cf = LV_COLOR_FORMAT_RGB565A8,",
        "        .flags = 0,",
        f"        .w = {px},",
        f"        .h = {px},",
        f"        .stride = {px * 2},",
        "        .reserved_2 = 0,",
        "    },",
        f"    .data_size = {size},",
        f"    .data = {name}_map,",
        "};",
        "",
    ]


def build(coins: list[str], images: dict[tuple[str, int], bytes]) -> tuple[str, str]:
    banner = [
        "// สร้างอัตโนมัติจาก tools/coins/*.svg — ห้ามแก้ไฟล์นี้ด้วยมือ",
        "// แก้ที่ SVG แล้วรัน: python3 tools/export_coins.py",
        "",
    ]

    h = banner + [
        "#pragma once",
        "",
        "#include \"lvgl.h\"",
        "",
        f"#define CT_COINS_COUNT {len(coins)}",
        f"#define CT_COINS_MAX   {MAX_COINS}",
        f"#define CT_COIN_PX_CARD {SIZES[0]}",
        f"#define CT_COIN_PX_ROW  {SIZES[1]}",
        "",
        "// สัญลักษณ์ที่ไม่มีในตารางได้รูปของ `_default.svg` — ไม่เคยคืน NULL",
        "// เหรียญที่เราไม่รู้จักต้องกินที่เท่ากับเหรียญที่รู้จัก ไม่งั้นคอลัมน์แหว่งเป็นแถวๆ",
        "// ปนกับแถวที่มีรูป ซึ่งเป็นสิ่งเดียวที่คอลัมน์นี้มีไว้กัน",
        "const lv_image_dsc_t *ct_coin_card(const char *sym);",
        "const lv_image_dsc_t *ct_coin_row(const char *sym);",
        "",
    ]

    c = banner + [
        "#include \"ct_coins.h\"",
        "",
        "#include <string.h>",
        "",
    ]
    for name in coins + [DEFAULT_NAME]:
        for px in SIZES:
            sym = f"ct_coin_{c_name(name)}_{px}"
            data = images[(name, px)]
            c += c_array(f"{sym}_map", data)
            c += c_dsc(sym, px, len(data))

    c += [
        "typedef struct {",
        "    const char *sym;",
        f"    const lv_image_dsc_t *px{SIZES[0]};",
        f"    const lv_image_dsc_t *px{SIZES[1]};",
        "} ct_coin_entry_t;",
        "",
        "// ค้นแบบไล่ทีละตัว ไม่ใช่ binary search — ตารางยาวได้ 32 แถว และการค้นเกิด",
        "// เฉพาะตอนวาดหน้าใหม่ (ไม่เกินนาทีละครั้ง) ตารางที่ต้องเรียงถูกเสมอคือตารางที่",
        "// พังเงียบได้ตอนมีคนเพิ่มไฟล์ ส่วน strcmp 32 ครั้งคือค่าที่วัดไม่ออก",
        "static const ct_coin_entry_t s_coins[] = {",
    ]
    for name in coins:
        n = c_name(name)
        c.append(f"    {{\"{name}\", &ct_coin_{n}_{SIZES[0]}, &ct_coin_{n}_{SIZES[1]}}},")
    d = c_name(DEFAULT_NAME)
    c += [
        "};",
        "",
        "static const ct_coin_entry_t s_default = {",
        f"    \"\", &ct_coin_{d}_{SIZES[0]}, &ct_coin_{d}_{SIZES[1]}",
        "};",
        "",
        "static const ct_coin_entry_t *lookup(const char *sym)",
        "{",
        "    if (sym) {",
        "        for (int i = 0; i < CT_COINS_COUNT; i++) {",
        "            if (strcmp(s_coins[i].sym, sym) == 0) return &s_coins[i];",
        "        }",
        "    }",
        "    return &s_default;",
        "}",
        "",
        f"const lv_image_dsc_t *ct_coin_card(const char *sym) {{ return lookup(sym)->px{SIZES[0]}; }}",
        "",
        f"const lv_image_dsc_t *ct_coin_row(const char *sym) {{ return lookup(sym)->px{SIZES[1]}; }}",
        "",
    ]
    return "\n".join(h), "\n".join(c)


def c_name(name: str) -> str:
    """ชื่อไฟล์ -> ตัวระบุ C — `_default` ผ่านได้อยู่แล้ว ตัวอื่นเป็น A-Z0-9 ตามสัญลักษณ์"""
    return "".join(ch if ch.isalnum() or ch == "_" else "_" for ch in name)


def main() -> None:
    svgs = sorted(SVG_DIR.glob("*.svg"))
    names = [p.stem for p in svgs]
    if DEFAULT_NAME not in names:
        raise SystemExit(f"ต้องมี {DEFAULT_NAME}.svg — เหรียญที่ไม่รู้จักไม่มีรูปให้วาด")

    coins = [n for n in names if not n.startswith("_")]
    bad = [n for n in coins if n != n.upper() or not n.isalnum()]
    if bad:
        # ชื่อไฟล์คือ key ที่เทียบกับสัญลักษณ์บนสาย ซึ่ง CryptoSource ทำ .uppercased() มาแล้ว
        # ไฟล์ชื่อ `btc.svg` จะไม่มีวันถูกค้นเจอ และไม่มีอะไรฟ้อง — จับที่นี่แทน
        raise SystemExit(f"ชื่อไฟล์ต้องเป็นสัญลักษณ์ตัวใหญ่ล้วน: {', '.join(bad)}")
    if len(coins) > MAX_COINS:
        raise SystemExit(
            f"{len(coins)} เหรียญ เกินเพดาน {MAX_COINS} "
            f"({len(coins) * BYTES_PER_COIN // 1024} KB) — ตัดออกหรือขยับเพดานพร้อมวัด "
            "ขนาด .bin จริงก่อน")

    PNG_DIR.mkdir(parents=True, exist_ok=True)
    for old in PNG_DIR.glob("*.png"):
        old.unlink()  # เหรียญที่ถูกลบ SVG ทิ้งต้องไม่ทิ้ง PNG ค้างให้ preview ไปหยิบ

    images: dict[tuple[str, int], bytes] = {}
    for path in svgs:
        for px in SIZES:
            img = rasterize(path, px)
            img.save(PNG_DIR / f"{path.stem}-{px}.png")
            images[(path.stem, px)] = rgb565a8(img)

    h, c = build(coins, images)
    OUT_H.write_text(h, encoding="utf-8")
    OUT_C.write_text(c, encoding="utf-8")

    total = (len(coins) + 1) * BYTES_PER_COIN
    print(f"{len(coins)} coins + default, {total / 1024:.1f} KB -> {OUT_C.name}")


if __name__ == "__main__":
    main()
