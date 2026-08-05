"""logo ฝั่ง preview — พอร์ตคู่กับ firmware/main/ct_logos.c

ต่างจากพอร์ตคู่ขนานคู่อื่นของโปรเจกต์ตรงที่ *ไม่ได้เขียนรูปซ้ำ* สองฝั่งอ่านผลลัพธ์ของ
`export_logos.py` ชุดเดียวกัน (ที่นี่อ่าน PNG ฝั่งโน้นอ่าน C array ที่ raster มาจาก
SVG ไฟล์เดียวกัน สีถูกบีบเป็น RGB565 ตั้งแต่ตอนนั้นแล้ว) — สิ่งที่ยังพอร์ตกันจริงๆ คือ
*กติกาการค้น*: ไม่เจอสัญลักษณ์แล้วต้องได้ `_default` ไม่ใช่ช่องว่าง

ที่ยังต่างกันได้ราวหนึ่ง LSB คือคณิตของการผสมอัลฟา — PIL ผสมบนช่อง 8 บิต LVGL ผสม
บน 565 ผลต่างมองไม่เห็นบนพื้นเข้ม และการไล่ให้ตรงเป๊ะแปลว่าต้องเขียน blender เองใน
Python ซึ่งแพงกว่าสิ่งที่มันซื้อ
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from PIL import Image

from .config import TOOLS_DIR

PNG_DIR = TOOLS_DIR / "logos" / "png"
DEFAULT_NAME = "_default"


@lru_cache(maxsize=None)
def _load(name: str, px: int) -> Image.Image | None:
    path: Path = PNG_DIR / f"{name}-{px}.png"
    if not path.exists():
        return None
    return Image.open(path).convert("RGBA")


# ตอนลิงก์หลุด ทั้งหน้าพูดเป็นเสียงเดียวว่าตัวเลขไม่สดแล้ว (ตัวหนังสือเป็น gray ลูกศรกับ
# spark หม่นตาม) logo จึงต้องหม่นด้วย ไม่งั้นของที่ฉูดฉาดที่สุดบนหน้าจะเป็นชิ้นเดียวที่
# ไม่ยอมบอกว่ามันเก่า · **ไม่ยุบเหลือสีเดียว** — จานกับ glyph ที่กลายเป็นสีเดียวกันแปลว่า
# BTC เหลือวงกลมทึบ ETH เหลือข้าวหลามตัดทึบ พอดีตอนที่ภาพนั้นค้างบนจอนานที่สุด
# ผสมเข้าหาเทาแทน: คอนทราสต์ในตัว logo อยู่ครบ แค่ไม่ส่งเสียง
#
# ฝั่งบอร์ดคือ LV_STYLE_IMAGE_RECOLOR + RECOLOR_OPA ค่าเดียวกัน ไม่ต้องเก็บรูปเทาเพิ่ม
# (`CT_LOGO_DIM_OPA` ใน ct_logos.h ซึ่ง export_logos.py คายมาจาก DIM_OPA ของมันเอง)
DIM_MIX = 153  # 60% ของ 255
DIM_RGB = (0x5C, 0x5C, 0x5C)  # [palette] gray


def _quantize565(v: tuple[int, int, int]) -> tuple[int, int, int]:
    r, g, b = v
    return (((r >> 3) * 255 + 15) // 31, ((g >> 2) * 255 + 31) // 63,
            ((b >> 3) * 255 + 15) // 31)


@lru_cache(maxsize=None)
def _dimmed(name: str, px: int) -> Image.Image | None:
    ic = _load(name, px)
    if ic is None:
        return None
    out = ic.copy()
    src = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = src[x, y]
            mixed = tuple((c * (255 - DIM_MIX) + d * DIM_MIX) // 255
                          for c, d in zip((r, g, b), DIM_RGB))
            src[x, y] = (*_quantize565(mixed), a)
    return out


def paste(img: Image.Image, symbol: str | None, x: int, y: int, px: int,
          connected: bool = True) -> None:
    """แปะ logo ลงภาพหน้าจอ ใช้อัลฟาของตัวมันเองเป็นหน้ากาก

    เงียบไปเฉยๆ ได้กรณีเดียว: ยังไม่เคยรัน `export_logos.py` (โฟลเดอร์ png ว่าง) ซึ่ง
    เป็นสภาพของ working copy ไม่ใช่ของบอร์ด — ฝั่ง C ไม่มีกรณีนี้ มันคอมไพล์ไม่ผ่าน
    ตั้งแต่แรกถ้าไม่มีตาราง
    """
    name = symbol if (symbol and _load(symbol, px) is not None) else DEFAULT_NAME
    ic = _load(name, px) if connected else _dimmed(name, px)
    if ic is None:
        return
    img.paste(ic, (x, y), ic)
