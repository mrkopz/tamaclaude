import AppKit
import TamaCore

/// หน้าตั้งค่าเต็มรูป — ที่เดียวของทุกสวิตช์ที่เคยอยู่หลังปุ่มเฟือง
///
/// เมนูเฟืองรับหน้า WiFi ไม่ไหว: รายชื่อเครือข่ายยาวไม่แน่นอน มีช่องรหัสผ่านที่ต้องพิมพ์
/// และมีสถานะที่เปลี่ยนเองระหว่างที่ผู้ใช้มองอยู่ ทั้งสามอย่างเป็นสิ่งที่ `NSMenu` ทำไม่ได้
/// (เมนูปิดตัวเองทันทีที่คลิก และไม่มีที่ให้ข้อความสถานะยาวๆ)
///
/// controller ตัวนี้ไม่รู้จัก BLE, ไฟล์ หรือ UserDefaults เลย — ทุกอย่างเข้าออกผ่าน closure
/// ที่ `MenuBarApp` ผูกให้ เพื่อให้ที่เก็บสถานะจริงยังมีที่เดียวเหมือนเดิม
final class PreferencesWindowController: NSWindowController {
    // --- ทางออกไปหา MenuBarApp ---------------------------------------------
    var onSelectBoard: ((UUID?) -> Void)?
    var onBrightness: ((Int) -> Void)?
    var onInterval: ((PollInterval) -> Void)?
    var onSetSessionKey: (() -> Void)?
    var onInstallHooks: (() -> Void)?
    var onToggleStatusline: (() -> Void)?
    var onToggleLogin: (() -> Void)?
    var onToggleAutoStart: (() -> Void)?
    var onOpenLog: (() -> Void)?
    var onOpenProject: (() -> Void)?

    var onScan: (() -> Void)?
    var onJoin: ((String, String) -> Void)?
    var onForget: ((String) -> Void)?
    /// ที่อยู่บอร์ดที่ผู้ใช้กรอกเอง — สตริงว่างคือกลับไปให้แอปหาเอง
    var onBoardHost: ((String) -> Void)?
    /// ค่าตั้งของหน้าอากาศเปลี่ยน — หน้าต่างไม่รู้จัก UserDefaults เหมือนทุกอย่างที่นี่
    var onWeather: ((WeatherSettings) -> Void)?
    /// พฤติกรรมของจอเปลี่ยน (หน้าไหนเปิด ลำดับ รอบหมุน) — ทางเดียวกับทุกอย่างที่นี่
    var onPages: ((PageSettings) -> Void)?
    /// watchlist ของหน้าคริปโตเปลี่ยน — ทั้งก้อนเสมอ ไม่ใช่ "เพิ่มตัวนี้" ทีละคำสั่ง
    var onCrypto: ((CryptoSettings) -> Void)?
    /// ปฏิทินที่ผู้ใช้ติ๊กให้ขึ้นจอเปลี่ยน — ทั้งก้อนเหมือน watchlist
    var onCalendar: ((CalendarSettings) -> Void)?
    /// ผู้ใช้กดขอสิทธิ์ปฏิทิน — กล่องของระบบเด้งจากฝั่ง `MenuBarApp` ไม่ใช่จากที่นี่
    var onCalendarAccess: (() -> Void)?

    // --- General ------------------------------------------------------------
    private let boardPopup = NSPopUpButton()
    private let brightness = NSSlider(value: 100, minValue: 5, maxValue: 100, target: nil,
                                      action: nil)
    private let intervalPopup = NSPopUpButton()
    private let statuslineBox = NSButton(checkboxWithTitle: "Read quota from the statusline",
                                         target: nil, action: nil)
    private let autoStartBox = NSButton(checkboxWithTitle: "Auto-start a session when idle",
                                        target: nil, action: nil)
    private let loginBox = NSButton(checkboxWithTitle: "Launch at login", target: nil,
                                    action: nil)
    private let keyLabel = NSTextField(labelWithString: "")

    // --- Pages --------------------------------------------------------------
    /// รายการหน้าถูกสร้างใหม่ทั้งแถบทุกครั้งที่ค่าเปลี่ยน — ไม่กี่แถวและลำดับก็ขยับได้
    /// การมี view ต่อหน้าที่ต้องคอยย้ายที่เองแลกไม่คุ้มกับความซับซ้อนที่ตามมา
    private let pageList = NSStackView()
    private let rotationField = NSTextField()
    private let holdField = NSTextField()
    private let jumpBox = NSButton(checkboxWithTitle: "Jump to the mascot when it needs a hand",
                                   target: nil, action: nil)
    /// ค่าที่หน้าต่างกำลังแสดงอยู่ — ปุ่มลูกศรกับติ๊กถูกแก้ *ของก้อนนี้* แล้วส่งออกทั้งก้อน
    private var pages = PageSettings()
    private let placeField = NSTextField()
    private let unitPopup = NSPopUpButton()
    private let weatherStatus = NSTextField(labelWithString: "")

    // --- Crypto --------------------------------------------------------------
    /// watchlist ได้แท็บของตัวเอง ไม่ได้ต่อท้ายแท็บ Pages เหมือนเมืองของหน้าอากาศ —
    /// เหตุผลเดียวกับที่ Wi-Fi ต้องมีแท็บ: รายการที่ยาวไม่แน่นอนพร้อมปุ่มของแต่ละแถว
    /// ไม่มีที่ยืนใต้ของอื่นในหน้าต่างสูง 520 pt ส่วนหน้าอากาศมีแค่สองช่อง
    private let coinList = NSStackView()
    private let coinField = NSTextField()
    private let addButton = NSButton(title: "Add", target: nil, action: nil)
    private let cryptoStatus = NSTextField(labelWithString: "")
    /// หน้านี้เปิดอยู่ไหม — ปุ่มของทุกแถวถูกสร้างใหม่ตอน `rebuildCoinList` ซึ่งเกิดตอนที่
    /// ผู้เรียกยังไม่ได้บอกค่านี้เข้ามาก็ได้ จึงต้องจำไว้ ไม่ใช่ส่งผ่านเป็นพารามิเตอร์
    private var cryptoOn = true
    /// ค่าที่หน้าต่างกำลังแสดงอยู่ — ปุ่มทุกปุ่มแก้ของก้อนนี้แล้วส่งออกทั้งก้อน
    private var crypto = CryptoSettings()

    // --- Calendar ------------------------------------------------------------
    /// รายการปฏิทินเป็นติ๊ก ไม่ใช่ช่องพิมพ์: ผู้ใช้ไม่ได้ตั้งชื่อปฏิทินเอง เขาเลือกจากที่
    /// macOS sync มาให้ (ADR-0005) และชื่อที่พิมพ์ผิดจะกลายเป็นหน้าที่ว่างโดยไม่บอกอะไร
    private let calendarList = NSStackView()
    private let accessButton = NSButton(title: "Allow access", target: nil, action: nil)
    private let calendarStatus = NSTextField(labelWithString: "")
    /// id ของแต่ละแถวเรียงตามที่วาด — ปุ่มติ๊กพก `tag` เป็นตัวเลขได้อย่างเดียว
    private var calendarIDs: [String] = []
    private var calendarOn = true
    private var calendars = CalendarSettings()

    // --- Wi-Fi --------------------------------------------------------------
    private let statusLabel = NSTextField(labelWithString: "")
    private let ipLabel = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private let spinner = NSProgressIndicator()
    private let password = NSSecureTextField()
    private let joinButton = NSButton(title: "Connect", target: nil, action: nil)
    private let forgetButton = NSButton(title: "Forget", target: nil, action: nil)
    private let hostField = NSTextField()
    private let routeLabel = NSTextField(labelWithString: "")

    private var boards: [Board] = []
    private var selectedBoard: UUID?
    private var list = NetworkList()
    private var status: WiFiStatus?
    private var linked = false
    private var route: LanRoute = .none

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "TamaClaude Settings"
        super.init(window: window)
        window.contentView = buildTabs()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        // ปกติแอปนี้ไม่มีหน้าต่างเลย (`.accessory`) การเปิดหน้าตั้งค่าจึงต้องดึงแอปขึ้นมา
        // หน้าสุดเอง ไม่งั้นหน้าต่างโผล่หลังหน้าต่างของแอปอื่นแล้วดูเหมือนกดปุ่มไม่ติด
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        onScan?()
    }

    // --- โครงหน้าต่าง -------------------------------------------------------
    private func buildTabs() -> NSView {
        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false

        let general = NSTabViewItem(identifier: "general")
        general.label = "General"
        general.view = pad(buildGeneral())
        tabs.addTabViewItem(general)

        let pagesTab = NSTabViewItem(identifier: "pages")
        pagesTab.label = "Pages"
        pagesTab.view = pad(buildPages())
        tabs.addTabViewItem(pagesTab)

        let cryptoTab = NSTabViewItem(identifier: "crypto")
        cryptoTab.label = "Crypto"
        cryptoTab.view = pad(buildCrypto())
        tabs.addTabViewItem(cryptoTab)

        let calendarTab = NSTabViewItem(identifier: "calendar")
        calendarTab.label = "Calendar"
        calendarTab.view = pad(buildCalendar())
        tabs.addTabViewItem(calendarTab)

        let wifi = NSTabViewItem(identifier: "wifi")
        wifi.label = "Wi-Fi"
        wifi.view = pad(buildWiFi())
        tabs.addTabViewItem(wifi)

        let container = NSView()
        container.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            tabs.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            tabs.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            tabs.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
        return container
    }

    private func pad(_ view: NSView) -> NSView {
        let host = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -16),
            view.topAnchor.constraint(equalTo: host.topAnchor, constant: 16),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -16),
        ])
        return host
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.spacing = 8
        label.widthAnchor.constraint(equalToConstant: 130).isActive = true
        return stack
    }

    private func buildGeneral() -> NSView {
        boardPopup.target = self
        boardPopup.action = #selector(boardChanged)

        brightness.target = self
        brightness.action = #selector(brightnessChanged)
        brightness.isContinuous = false  // ส่งตอนปล่อยเมาส์ ไม่ใช่ทุกพิกเซลที่ลาก

        intervalPopup.target = self
        intervalPopup.action = #selector(intervalChanged)
        for interval in PollInterval.allCases {
            intervalPopup.addItem(withTitle: interval.title)
            intervalPopup.lastItem?.representedObject = interval.rawValue
        }

        let key = NSButton(title: "Set session key…", target: self,
                           action: #selector(setSessionKey))
        let hooks = NSButton(title: "Install hooks in settings.json", target: self,
                             action: #selector(installHooks))
        hooks.toolTip = "~/.claude/settings.json"
        let log = NSButton(title: "Open log", target: self, action: #selector(openLog))
        // ปลายทางอยู่ในชื่อปุ่ม ไม่ใช่คำว่า "GitHub" — แอปนี้ขอ credential เต็มบัญชี
        // ลิงก์ที่ซ่อนปลายทางไว้หลังคำสวยๆ เป็นท่าเดียวกับที่ผู้ใช้ควรระวัง
        let project = NSButton(title: PanelText.projectLink, target: self,
                               action: #selector(openProject))
        for button in [key, hooks, log, project] { button.bezelStyle = .rounded }

        for box in [statuslineBox, autoStartBox, loginBox] { box.target = self }
        statuslineBox.action = #selector(statuslineToggled)
        autoStartBox.action = #selector(autoStartToggled)
        loginBox.action = #selector(loginToggled)

        // ช่องกรอก key เป็นแบบปิดบังตัวอักษรและไม่เคยถูกเติมกลับ บรรทัดนี้จึงเป็น
        // ทางเดียวที่ผู้ใช้รู้ว่ากด Save แล้วเข้าไหม
        keyLabel.font = .systemFont(ofSize: 11)
        keyLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            row("Board", boardPopup),
            row("Brightness", brightness),
            row("Refresh quota", intervalPopup),
            row("Session key", key),
            row("", keyLabel),
            separator(),
            row("", statuslineBox),
            row("", autoStartBox),
            row("", loginBox),
            separator(),
            row("", hooks),
            row("", log),
            row("", project),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        return stack
    }

    /// หน้าบนจอ — ทุกค่าที่นี่ไปจบที่ `UserDefaults` และแอปเป็นบรรณาธิการเดียว
    ///
    /// เมืองเป็นชื่อที่พิมพ์เอง ไม่ใช่ CoreLocation: เลี่ยง TCC อีกใบ และของตั้งโต๊ะไม่ได้
    /// ย้ายที่ · ปิดหน้าไหนแล้วบอร์ดถูกสั่งให้ลืมมันจริงๆ ไม่ใช่แค่หยุดส่งของใหม่
    private func buildPages() -> NSView {
        pageList.orientation = .vertical
        pageList.alignment = .leading
        pageList.spacing = 4

        for field in [rotationField, holdField] {
            field.target = self
            field.action = #selector(pagesChanged)
            field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 60).isActive = true
            let numbers = NumberFormatter()
            numbers.allowsFloats = false
            field.formatter = numbers
        }
        jumpBox.target = self
        jumpBox.action = #selector(pagesChanged)

        placeField.placeholderString = "City (e.g. Bangkok)"
        placeField.target = self
        placeField.action = #selector(weatherChanged)

        unitPopup.target = self
        unitPopup.action = #selector(weatherChanged)
        for unit in TempUnit.allCases {
            unitPopup.addItem(withTitle: unit.title)
            unitPopup.lastItem?.representedObject = unit.rawValue
        }

        weatherStatus.font = .systemFont(ofSize: 11)
        weatherStatus.textColor = .secondaryLabelColor

        let hint = NSTextField(wrappingLabelWithString:
            "The board keeps its own clock, so the screen keeps turning while this Mac sleeps. "
            + "Weather figures come from Open-Meteo, fetched here every 15 minutes — the board "
            + "never goes online itself, and the page always says how old the figures are.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            pageList,
            row("Turn every", measure(rotationField, "seconds")),
            row("Hold a swipe for", measure(holdField, "minutes")),
            row("", jumpBox),
            separator(),
            row("City", placeField),
            row("Units", unitPopup),
            row("", weatherStatus),
            separator(),
            hint,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        placeField.widthAnchor.constraint(equalToConstant: 220).isActive = true
        hint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// ช่องตัวเลขกับหน่วยของมัน — หน่วยอยู่ *หลัง* ช่อง ไม่ใช่ในป้ายซ้าย ผู้ใช้ที่พิมพ์ทับ
    /// ต้องเห็นว่ากำลังพิมพ์วินาทีหรือนาที ตอนที่สายตาอยู่ที่ช่อง ไม่ใช่ตอนอ่านหัวแถว
    private func measure(_ field: NSTextField, _ unit: String) -> NSView {
        let label = NSTextField(labelWithString: unit)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [field, label])
        stack.orientation = .horizontal
        stack.spacing = 6
        return stack
    }

    /// วาดรายการหน้าใหม่ทั้งแถบจากค่าที่ถืออยู่
    ///
    /// หน้ามาสคอตมีติ๊กที่กดไม่ได้ ไม่ใช่ไม่มีติ๊ก — แถวที่ไม่มีติ๊กอ่านว่า "ยังไม่รองรับ"
    /// ส่วนติ๊กที่ติดค้างและกดไม่ลงบอกตรงๆ ว่ามันปิดไม่ได้
    private func rebuildPageList() {
        for view in pageList.arrangedSubviews { view.removeFromSuperview() }
        for (index, kind) in pages.order.enumerated() {
            let box = NSButton(checkboxWithTitle: kind.title, target: self,
                               action: #selector(pageToggled))
            box.state = pages.isOn(kind) ? .on : .off
            box.tag = kind.rawValue
            box.isEnabled = kind != .mascot
            box.widthAnchor.constraint(equalToConstant: 140).isActive = true

            let up = NSButton(title: "▲", target: self, action: #selector(movePageUp))
            let down = NSButton(title: "▼", target: self, action: #selector(movePageDown))
            for button in [up, down] {
                button.bezelStyle = .rounded
                button.tag = kind.rawValue
                button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            }
            up.isEnabled = index > 0
            down.isEnabled = index < pages.order.count - 1

            let row = NSStackView(views: [box, up, down])
            row.orientation = .horizontal
            row.spacing = 4
            pageList.addArrangedSubview(row)
        }
    }

    /// watchlist ของหน้าคริปโต — เพิ่ม ลบ จัดลำดับ และเพดานห้าตัวที่กดผ่านไม่ได้
    ///
    /// ผู้ใช้พิมพ์ชื่อที่เขาเรียกมันเอง ("btc", "bitcoin") ไม่ใช่ id ของบริการ การแปลงเป็น id
    /// เกิดครั้งเดียวใน `CryptoService` แล้วถูกจำไว้ — คนซื้อคริปโตไม่ได้จำ slug ของ CoinGecko
    private func buildCrypto() -> NSView {
        coinList.orientation = .vertical
        coinList.alignment = .leading
        coinList.spacing = 4

        coinField.placeholderString = "Coin (e.g. btc)"
        coinField.target = self
        coinField.action = #selector(addCoin)
        coinField.widthAnchor.constraint(equalToConstant: 180).isActive = true

        addButton.target = self
        addButton.action = #selector(addCoin)
        addButton.bezelStyle = .rounded

        cryptoStatus.font = .systemFont(ofSize: 11)
        cryptoStatus.textColor = .secondaryLabelColor

        let entry = NSStackView(views: [coinField, addButton])
        entry.orientation = .horizontal
        entry.spacing = 6

        let hint = NSTextField(wrappingLabelWithString:
            "Prices come from CoinGecko, fetched here every 60 seconds around the clock — the "
            + "crypto market never closes. Five coins at most: that is what keeps one request "
            + "per round and one frame per page. Gains and losses are told apart by the arrow "
            + "as well as the colour.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            coinList,
            entry,
            cryptoStatus,
            separator(),
            hint,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        hint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// วาดรายการเหรียญใหม่ทั้งแถบจากค่าที่ถืออยู่ — เหตุผลเดียวกับรายการหน้า:
    /// ไม่กี่แถว ลำดับขยับได้ และ view ที่ต้องคอยย้ายที่เองแลกไม่คุ้ม
    private func rebuildCoinList() {
        for view in coinList.arrangedSubviews { view.removeFromSuperview() }
        for (index, coin) in crypto.coins.enumerated() {
            let label = NSTextField(labelWithString: coin)
            label.widthAnchor.constraint(equalToConstant: 140).isActive = true

            let up = NSButton(title: "▲", target: self, action: #selector(moveCoinUp))
            let down = NSButton(title: "▼", target: self, action: #selector(moveCoinDown))
            let remove = NSButton(title: "Remove", target: self, action: #selector(removeCoin))
            for button in [up, down, remove] {
                button.bezelStyle = .rounded
                button.tag = index
                button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            }
            up.isEnabled = cryptoOn && index > 0
            down.isEnabled = cryptoOn && index < crypto.coins.count - 1
            remove.isEnabled = cryptoOn
            label.textColor = cryptoOn ? .labelColor : .disabledControlTextColor

            let row = NSStackView(views: [label, up, down, remove])
            row.orientation = .horizontal
            row.spacing = 4
            coinList.addArrangedSubview(row)
        }
    }

    /// ปฏิทินใบไหนได้ขึ้นจอบ้าง — ติ๊กทีละใบ พร้อมปุ่มขอสิทธิ์ตอนที่ยังไม่มี
    ///
    /// ไม่มีปุ่ม "เลือกทั้งหมด": จอนี้วางให้คนอื่นเห็นได้ การเปิดทุกใบด้วยการกดครั้งเดียว
    /// คือการเผลอเอาปฏิทินหมอกับปฏิทินครอบครัวขึ้นจอพร้อมกันโดยไม่ได้อ่านชื่อสักใบ
    private func buildCalendar() -> NSView {
        calendarList.orientation = .vertical
        calendarList.alignment = .leading
        calendarList.spacing = 4

        accessButton.target = self
        accessButton.action = #selector(askCalendarAccess)
        accessButton.bezelStyle = .rounded

        calendarStatus.font = .systemFont(ofSize: 11)
        calendarStatus.textColor = .secondaryLabelColor

        let hint = NSTextField(wrappingLabelWithString:
            "Appointments are read from the calendars macOS already syncs, so TamaClaude never "
            + "holds a calendar password of its own — add the account in System Settings and "
            + "tick it here. The page shows the next four appointments within seven days, "
            + "read-only: nothing on the desk can change an appointment.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            calendarList,
            accessButton,
            calendarStatus,
            separator(),
            hint,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        hint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// วาดรายการปฏิทินใหม่ทั้งแถบ — เหตุผลเดียวกับรายการหน้าและ watchlist
    private func rebuildCalendarList(_ available: [CalendarInfo]) {
        for view in calendarList.arrangedSubviews { view.removeFromSuperview() }
        calendarIDs = available.map(\.id)
        for (index, info) in available.enumerated() {
            // ชื่อบัญชีต่อท้ายเสมอ — ปฏิทินชื่อ "Calendar" สองใบจากคนละบัญชีแยกกันไม่ออก
            // ถ้าไม่บอกว่ามาจากไหน แล้วผู้ใช้จะติ๊กใบผิดขึ้นจอที่คนอื่นมองเห็น
            let title = info.source.isEmpty ? info.title : "\(info.title)  (\(info.source))"
            let box = NSButton(
                checkboxWithTitle: title, target: self, action: #selector(calendarTicked))
            box.tag = index
            box.state = calendars.isOn(info.id) ? .on : .off
            box.isEnabled = calendarOn
            calendarList.addArrangedSubview(box)
        }
    }

    @objc private func calendarTicked(_ sender: NSButton) {
        guard calendarIDs.indices.contains(sender.tag) else { return }
        calendars.setOn(calendarIDs[sender.tag], sender.state == .on)
        onCalendar?(calendars)
    }

    @objc private func askCalendarAccess() { onCalendarAccess?() }

    private func buildWiFi() -> NSView {
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        ipLabel.font = .systemFont(ofSize: 11)
        ipLabel.textColor = .secondaryLabelColor

        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ssid")))
        table.headerView = nil
        table.rowHeight = 20
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(join)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let rescan = NSButton(title: "Rescan", target: self, action: #selector(rescan))
        rescan.bezelStyle = .rounded
        joinButton.target = self
        joinButton.action = #selector(join)
        joinButton.bezelStyle = .rounded
        joinButton.keyEquivalent = "\r"
        forgetButton.target = self
        forgetButton.action = #selector(forget)
        forgetButton.bezelStyle = .rounded

        password.placeholderString = "Network password"

        let buttons = NSStackView(views: [rescan, spinner, NSView(), forgetButton, joinButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        // เขียนไว้ตรงนี้ ไม่ใช่ในกล่องข้อผิดพลาดตอนล้ม — เน็ตที่เปิด client isolation
        // (โรงแรม ออฟฟิศ) ให้บอร์ดขึ้นเน็ตได้ตามปกติแล้วเงียบทีหลัง ผู้ใช้ควรรู้ล่วงหน้า
        let hint = NSTextField(wrappingLabelWithString:
            "The board only talks to this Mac over your LAN — it never contacts claude.ai "
            + "itself, so your session key stays here. Networks that isolate clients from "
            + "each other will connect but stay unreachable.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        routeLabel.font = .systemFont(ofSize: 11)
        routeLabel.textColor = .secondaryLabelColor

        // ช่องกรอกที่อยู่เอง: mDNS เป็นสิ่งแรกที่หายไปเมื่อมี VLAN ของแขก, subnet ที่สอง
        // หรือเราเตอร์ที่กรอง multicast — และตอนนั้น BLE ก็ตายไปแล้ว ไม่มีทางอื่นเหลือ
        hostField.placeholderString = "Board address (leave empty to find it automatically)"
        hostField.target = self
        hostField.action = #selector(hostChanged)

        let stack = NSStackView(views: [
            statusLabel, ipLabel, scroll, password, buttons, separator(), routeLabel,
            hostField, hint,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        for view in [scroll, password, buttons, hostField, hint] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        return line
    }

    // --- ให้ MenuBarApp ป้อนสถานะเข้ามา ------------------------------------
    func showBoards(_ list: [Board], selected: UUID?) {
        boards = list
        selectedBoard = selected
        boardPopup.removeAllItems()
        boardPopup.addItem(withTitle: "Any board")
        boardPopup.lastItem?.representedObject = nil
        for board in list {
            boardPopup.addItem(withTitle: board.name + (board.isCurrent ? " ✓" : ""))
            boardPopup.lastItem?.representedObject = board.id.uuidString
        }
        let index = list.firstIndex { $0.id == selected }
        boardPopup.selectItem(at: index.map { $0 + 1 } ?? 0)
    }

    func showBrightness(_ value: Int) { brightness.integerValue = value }

    func showInterval(_ interval: PollInterval) {
        let index = PollInterval.allCases.firstIndex(of: interval) ?? 0
        intervalPopup.selectItem(at: index)
    }

    func showToggles(statusline: Bool, autoStart: Bool, login: Bool) {
        statuslineBox.state = statusline ? .on : .off
        autoStartBox.state = autoStart ? .on : .off
        loginBox.state = login ? .on : .off
    }

    func showBoardHost(_ host: String) { hostField.stringValue = host }

    /// นาทีเข้า วินาทีออก — ค่าบนสายเป็นวินาทีเสมอ ส่วนช่องนี้ถามเป็นนาทีเพราะ
    /// ค่าตั้งต้นคือ 5 นาที และไม่มีใครอยากอ่านหรือพิมพ์เลข 300
    private static let holdStep = 60

    func showPages(_ settings: PageSettings) {
        pages = settings
        rebuildPageList()
        rotationField.integerValue = settings.rotation
        holdField.integerValue = settings.hold / Self.holdStep
        jumpBox.state = settings.attentionJump ? .on : .off
    }

    func showWeather(_ settings: WeatherSettings, status: String?, supported: Bool, on: Bool) {
        placeField.stringValue = settings.place
        unitPopup.selectItem(at: TempUnit.allCases.firstIndex(of: settings.unit) ?? 0)
        placeField.isEnabled = on
        unitPopup.isEnabled = on

        // เหตุผลที่หน้านี้ยังไม่ขึ้นจอมีได้สามอย่าง และผู้ใช้แก้ได้คนละแบบ: firmware เก่า
        // (ต้องแฟลช) · ยังไม่พิมพ์ชื่อเมือง (พิมพ์) · ดึงไม่สำเร็จ (รอ หรือแก้ชื่อเมือง)
        if !supported {
            weatherStatus.stringValue =
                "The board's firmware does not know this page yet — flash it to use it."
        } else if let status {
            weatherStatus.stringValue = status
        } else if on && !settings.isUsable {
            weatherStatus.stringValue = "Type a city to start."
        } else {
            weatherStatus.stringValue = ""
        }
    }

    func showCrypto(_ settings: CryptoSettings, status: String?, supported: Bool, on: Bool) {
        crypto = settings
        cryptoOn = on
        rebuildCoinList()
        // ปิดหน้านี้แล้วยังแก้ watchlist ได้ครึ่งเดียวคือหน้าต่างที่บอกคนละเรื่องกับตัวเอง —
        // ปุ่มทุกปุ่มดับพร้อมกัน เหมือนช่องเมืองกับหน่วยของหน้าอากาศ
        let room = settings.coins.count < CryptoSettings.maxCoins
        coinField.isEnabled = on && room
        addButton.isEnabled = on && room

        // เหตุผลที่หน้านี้ยังไม่ขึ้นจอมีได้สี่อย่าง และผู้ใช้แก้ได้คนละแบบ: firmware เก่า
        // (ต้องแฟลช) · ยังไม่ใส่เหรียญ (ใส่) · เต็มเพดานแล้ว (ลบก่อน) · ดึงไม่สำเร็จ
        if !supported {
            cryptoStatus.stringValue =
                "The board's firmware does not know this page yet — flash it to use it."
        } else if let status {
            cryptoStatus.stringValue = status
        } else if on && !settings.isUsable {
            cryptoStatus.stringValue = "Add a coin to start."
        } else if settings.coins.count >= CryptoSettings.maxCoins {
            cryptoStatus.stringValue = "Five coins is the most this page shows."
        } else {
            cryptoStatus.stringValue = ""
        }
    }

    func showCalendar(
        _ settings: CalendarSettings, available: [CalendarInfo], access: CalendarAccess,
        status: String?, supported: Bool, on: Bool
    ) {
        calendars = settings
        calendarOn = on
        rebuildCalendarList(available)

        // ปุ่มขอสิทธิ์มีความหมายครั้งเดียวในชีวิตของแอป — หลังผู้ใช้ปฏิเสธไปแล้ว macOS
        // จะไม่ถามซ้ำ กดอีกกี่ครั้งก็ไม่มีอะไรเกิดขึ้น ปุ่มจึงต้องดับและประโยคต้องเปลี่ยน
        accessButton.isHidden = access == .granted
        accessButton.isEnabled = on && access == .notDetermined

        // ประโยคของแต่ละสภาพมาจาก `CalendarService` ที่เดียว — หน้าต่างเติมเฉพาะสิ่งที่
        // มันรู้อยู่คนเดียว: firmware ที่ยังไม่รู้จักหน้านี้ (ต้องแฟลช) และทางออกของสิทธิ์
        // ที่ถูกปฏิเสธ ซึ่งยาวเกินกว่าจะขึ้นจอ 320px ได้
        if !supported {
            calendarStatus.stringValue =
                "The board's firmware does not know this page yet — flash it to use it."
        } else if access == .denied {
            calendarStatus.stringValue =
                "Calendar access was refused. Turn TamaClaude on in System Settings > "
                + "Privacy & Security > Calendars."
        } else {
            calendarStatus.stringValue = status ?? ""
        }
    }

    func showKey(_ state: SessionKeyState) {
        keyLabel.stringValue = state.line
        keyLabel.textColor = state.isProblem ? .systemRed : .secondaryLabelColor
    }

    /// ทางที่ snapshot เดินอยู่จริง — คนละเรื่องกับ "บอร์ดต่อ WiFi แล้ว"
    ///
    /// บอร์ดที่ขึ้นเน็ตสำเร็จแต่ Mac หาไม่เจอ (client isolation, คนละ subnet) จะดูดีทุกอย่าง
    /// บนหน้านี้ทั้งที่ทางสำรองใช้ไม่ได้เลย บรรทัดนี้เป็นที่เดียวที่แยกสองอย่างนั้นออก
    func showRoute(_ route: LanRoute, detail: String?) {
        self.route = route
        routeLabel.stringValue = detail ?? PanelText.board(route: route)
    }

    func showLink(_ connected: Bool) {
        linked = connected
        if !connected { list.linkLost() }
        redraw()
    }

    func apply(_ event: BoardEvent) {
        list.apply(event)
        if case .wifi(let status) = event { self.status = status }
        redraw()
    }

    func beginScan() {
        list.beginScan()
        redraw()
    }

    private func redraw() {
        table.reloadData()
        if list.scanning { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }

        guard linked else {
            statusLabel.stringValue = "No board connected over Bluetooth"
            ipLabel.stringValue = "Wi-Fi can only be set up while the board is in range."
            return
        }
        guard let status else {
            statusLabel.stringValue = "Asking the board…"
            ipLabel.stringValue = ""
            return
        }
        switch status.state {
        case .connected:
            statusLabel.stringValue = "Connected to \(status.ssid)"
            ipLabel.stringValue = "Board address \(status.ip)"
        case .connecting:
            statusLabel.stringValue = "Connecting to \(status.ssid)…"
            ipLabel.stringValue = ""
        case .failed:
            statusLabel.stringValue = "\(status.ssid): \(status.error ?? "failed")"
            // ไม่ต้องบอกให้กดลองใหม่ — firmware ลองเองเรื่อยๆ อยู่แล้ว
            ipLabel.stringValue = "The board keeps retrying on its own."
        case .off:
            statusLabel.stringValue = "No network saved yet"
            ipLabel.stringValue = ""
        }
    }

    private var selectedSSID: String? {
        let row = table.selectedRow
        guard row >= 0, row < list.found.count else { return nil }
        return list.found[row].ssid
    }

    // --- การกระทำ ----------------------------------------------------------
    @objc private func boardChanged() {
        let raw = boardPopup.selectedItem?.representedObject as? String
        onSelectBoard?(raw.flatMap(UUID.init(uuidString:)))
    }

    @objc private func brightnessChanged() { onBrightness?(brightness.integerValue) }

    @objc private func intervalChanged() {
        let raw = intervalPopup.selectedItem?.representedObject as? Int
        onInterval?(PollInterval.stored(raw))
    }

    @objc private func weatherChanged() {
        let raw = unitPopup.selectedItem?.representedObject as? String
        onWeather?(
            WeatherSettings(
                place: placeField.stringValue.trimmingCharacters(in: .whitespaces),
                unit: TempUnit(rawValue: raw ?? "") ?? .celsius))
    }

    /// รอบหมุนกับ hold ถูกอ่านจากช่องทุกครั้งที่มีอะไรในแท็บนี้เปลี่ยน — ผู้ใช้ที่พิมพ์เลข
    /// แล้วกดติ๊กต่อโดยไม่กด Enter ต้องได้ทั้งสองอย่าง ไม่ใช่ได้ติ๊กแล้วเลขหาย
    @objc private func pagesChanged() {
        pages.rotation = rotationField.integerValue
        pages.hold = holdField.integerValue * Self.holdStep
        pages.attentionJump = jumpBox.state == .on
        emitPages()
    }

    @objc private func pageToggled(_ sender: NSButton) {
        guard let kind = PageKind(rawValue: sender.tag) else { return }
        pages.setOn(kind, sender.state == .on)
        pagesChanged()
    }

    // ชื่อ `pageUp`/`pageDown` ใช้ไม่ได้ — `NSResponder` มีเมธอดชื่อนั้นอยู่แล้ว
    @objc private func movePageUp(_ sender: NSButton) { movePage(sender, by: -1) }
    @objc private func movePageDown(_ sender: NSButton) { movePage(sender, by: 1) }

    private func movePage(_ sender: NSButton, by step: Int) {
        guard let kind = PageKind(rawValue: sender.tag) else { return }
        pages.move(kind, by: step)
        pagesChanged()
    }

    /// ค่าที่ส่งออกถูกบีบเข้าช่วงที่ยอมรับได้ระหว่างทาง — แสดงกลับเสมอ ไม่ใช่เฉพาะตอนเปิด
    /// หน้าต่าง ไม่งั้นช่องจะค้างเลข 9999 ที่ไม่มีใครใช้ทั้งที่จอหมุนตาม 600
    private func emitPages() {
        let settled = PageSettings(
            order: pages.order, off: pages.off, rotation: pages.rotation, hold: pages.hold,
            attentionJump: pages.attentionJump)
        onPages?(settled)
        showPages(settled)
    }

    @objc private func addCoin() {
        // ช่องถูกล้างเฉพาะตอนที่เหรียญเข้าไปจริง — คำที่ถูกปฏิเสธ (ซ้ำ หรือเต็มแล้ว)
        // ต้องยังอยู่ให้ผู้ใช้เห็นว่าเขาพิมพ์อะไรไป พร้อมเหตุผลในบรรทัดสถานะ
        guard crypto.add(coinField.stringValue) else { return }
        coinField.stringValue = ""
        emitCrypto()
    }

    @objc private func removeCoin(_ sender: NSButton) {
        crypto.remove(sender.tag)
        emitCrypto()
    }

    @objc private func moveCoinUp(_ sender: NSButton) { moveCoin(sender, by: -1) }
    @objc private func moveCoinDown(_ sender: NSButton) { moveCoin(sender, by: 1) }

    private func moveCoin(_ sender: NSButton, by step: Int) {
        crypto.move(sender.tag, by: step)
        emitCrypto()
    }

    /// วาดรายการใหม่ทันทีแล้วค่อยบอกออกไป — สถานะที่เหลือ (firmware รู้จักหน้านี้ไหม
    /// หน้านี้เปิดอยู่ไหม ดึงข้อมูลสำเร็จไหม) ไม่ใช่ของหน้าต่างนี้ `MenuBarApp` จะป้อน
    /// กลับมาเองผ่าน `showCrypto` เหมือนทุกอย่างที่นี่
    private func emitCrypto() {
        rebuildCoinList()
        onCrypto?(crypto)
    }

    @objc private func setSessionKey() { onSetSessionKey?() }
    @objc private func installHooks() { onInstallHooks?() }
    @objc private func statuslineToggled() { onToggleStatusline?() }
    @objc private func autoStartToggled() { onToggleAutoStart?() }
    @objc private func loginToggled() { onToggleLogin?() }
    @objc private func openLog() { onOpenLog?() }
    @objc private func openProject() { onOpenProject?() }

    @objc private func rescan() {
        beginScan()
        onScan?()
    }

    @objc private func join() {
        guard let ssid = selectedSSID else { return }
        onJoin?(ssid, password.stringValue)
        password.stringValue = ""
    }

    @objc private func hostChanged() {
        onBoardHost?(hostField.stringValue.trimmingCharacters(in: .whitespaces))
    }

    @objc private func forget() {
        guard let ssid = selectedSSID else { return }
        onForget?(ssid)
    }
}

extension PreferencesWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { list.found.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        let ap = list.found[row]
        // เครือข่ายที่บอร์ดจำไว้ต้องแยกออกจากที่เพิ่งเห็น ไม่งั้นผู้ใช้ไม่รู้ว่าต้องพิมพ์รหัส
        // ซ้ำไหม และปุ่ม Forget จะดูเหมือนใช้ได้กับทุกแถว
        var marks: [String] = []
        if list.saved.contains(ap.ssid) { marks.append("saved") }
        if ap.secured { marks.append("locked") }
        marks.append("\(ap.rssi) dBm")
        let text = "\(ap.ssid)   —   \(marks.joined(separator: ", "))"
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}
