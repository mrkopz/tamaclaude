import AppKit
import TamaCore

/// หน้าตาของ popover ที่เด้งจากไอคอนแถบเมนู
///
/// อยู่คนละไฟล์กับ `MenuBarApp` ด้วยเหตุผลเดียวกับ `MenuBadgeImage`: ไฟล์นั้นเปลี่ยน
/// เมื่อการต่อสายระหว่าง daemon กับ UI เปลี่ยน ไฟล์นี้เปลี่ยนเมื่อหน้าตาของแผงเปลี่ยน
///
/// โครงคือ หัว / เนื้อ / ท้าย โดยเนื้อยังว่างอยู่ — การ์ดโควตามาทีหลัง แต่ช่องของมัน
/// ถูกจองไว้แล้วเพื่อให้การเพิ่มเข้ามาไม่ต้องรื้อลำดับของอย่างอื่น
final class PanelViewController: NSViewController {
    /// ปุ่มเฟืองไม่รู้ว่าเมนูมีอะไร — `MenuBarApp` เป็นเจ้าของ NSMenu ตัวนั้น
    var onGear: ((NSButton) -> Void)?

    private static let width: CGFloat = 260
    private static let inset: CGFloat = 14

    /// ชื่อแอปไปก่อน — ชื่อ org มาพร้อมการ์ดโควตาในใบถัดไป
    private let heading = NSTextField(labelWithString: "tamaclaude")
    private let gear = NSButton()
    /// ที่ว่างของการ์ดโควตา ยังไม่มีอะไร จึงยังไม่กินความสูง
    private let cards = NSStackView()
    private let boardLabel = NSTextField(labelWithString: "")
    private let sessions = NSStackView()
    private var shownRows: [String] = []

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        heading.font = .systemFont(ofSize: 13, weight: .semibold)

        gear.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        gear.isBordered = false
        gear.bezelStyle = .inline
        gear.imagePosition = .imageOnly
        gear.target = self
        gear.action = #selector(gearClicked)
        gear.setContentHuggingPriority(.required, for: .horizontal)
        // เมนูเด้งตอนกดลง ไม่ใช่ตอนปล่อย — เหมือนปุ่มที่มีเมนูทุกตัวใน macOS
        gear.cell?.sendAction(on: .leftMouseDown)

        let header = NSStackView(views: [heading, NSView(), gear])
        header.orientation = .horizontal
        header.distribution = .fill

        cards.orientation = .vertical
        cards.spacing = 8
        cards.alignment = .leading
        // ซ่อนไว้จนกว่าจะมีการ์ด — stack ที่ว่างยังกินระยะห่างของ stack ที่ครอบมันอยู่
        // แผงเปล่าจึงมีช่องว่างลอยๆ ที่ไม่มีอะไรอธิบาย
        cards.isHidden = true

        boardLabel.font = .systemFont(ofSize: 12)
        boardLabel.textColor = .secondaryLabelColor

        sessions.orientation = .vertical
        sessions.spacing = 2
        sessions.alignment = .leading

        let footer = NSStackView(views: [boardLabel, sessions])
        footer.orientation = .vertical
        footer.spacing = 4
        footer.alignment = .leading

        let stack = NSStackView(views: [header, cards, separator(), footer])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        let inset = Self.inset
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Self.width),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -inset),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: inset),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -inset),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
        // view ถูกโหลดตอนแผงเปิดครั้งแรก ซึ่งช้ากว่า snapshot แรกเสมอ — แถวที่มาก่อนหน้านั้น
        // อยู่ใน `sessions` แล้วและต้องรอด ตัวนี้เผื่อไว้เฉพาะกรณีที่ยังไม่เคยมี snapshot เลย
        if shownRows.isEmpty { showSessions(Snapshot(clock: "", date: "")) }
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: Self.width - 2 * Self.inset).isActive = true
        return line
    }

    @objc private func gearClicked() {
        onGear?(gear)
    }

    // MARK: - อัปเดตข้อความ

    func showBoard(connected: Bool) {
        boardLabel.stringValue = PanelText.board(connected: connected)
    }

    /// วาดใหม่เฉพาะตอนข้อความเปลี่ยนจริง — ถูกเรียกทุก snapshot ซึ่งขยับทุกนาที
    /// ตามนาฬิกา ส่วนรายการ session เปลี่ยนนานๆ ครั้ง
    func showSessions(_ snapshot: Snapshot) {
        let rows = PanelText.sessions(snapshot)
        guard rows != shownRows else { return }
        shownRows = rows

        for old in sessions.arrangedSubviews {
            sessions.removeArrangedSubview(old)
            old.removeFromSuperview()
        }
        for row in rows {
            let label = NSTextField(labelWithString: row)
            label.font = .systemFont(ofSize: 12)
            label.lineBreakMode = .byTruncatingTail
            sessions.addArrangedSubview(label)
        }
    }
}
