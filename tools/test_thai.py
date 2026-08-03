#!/usr/bin/env python3
"""ฝั่ง Python ของ golden vectors ไทย — คู่ของ suite("thai clusters") ใน tamatest

    python3 tools/test_thai.py

ทั้งสองฝั่งอ่าน tools/thai-golden.json ไฟล์เดียวกัน ถ้าพอร์ตใดพอร์ตหนึ่งดริฟต์
ฝั่งนั้นจะแดงคนเดียว — นั่นคือทั้งหมดที่เทสต์ชุดนี้มีไว้จับ
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from gen import thai  # noqa: E402

GOLDEN = Path(__file__).resolve().parent / "thai-golden.json"


def main() -> int:
    cases = json.loads(GOLDEN.read_text(encoding="utf-8"))["cases"]
    failed = 0
    for c in cases:
        want = "".join(chr(int(h, 16)) for h in c["out"])
        got = thai.shape(c["in"])
        if got != want:
            failed += 1
            print(f"FAIL {c['name']}")
            print(f"  want {[f'{ord(ch):04X}' for ch in want]}")
            print(f"  got  {[f'{ord(ch):04X}' for ch in got]}")
        w = thai.display_width(c["in"])
        if w != c["width"]:
            failed += 1
            print(f"FAIL {c['name']} — width want {c['width']} got {w}")
    print(f"{len(cases)} cases, {failed} failures")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
