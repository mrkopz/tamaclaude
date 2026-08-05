#!/bin/bash
# ประกอบ TamaClaude.app
#
#   ./Scripts/make-app.sh              บิลด์ release ไว้ที่ host/dist/TamaClaude.app
#   ./Scripts/make-app.sh --install    บิลด์แล้วติดตั้งลง /Applications และเปิดให้เลย
#   ./Scripts/make-app.sh --debug      บิลด์ debug (ไว้ตอนพัฒนา)
#
# ทำไมต้องเป็น .app: TCC บน macOS 26 ไม่ยอมรับ Mach-O เปล่าแม้จะฝัง __info_plist ไว้แล้ว
# และคำขอสิทธิ์ Bluetooth จะถูกผูกกับ "responsible process" ซึ่งคือ Terminal ถ้ารันจากเชลล์
# ผลคือ SIGABRT (__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__) ไม่ใช่การปฏิเสธแบบสุภาพ
# ต้องเปิดผ่าน LaunchServices (`open`) หรือดับเบิลคลิกจาก Finder เท่านั้น
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="$(cd .. && pwd)"

CONFIG=release
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --debug) CONFIG=debug ;;
        *) echo "unknown option $arg" >&2; exit 1 ;;
    esac
done

# ไอคอนมาจาก docs/images/tamaclaude-logo.png ผ่าน make_icon.py (เติมขอบ + ทำ .icns)
if [ ! -f Resources/AppIcon.icns ]; then
    python3 "$REPO/tools/make_icon.py"
fi

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/tamaclaude"
APP="dist/TamaClaude.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/tamaclaude"
cp Sources/tamaclaude/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# logo เหรียญของหน้าตั้งค่า — ใบ 32px ชุดเดียวกับที่บอร์ดวาด (ใบ 16px เป็นของบอร์ดล้วน)
# ก๊อปตอนประกอบ .app ไม่ได้ผูกเป็น resource ของ SwiftPM: ไฟล์พวกนี้เกิดจาก
# tools/export_coins.py ซึ่งอยู่คนละฝั่งของรีโปกับ Package.swift และคนที่แค่ `swift build`
# ไม่ควรถูกบังคับให้มีตัวแปลง SVG บนเครื่อง (CoinIconImage ยอมไม่มีรูปได้)
if [ -d "$REPO/tools/coins/png" ]; then
    mkdir -p "$APP/Contents/Resources/coins"
    cp "$REPO"/tools/coins/png/*-32.png "$APP/Contents/Resources/coins/" 2>/dev/null || true
fi

# ลายเซ็น adhoc: พอสำหรับเครื่องที่บิลด์เอง แต่สิทธิ์ TCC ผูกกับ cdhash
# บิลด์ใหม่ = ตัวตนใหม่ = macOS ถามสิทธิ์ Bluetooth อีกรอบ
# การแจกให้เครื่องอื่นต้องใช้ Developer ID + notarization ซึ่งต้องมีบัญชีนักพัฒนา
codesign --force --deep --sign - --identifier com.tamaclaude.daemon "$APP" >/dev/null
echo "built $PWD/$APP"

if [ "$INSTALL" = "1" ]; then
    DEST="/Applications/TamaClaude.app"
    # เคยชื่อ tamaclaude.app — ตัวเก่าต้องถูกลบ ไม่ใช่แค่ถูกทับ สองบันเดิลที่รันได้พร้อมกัน
    # จะแย่ง socket กัน แล้วตัวที่แพ้เด้ง alert ทิ้ง · pkill ครอบทั้งสองชื่อด้วยเหตุผลเดียวกัน
    LEGACY="/Applications/tamaclaude.app"
    # ตัวเก่าอาจรันอยู่ ปิดก่อนไม่งั้นได้ไบนารีเก่าค้างในหน่วยความจำ และตัวใหม่จะจอง
    # socket ไม่ได้แล้วเด้ง alert ทิ้ง — ต้องปิดให้ตายจริงก่อน ไม่ใช่ส่งสัญญาณแล้วเดินต่อ
    RUNNING="[Tt]ama[Cc]laude\.app/Contents/MacOS/tamaclaude"
    pkill -f "$RUNNING" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
        pgrep -f "$RUNNING" >/dev/null || break
        sleep 1
    done
    # จำไว้ *ก่อน* ลบ — คำเตือนข้างล่างต้องขึ้นเฉพาะรอบที่ย้ายชื่อจริง คำเตือนที่ขึ้นทุกรอบ
    # ทั้งที่ไม่มีอะไรเปลี่ยนคือคำเตือนที่ผู้ใช้เลิกอ่านตั้งแต่ครั้งที่สอง
    #
    # ถามจากรายชื่อในโฟลเดอร์ ไม่ใช่ `[ -d "$LEGACY" ]` — APFS ปริยายไม่แยกตัวพิมพ์
    # `TamaClaude.app` ที่เพิ่งติดตั้งไปจึงตอบว่า "มี" ให้กับพาธชื่อเก่าทุกครั้ง
    RENAMED=0
    if ls /Applications | grep -qxF 'tamaclaude.app'; then RENAMED=1; fi
    rm -rf "$DEST" "$LEGACY"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "installed $DEST and launched it"
    echo "อนุญาต Bluetooth เมื่อระบบถาม แล้วเปิดเมนูจากไอคอนบนแถบเมนู"
    # hook กับ statusline เก็บ *พาธเต็ม* ของ binary ไว้ตอนกดติดตั้ง การเปลี่ยนชื่อบันเดิล
    # จึงทำให้พาธนั้นชี้ไปที่ไฟล์ที่ไม่มีแล้ว — เงียบ ไม่มี error ให้เห็น
    if [ "$RENAMED" = "1" ]; then
        echo "ลบ $LEGACY ตัวเก่าแล้ว — กด Install hooks กับ Usage display ในเมนูเฟืองซ้ำหนึ่งครั้ง"
    fi
fi
