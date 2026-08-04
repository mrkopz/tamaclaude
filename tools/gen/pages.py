"""ชนิดของ page — ด้านที่สามของสัญญาเดียวกัน (ADR-0004)

ลำดับในลิสต์นี้ *คือ* ตัวเลขที่เดินทางบนสาย ต้องตรงกับ `ct_page_kind_t`
(firmware/main/ct_pages.h) และ `PageKind` (host/Sources/TamaCore/Pages.swift)
การเพิ่มหน้าใหม่แพงโดยตั้งใจ — ต้องแก้สามฝั่งแล้วแฟลชบอร์ด
"""

from __future__ import annotations

PAGES = ("mascot", "weather", "crypto", "calendar", "stocks")

# ชื่อที่ขึ้นบนแถบบน — ผูกกับ enum ไม่ใช่ข้อมูลที่เดินทางมากับเฟรม จึงมีชื่อตั้งแต่ก่อนได้
# เฟรมแรก (ADR-0002: หน้าที่ยังไม่เคยได้ข้อมูลก็ต้องมีหน้าตาของตัวเอง) และไม่กินไบต์บนสาย
# ตัวพิมพ์เล็กทั้งหมดตามป้ายเดิมที่มันมาแทน · หน้ามาสคอตใช้ชื่ออุปกรณ์เพราะไม่มีชื่ออื่น
LABELS = {
    "mascot": "tamaclaude",
    "weather": "weather",
    "crypto": "crypto",
    "calendar": "calendar",
    "stocks": "stocks",
}


def kind(name: str) -> int:
    return PAGES.index(name)
