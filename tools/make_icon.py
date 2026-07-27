#!/usr/bin/env python3
"""ไอคอนแอป — มาสคอตตัวเดียวกับบนจอ ไม่ใช่ภาพวาดแยกอีกชุด

ที่มาเดียวกับทุกอย่างในโปรเจกต์: rect list จาก gen/mascot.py
ถ้ามาสคอตเปลี่ยน ไอคอนเปลี่ยนตามโดยไม่ต้องแก้ที่นี่

ผลลัพธ์: host/Resources/AppIcon.icns
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from PIL import Image, ImageDraw  # noqa: E402

from gen import mascot  # noqa: E402
from gen.config import PAL, REPO_DIR  # noqa: E402
from gen.props import BOX_X0, BOX_X1, BOX_Y0, BOX_Y1  # noqa: E402
from gen.render import draw_rects, quantize565  # noqa: E402

OUT = REPO_DIR / "host" / "Resources" / "AppIcon.icns"

# macOS เว้นขอบรอบไอคอนราว 10% ของด้าน ไอคอนที่ชิดขอบจะดูใหญ่ผิดพวกบน Dock
MASTER = 1024
MARGIN = 0.10
CORNER = 0.22  # รัศมีมุมของ macOS Big Sur เป็นต้นมา ~22% ของด้าน


def render_master() -> Image.Image:
    img = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    inset = round(MASTER * MARGIN)
    side = MASTER - 2 * inset
    draw.rounded_rectangle(
        [inset, inset, MASTER - inset - 1, MASTER - inset - 1],
        radius=round(side * CORNER),
        fill=quantize565(PAL.bg) + (255,),
    )

    # ท่า idle ไม่มี prop ถือ จึงเป็นท่าเดียวที่สมมาตรพอจะเป็นไอคอนได้
    rects = mascot.build_centered("idle", phase=0.0)
    box_w, box_h = BOX_X1 - BOX_X0, BOX_Y1 - BOX_Y0
    px = side * 0.62 / box_w
    ox = MASTER / 2 - (BOX_X0 + BOX_X1) / 2 * px
    # ยึดกึ่งกลางของ *ซิลลูเอ็ต* ไม่ใช่กึ่งกลางกรอบ เพราะกรอบเผื่อที่ให้ prop ไว้ด้านบน
    oy = MASTER / 2 - (BOX_Y1 - box_h * 0.32) * px
    draw_rects(draw, rects, px, ox, oy, true_color=True)
    return img


def main() -> None:
    master = render_master()
    OUT.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for size in (16, 32, 128, 256, 512):
            master.resize((size, size), Image.LANCZOS).save(iconset / f"icon_{size}x{size}.png")
            master.resize((size * 2, size * 2), Image.LANCZOS).save(
                iconset / f"icon_{size}x{size}@2x.png"
            )
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(OUT)], check=True
        )
    print(f"mascot -> {OUT.relative_to(REPO_DIR)}")


if __name__ == "__main__":
    main()
