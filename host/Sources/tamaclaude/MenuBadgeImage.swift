import AppKit
import TamaCore

/// แบดจ์บนแถบเมนูในรูปภาพเดียว — แถบ pill สั้นๆ กับเปอร์เซ็นต์
///
/// อยู่คนละไฟล์กับ `MenuBarApp` เพราะเป็นคนละเหตุผลที่จะแก้: ไฟล์นั้นเปลี่ยนเมื่อเมนู
/// มีรายการใหม่หรือ daemon ต่อสายใหม่ ไฟล์นี้เปลี่ยนเมื่อหน้าตาของแบดจ์เปลี่ยน
enum MenuBadgeImage {
    private static let barWidth: CGFloat = 34
    private static let barHeight: CGFloat = 11
    private static let gap: CGFloat = 5
    /// 17 คือเพดานที่ปลอดภัยของภาพบนแถบเมนู — สูงกว่านี้ระบบย่อให้เองแล้วเส้นขอบ 1 px
    /// กลายเป็นเส้นเบลอครึ่งพิกเซล ความสูงนี้ต้องพอให้ขีด pace ล้นแถบได้ทั้งบนและล่าง
    private static let height: CGFloat = 17
    private static let border: CGFloat = 1
    /// ขีด pace ล้นขอบแถบข้างละ 2 px เหมือนบนจอ — ตรงที่มันทับเนื้อแถบพอดี
    /// สีเดียวกันทำให้มันหายไป ส่วนที่ล้นออกมาคือส่วนที่มองเห็นได้เสมอ
    private static let paceOvershoot: CGFloat = 2

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
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: ink,
        ]
        let textSize = text.size(withAttributes: attributes)
        let size = NSSize(width: barWidth + gap + ceil(textSize.width), height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            // หดเข้ามาครึ่งเส้น เพราะ stroke วาดคร่อมเส้นทาง ครึ่งนอกจะถูกขอบภาพตัดทิ้ง
            let bar = NSRect(
                x: border / 2, y: (height - barHeight) / 2,
                width: barWidth - border, height: barHeight - border)
            let pill = NSBezierPath(
                roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2)
            // รางจางแต่ยังเห็น — แถบที่ไม่มีรางบอกไม่ได้ว่า 20% นี้คือ 20% ของเท่าไร
            ink.withAlphaComponent(0.25).setFill()
            pill.fill()

            let filled = bar.width * CGFloat(min(100, max(0, badge.percent))) / 100
            if filled > 0 {
                // ตัดด้วย clip ไม่ใช่วาด pill ที่แคบลง ไม่งั้นปลายซ้ายของเนื้อแถบ
                // จะโค้งตามความยาวของตัวเอง แทนที่จะโค้งตามราง
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(
                    rect: NSRect(x: bar.minX, y: bar.minY, width: filled, height: bar.height)
                ).setClip()
                ink.setFill()
                pill.fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            // ขอบทึบวาดทับท้ายสุด — บนพื้นแถบเมนูที่มีวอลเปเปอร์อยู่ข้างหลัง รางจางๆ
            // อย่างเดียวหายไปกับพื้น เส้นขอบคือสิ่งที่บอกว่าแถบเริ่มและจบตรงไหน
            ink.setStroke()
            pill.lineWidth = border
            pill.stroke()

            // ขีด "ควรใช้ถึงไหนแล้ว" — ขีดอยู่ขวาของเนื้อแถบ = ใช้ช้ากว่าเวลา
            // อยู่ซ้าย = ใช้เร็วเกินไป ภาษาเดียวกับแผงบนบอร์ด
            if badge.pace != MenuBadge.unknown {
                let at = bar.minX + bar.width * CGFloat(min(100, max(0, badge.pace))) / 100
                ink.setFill()
                NSBezierPath(
                    rect: NSRect(
                        x: min(at, barWidth - border), y: bar.minY - paceOvershoot,
                        width: border, height: bar.height + 2 * paceOvershoot)
                ).fill()
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
        let used = "\(badge.percent)% of the 5 hour window used"
        guard badge.pace != MenuBadge.unknown else { return used }
        // ขีดบนภาพบอกเรื่องนี้กับตา คำอธิบายต้องบอกเรื่องเดียวกันกับคนที่ไม่ได้ใช้ตาอ่าน
        return used + ", \(badge.pace)% of the window elapsed"
    }
}
