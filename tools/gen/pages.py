"""ชนิดของ page — ด้านที่สามของสัญญาเดียวกัน (ADR-0004)

ลำดับในลิสต์นี้ *คือ* ตัวเลขที่เดินทางบนสาย ต้องตรงกับ `ct_page_kind_t`
(firmware/main/ct_pages.h) และ `PageKind` (host/Sources/TamaCore/Pages.swift)
การเพิ่มหน้าใหม่แพงโดยตั้งใจ — ต้องแก้สามฝั่งแล้วแฟลชบอร์ด
"""

from __future__ import annotations

PAGES = ("mascot", "weather")


def kind(name: str) -> int:
    return PAGES.index(name)
