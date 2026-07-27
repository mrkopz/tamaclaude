#!/bin/bash
# ประกอบ tamaclaude.app
#
#   ./Scripts/make-app.sh              บิลด์ release ไว้ที่ host/dist/tamaclaude.app
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

# ไอคอนมาจากมาสคอตตัวเดียวกับบนจอ ไม่ใช่ภาพแยกอีกชุด
if [ ! -f Resources/AppIcon.icns ]; then
    python3 "$REPO/tools/make_icon.py"
fi

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/tamaclaude"
APP="dist/tamaclaude.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/tamaclaude"
cp Sources/tamaclaude/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# ลายเซ็น adhoc: พอสำหรับเครื่องที่บิลด์เอง แต่สิทธิ์ TCC ผูกกับ cdhash
# บิลด์ใหม่ = ตัวตนใหม่ = macOS ถามสิทธิ์ Bluetooth อีกรอบ
# การแจกให้เครื่องอื่นต้องใช้ Developer ID + notarization ซึ่งต้องมีบัญชีนักพัฒนา
codesign --force --deep --sign - --identifier com.tamaclaude.daemon "$APP" >/dev/null
echo "built $PWD/$APP"

if [ "$INSTALL" = "1" ]; then
    DEST="/Applications/tamaclaude.app"
    # ตัวเก่าอาจรันอยู่ ปิดก่อนไม่งั้นได้ไบนารีเก่าค้างในหน่วยความจำ และตัวใหม่จะจอง
    # socket ไม่ได้แล้วเด้ง alert ทิ้ง — ต้องปิดให้ตายจริงก่อน ไม่ใช่ส่งสัญญาณแล้วเดินต่อ
    pkill -f "tamaclaude.app/Contents/MacOS/tamaclaude" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
        pgrep -f "tamaclaude.app/Contents/MacOS/tamaclaude" >/dev/null || break
        sleep 1
    done
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "installed $DEST and launched it"
    echo "อนุญาต Bluetooth เมื่อระบบถาม แล้วเปิดเมนูจากไอคอนบนแถบเมนู"
fi
