"""อ่าน layout.toml — ต้นทางเดียวของค่าคงที่ทั้ง Python และ C"""

from __future__ import annotations

import tomllib
from pathlib import Path
from types import SimpleNamespace

TOOLS_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = TOOLS_DIR.parent
LAYOUT_TOML = TOOLS_DIR / "layout.toml"


def _ns(d: dict) -> SimpleNamespace:
    return SimpleNamespace(**{k: (_ns(v) if isinstance(v, dict) else v) for k, v in d.items()})


with LAYOUT_TOML.open("rb") as fh:
    _raw = tomllib.load(fh)

L = _ns(_raw)
PAL = L.palette
