import AppKit
import TamaCore

/// การ์ดโควตาหนึ่งใบ — หัวแถว, แถบพร้อมขีด pace, แล้วเวลารีเซ็ต
///
/// อยู่คนละไฟล์กับ `PanelViewController` ด้วยเหตุผลเดียวกับ `MenuBadgeImage`:
/// ไฟล์นั้นเปลี่ยนเมื่อโครงของแผงเปลี่ยน ไฟล์นี้เปลี่ยนเมื่อหน้าตาของการ์ดเปลี่ยน
/// สิ่งที่*พูด* อยู่ที่ `QuotaCard` ใน TamaCore ที่นี่มีแต่วิธีวาด
final class QuotaCardView: NSView {
    /// สีของสามขั้น — ตรงกับ `[palette]` ใน tools/layout.toml เพื่อให้แผงบนบอร์ด
    /// กับแผงบนเมนูบาร์เป็นภาษาเดียวกัน ไม่ใช่สีระบบที่บังเอิญชื่อเหมือนกัน
    static func color(_ level: QuotaCard.Level) -> NSColor {
        switch level {
        case .good: return NSColor(srgbRed: 0x5F / 255, green: 0xA8 / 255, blue: 0x5F / 255,
                                   alpha: 1)
        case .warn: return NSColor(srgbRed: 0xE8 / 255, green: 0xB8 / 255, blue: 0x4B / 255,
                                   alpha: 1)
        case .crit: return NSColor(srgbRed: 0xD9 / 255, green: 0x56 / 255, blue: 0x4F / 255,
                                   alpha: 1)
        // ไม่รู้ = สีของข้อความจาง ไม่ใช่เขียว — สีที่ดูปลอดภัยบนค่าที่ไม่มีคือการโกหก
        case .unknown: return .tertiaryLabelColor
        }
    }

    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let percent = NSTextField(labelWithString: "")
    private let bar = QuotaBarView()
    private let reset = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        title.font = .systemFont(ofSize: 12, weight: .semibold)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        // คำอธิบายยอมโดนบีบก่อนใคร — ชื่อหน้าต่างกับเปอร์เซ็นต์ห้ามหาย
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // ตัวเลขความกว้างคงที่ ไม่งั้นเปอร์เซ็นต์ขยับซ้ายขวาทุกครั้งที่เปลี่ยนหลัก
        // ในแผงที่วาดใหม่ทุกวินาที
        percent.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        percent.alignment = .right
        percent.setContentHuggingPriority(.required, for: .horizontal)
        percent.setContentCompressionResistancePriority(.required, for: .horizontal)

        reset.font = .systemFont(ofSize: 11)
        reset.textColor = .secondaryLabelColor
        reset.lineBreakMode = .byTruncatingTail

        let head = NSStackView(views: [title, subtitle, NSView(), percent])
        head.orientation = .horizontal
        head.spacing = 6
        head.alignment = .firstBaseline

        let stack = NSStackView(views: [head, bar, reset])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            head.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bar.heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("no nib") }

    func show(_ card: QuotaCard) {
        title.stringValue = card.title
        subtitle.stringValue = card.subtitle
        reset.stringValue = card.reset

        let color = Self.color(card.level)
        // `--%` ไม่ใช่ `0%` — ศูนย์เป็นค่าที่วัดได้จริง ความไม่รู้ต้องหน้าตาไม่เหมือนมัน
        percent.stringValue = card.percent == UsageSnap.unknown ? "--%" : "\(card.percent)%"
        percent.textColor = color

        bar.percent = card.percent
        bar.pace = card.pace
        bar.color = color
        bar.needsDisplay = true
    }
}

/// แถบวัดกับขีด pace — ภาษาเดียวกับแถบบนแถบเมนูและบนบอร์ด
///
/// ขีดอยู่ที่ `elapsed/window` เสมอ ไม่ว่าจะแซงหรือไม่: สีตอบว่ามีปัญหาไหม
/// ขีดตอบว่าห่างแค่ไหน ซึ่งเป็นคำถามที่สีตอบไม่ได้
final class QuotaBarView: NSView {
    var percent = UsageSnap.unknown
    var pace = UsageSnap.unknown
    var color: NSColor = .tertiaryLabelColor

    private let radius: CGFloat = 2.5

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        // รางยังต้องเห็นแม้ไม่มีค่า — แถบที่หายไปทั้งอันอ่านเหมือนแผงวาดไม่เสร็จ
        NSColor.quaternaryLabelColor.setFill()
        track.fill()

        if percent != UsageSnap.unknown {
            let filled = bounds.width * CGFloat(min(100, max(0, percent))) / 100
            if filled > 0 {
                // ตัดด้วย clip ไม่ใช่วาดรางที่แคบลง ไม่งั้นปลายซ้ายของเนื้อแถบจะโค้ง
                // ตามความยาวของตัวเอง แทนที่จะโค้งตามราง
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(
                    rect: NSRect(x: 0, y: 0, width: filled, height: bounds.height)).setClip()
                color.setFill()
                track.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        guard pace != UsageSnap.unknown else { return }
        // ขีดสูงเท่าแถบพอดี วาดทับทั้งเนื้อและราง — ที่นี่วาดบนพื้นทึบของ popover
        // จึงใช้สีของข้อความได้ตรงๆ ไม่ต้องเจาะร่องโปร่งอย่างบนแถบเมนู
        let at = bounds.width * CGFloat(min(100, max(0, pace))) / 100
        let width: CGFloat = 1.5
        // ขีดที่ 100% ครึ่งหนึ่งจะอยู่นอกแถบ — ดันเข้ามาให้เห็นเต็มเส้น
        let x = min(max(0, at - width / 2), bounds.width - width)
        NSColor.labelColor.setFill()
        NSBezierPath(rect: NSRect(x: x, y: 0, width: width, height: bounds.height)).fill()
    }
}
