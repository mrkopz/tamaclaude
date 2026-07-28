import AppKit
import TamaCore

/// หน้าตาของ popover ที่เด้งจากไอคอนแถบเมนู
///
/// อยู่คนละไฟล์กับ `MenuBarApp` ด้วยเหตุผลเดียวกับ `MenuBadgeImage`: ไฟล์นั้นเปลี่ยน
/// เมื่อการต่อสายระหว่าง daemon กับ UI เปลี่ยน ไฟล์นี้เปลี่ยนเมื่อหน้าตาของแผงเปลี่ยน
///
/// โครงคือ หัว / เนื้อ / ท้าย โดยเนื้อคือการ์ดโควตาสองใบกับบรรทัดอายุของค่า
final class PanelViewController: NSViewController {
    /// ปุ่มเฟืองไม่รู้ว่าเมนูมีอะไร — `MenuBarApp` เป็นเจ้าของ NSMenu ตัวนั้น
    var onGear: ((NSButton) -> Void)?
    /// บรรทัด "key หมดอายุ" กดได้ — ที่ที่บอกว่าพังคือที่ที่ควรแก้ได้
    var onKeyProblem: (() -> Void)?

    private static let width: CGFloat = 260
    private static let inset: CGFloat = 14

    /// ชื่อแอปไปก่อน — ชื่อ org มาพร้อมการ์ดโควตาในใบถัดไป
    private let heading = NSTextField(labelWithString: "tamaclaude")
    private let gear = NSButton()
    /// การ์ดสองใบ — ใบเดิมสองใบตลอดอายุแผง เปลี่ยนแต่เนื้อใน การสร้างใหม่ทุกวินาที
    /// คือการทิ้ง view ทุกวินาทีเพื่อผลลัพธ์หน้าตาเดียวกัน
    private let sessionCard = QuotaCardView()
    private let weeklyCard = QuotaCardView()
    private let cards = NSStackView()
    private let boardLabel = NSTextField(labelWithString: "")
    /// สองบรรทัดที่พูดคนละเรื่อง: ท่อพัง (กดได้) กับ ค่าที่เห็นอยู่เก่าแค่ไหน
    private let keyButton = NSButton()
    private let ageLabel = NSTextField(labelWithString: "")
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

        cards.setViews([sessionCard, weeklyCard], in: .top)
        cards.orientation = .vertical
        cards.spacing = 10
        cards.alignment = .leading
        // ซ่อนไว้จนกว่าจะมีค่าจริง — stack ที่ว่างยังกินระยะห่างของ stack ที่ครอบมันอยู่
        // และการ์ดเปล่าสองใบอ่านได้ว่าอุปกรณ์พัง ทั้งที่ยังไม่เคยมีตัวเลขมาถึง
        cards.isHidden = true

        boardLabel.font = .systemFont(ofSize: 12)
        boardLabel.textColor = .secondaryLabelColor

        sessions.orientation = .vertical
        sessions.spacing = 2
        sessions.alignment = .leading

        keyButton.isBordered = false
        keyButton.target = self
        keyButton.action = #selector(keyProblemClicked)
        keyButton.contentTintColor = .systemOrange
        keyButton.font = .systemFont(ofSize: 12)
        keyButton.alignment = .left
        keyButton.isHidden = true

        ageLabel.font = .systemFont(ofSize: 12)
        ageLabel.textColor = .secondaryLabelColor

        // อายุของค่าอยู่ใต้การ์ด ไม่ใช่ท้ายแผง — มันเป็นคำอธิบายของตัวเลขที่อยู่เหนือมัน
        // ("เลขนี้ค้างหรือเปล่า") ไม่ใช่สถานะของแอปแบบเดียวกับบรรทัดบอร์ดหรือรายการ session
        let body = NSStackView(views: [cards, ageLabel])
        body.orientation = .vertical
        body.spacing = 8
        body.alignment = .leading

        let footer = NSStackView(views: [keyButton, boardLabel, sessions])
        footer.orientation = .vertical
        footer.spacing = 4
        footer.alignment = .leading

        let stack = NSStackView(views: [header, body, separator(), footer])
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
            body.widthAnchor.constraint(equalTo: stack.widthAnchor),
            cards.widthAnchor.constraint(equalTo: body.widthAnchor),
            sessionCard.widthAnchor.constraint(equalTo: cards.widthAnchor),
            weeklyCard.widthAnchor.constraint(equalTo: cards.widthAnchor),
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

    @objc private func keyProblemClicked() {
        onKeyProblem?()
    }

    /// บรรทัดท่อพังโผล่เฉพาะตอนพัง ส่วนบรรทัดอายุของค่ามีตลอด — ค่าที่ไม่มีก็เป็นอายุแบบหนึ่ง
    ///
    /// `detail` คือสิ่งที่ตัวยิงพูดล่าสุด (`HTTP 503`, บรรทัดสรุป) อยู่ใน tooltip เพราะ
    /// เป็นคำตอบของคำถามที่นานๆ ถามที ("ทำไมค่าถึงเก่า") ไม่ใช่ของที่ต้องเห็นตลอดเวลา
    func showQuota(
        problem: String?, age: String, cards quota: [QuotaCard]?, detail: String? = nil
    ) {
        keyButton.isHidden = problem == nil
        keyButton.title = problem ?? ""
        ageLabel.stringValue = age
        ageLabel.toolTip = detail

        // `nil` = ไม่รู้อะไรเลยทั้งสองหน้าต่าง ซึ่งไม่ใช่ 0% สองใบ — ซ่อนทั้งช่อง
        // แล้วเหลือแต่บรรทัดอายุที่พูดว่ายังไม่เคยมีตัวเลข
        cards.isHidden = quota == nil
        guard let quota else { return }
        // การ์ดมาเป็นคู่เสมอจาก `QuotaCard.cards` — ใบที่หายไปแปลว่าสัญญาเปลี่ยน ไม่ใช่ค่าหาย
        if let session = quota.first { sessionCard.show(session) }
        if quota.count > 1 { weeklyCard.show(quota[1]) }
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
