import AppKit
import TamaCore

/// แบดจ์บนแถบเมนูในรูปภาพเดียว — แถบ pill สั้นๆ กับเปอร์เซ็นต์
///
/// อยู่คนละไฟล์กับ `MenuBarApp` เพราะเป็นคนละเหตุผลที่จะแก้: ไฟล์นั้นเปลี่ยนเมื่อเมนู
/// มีรายการใหม่หรือ daemon ต่อสายใหม่ ไฟล์นี้เปลี่ยนเมื่อหน้าตาของแบดจ์เปลี่ยน
enum MenuBadgeImage {
    private static let barWidth: CGFloat = 22
    private static let barHeight: CGFloat = 6
    private static let gap: CGFloat = 4
    private static let height: CGFloat = 14

    /// ไอคอนตอนไม่มีอะไรจะบอก — `0%` ที่เดาเอาคือคำโกหกที่ดูเหมือนค่าที่วัดมา
    /// ส่วนแถบเปล่าดูเหมือนแอปพัง
    static func fallback() -> NSImage? {
        let icon = NSImage(
            systemSymbolName: "desktopcomputer", accessibilityDescription: "tamaclaude")
        icon?.isTemplate = true
        return icon
    }

    /// ปกติเป็น template ขาวดำ ระบบจึงกลับสีให้เองทั้งพื้นสว่าง/มืด และตอนเมนูถูกไฮไลต์
    /// ตอนต้องเตือนเลิกเป็น template แล้ววาดแดงตรงๆ — สีที่ระบบกลับได้ตามใจ
    /// ไม่สามารถแปลว่า "แดง" ได้
    ///
    /// ยกเว้นตอนเมนูเปิด (`highlighted`) ซึ่งระบบถมพื้นปุ่มด้วยสีเน้นแล้ววาดภาพที่ไม่ใช่
    /// template ทับตรงๆ — แดงบนน้ำเงินอ่านไม่ออก ตอนนั้นกลับไปเป็น template
    /// เสียสีแดงไปชั่วขณะที่ผู้ใช้กำลังอ่านเมนูอยู่แล้ว ดีกว่าเสียตัวเลขไปทั้งตัว
    static func make(_ badge: MenuBadge, highlighted: Bool) -> NSImage {
        let template = !badge.isAlarming || highlighted
        // ขาวดำมาจาก isTemplate ไม่ใช่จากสีที่วาด — วาดดำแล้วระบบเก็บแค่ alpha ไปใช้
        let ink: NSColor = template ? .black : .systemRed
        let text = "\(badge.percent)%" as NSString
        // ตัวเลขความกว้างคงที่ ไม่งั้นไอคอนขยับซ้ายขวาทุกครั้งที่เปอร์เซ็นต์เปลี่ยนหลัก
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: ink,
        ]
        let textSize = text.size(withAttributes: attributes)
        let size = NSSize(width: barWidth + gap + ceil(textSize.width), height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            let bar = NSRect(
                x: 0, y: (height - barHeight) / 2, width: barWidth, height: barHeight)
            let pill = NSBezierPath(
                roundedRect: bar, xRadius: barHeight / 2, yRadius: barHeight / 2)
            // รางจางแต่ยังเห็น — แถบที่ไม่มีรางบอกไม่ได้ว่า 20% นี้คือ 20% ของเท่าไร
            ink.withAlphaComponent(0.3).setFill()
            pill.fill()

            let filled = barWidth * CGFloat(min(100, max(0, badge.percent))) / 100
            if filled > 0 {
                // ตัดด้วย clip ไม่ใช่วาด pill ที่แคบลง ไม่งั้นปลายซ้ายของเนื้อแถบ
                // จะโค้งตามความยาวของตัวเอง แทนที่จะโค้งตามราง
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(
                    rect: NSRect(x: bar.minX, y: bar.minY, width: filled, height: barHeight)
                ).setClip()
                ink.setFill()
                pill.fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            text.draw(
                at: NSPoint(x: barWidth + gap, y: (height - textSize.height) / 2),
                withAttributes: attributes)
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = description(badge)
        return image
    }

    static func description(_ badge: MenuBadge) -> String {
        "\(badge.percent)% of the 5 hour window used"
    }
}
