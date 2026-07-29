import AppKit
import ServiceManagement
import TamaCore

/// เมนูบาร์ = daemon ที่มีหน้าตา
///
/// ไม่ได้สั่ง daemon อีกตัวจากระยะไกล แต่ *เป็น* daemon เอง (โปรเซสเดียว socket เดียว)
/// เพราะสิทธิ์ Bluetooth ผูกกับ .app ที่ถูกปล่อยผ่าน LaunchServices เท่านั้น
/// ถ้าแยกโปรเซสจะได้ daemon ที่ไม่มีสิทธิ์ต่อบอร์ด
final class MenuBarApp: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let ble = BLETransport()
    private var daemon: Daemon!

    /// จำบอร์ดที่ผู้ใช้เลือกไว้ข้ามการเปิดปิดแอป
    private static let preferredKey = "preferredBoard"
    /// รอบการยิงโควตา และ org ที่เลือก — จำข้ามการเปิดปิดแอปเหมือนบอร์ด
    private static let intervalKey = "quotaRefresh"
    private static let orgKey = "preferredOrg"
    /// สวิตช์เริ่ม session เอง — ปิดโดยปริยาย เพราะมันใช้โควตาของผู้ใช้จริง
    private static let autoStartKey = "autoStartSession"

    private var poller: UsagePoller!
    private var starter: SessionStarter!
    /// แถวโควตาชุดล่าสุดที่ daemon ประกาศออกมา — ตัวเดียวกับที่แบดจ์กิน
    private var usage: [UsageSnap]?

    private let popover = NSPopover()
    private let panel = PanelViewController()
    private lazy var gearMenu: NSMenu = buildMenu()
    /// ตัวดักคลิกนอกแอปตอน popover เปิด — มีอยู่ก็ต่อเมื่อ popover เปิดอยู่
    private var outsideClicks: Any?
    /// นาฬิกาของแผง — เดินเฉพาะตอนแผงเปิด ด้วยเหตุผลเดียวกับตัวดักคลิก
    private var panelTicks: Timer?

    private let boardItem = NSMenuItem(title: "Board", action: nil, keyEquivalent: "")
    private var boards: [Board] = []
    private let hooksItem = NSMenuItem(
        title: "Install hooks in ~/.claude/settings.json", action: #selector(installHooks),
        keyEquivalent: "")
    private let statuslineItem = NSMenuItem(
        title: "Show usage on the board", action: #selector(toggleStatusline), keyEquivalent: "")
    private let loginItem = NSMenuItem(
        title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
    private let keyItem = NSMenuItem(
        title: "Set session key…", action: #selector(setSessionKey), keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "Refresh quota", action: nil, keyEquivalent: "")
    private let autoStartItem = NSMenuItem(
        title: "Auto-start a session when idle", action: #selector(toggleAutoStart),
        keyEquivalent: "")
    private let brightness = NSSlider(value: 100, minValue: 5, maxValue: 100, target: nil,
                                      action: nil)

    /// รอบที่ปุ่ม refresh เป็นคนสั่ง — ต่างจากรอบของนาฬิกา
    ///
    /// การเย็นตัวเป็นวินัยของ *ปุ่ม* ไม่ใช่ของ poller: รอบอัตโนมัติที่เพิ่งจบไปเมื่อครู่
    /// ไม่ควรทำให้ปุ่มกดไม่ได้ ไม่งั้นที่ 60 วินาที ปุ่มจะตายหนึ่งในหกของเวลาทั้งหมด
    /// โดยไม่มีใครเข้าใจว่าทำไม
    private var manualRefresh = false
    private var refreshFinished: Date?

    /// ภาพที่วาดไปแล้ว — ไฮไลต์กับธีมของแถบเมนูเป็นส่วนหนึ่งของภาพ ไม่ใช่แค่ค่าโควตา
    ///
    /// ภาพตอนเตือนไม่ใช่ template จึงเลือกสีหมึกเองตั้งแต่ตอนวาด สลับ Light/Dark
    /// แล้วภาพเดิมจะค้างเป็นหมึกของธีมก่อนหน้า — ธีมอยู่ในกุญแจนี้ นาฬิกาวินาที
    /// จึงวาดใหม่ให้เองภายในหนึ่งวินาที โดยไม่ต้องมีใครไปดักฟัง appearance
    private struct Drawn: Equatable {
        var badge: MenuBadge?
        var highlighted: Bool
        var dark: Bool
    }
    private var lastDrawn: Drawn?
    private var panelIsOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Paths.ensureStateDir()
        Log.toFile = true

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        showBadge(nil)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        panel.onGear = { [weak self] button in self?.showGearMenu(from: button) }
        panel.onOrgs = { [weak self] button in self?.showOrgMenu(from: button) }
        panel.onRefresh = { [weak self] in self?.refreshQuota() }
        // บรรทัด "key หมดอายุ" กดได้เอง — ที่ที่บอกว่าพังคือที่ที่ควรแก้ได้
        panel.onKeyProblem = { [weak self] in self?.setSessionKey() }
        popover.contentViewController = panel
        popover.delegate = self
        // ไม่ใช้ .transient เพราะเมนูเฟืองที่เด้งจากในตัว popover จะปิดมันไปด้วย
        // ปิดเองด้วยตัวดักคลิกแทน แลกโค้ดไม่กี่บรรทัดกับแผงที่ไม่หายไปใต้เมนูของตัวเอง
        popover.behavior = .applicationDefined
        refreshLink()

        if let saved = UserDefaults.standard.string(forKey: Self.preferredKey),
            let id = UUID(uuidString: saved) {
            ble.preferredBoard = id
        }
        ble.onBoardsChanged = { [weak self] list in
            DispatchQueue.main.async { self?.showBoards(list) }
        }

        let store = SessionStore(toolMap: ToolMap.loadOrDefault(Paths.toolConfig))
        daemon = Daemon(store: store, transports: [ble])
        daemon.onPublish = { [weak self] snapshot in
            DispatchQueue.main.async { self?.show(snapshot) }
        }
        do {
            try daemon.start()
        } catch {
            // socket ถูกจองอยู่ = มี daemon อีกตัวรันค้าง บอกให้รู้แล้วออก
            // ดีกว่าโผล่ในเมนูบาร์เงียบๆ ทั้งที่ไม่ได้ทำงาน
            alert("tamaclaude could not start", "\(error)")
            NSApp.terminate(nil)
            return
        }

        poller = UsagePoller(
            interval: PollInterval.stored(
                UserDefaults.standard.object(forKey: Self.intervalKey) as? Int),
            preferredOrg: UserDefaults.standard.string(forKey: Self.orgKey),
            launch: PollProcess.launcher())
        poller.onChange = { [weak self] in self?.redrawQuota() }
        showIntervals()

        starter = SessionStarter(
            enabled: UserDefaults.standard.bool(forKey: Self.autoStartKey),
            launch: SessionProcess.launcher())
        showAutoStart()

        // เครื่องหลับไปสองชั่วโมงแล้วตื่นมาเจอตัวเลขเมื่อสองชั่วโมงที่แล้ว คือหน้าจอที่โกหก
        // รอบถัดไปยังอีกไกล ยิงทันทีหนึ่งรอบตรงนี้จึงเป็นการซ่อมที่ถูกเวลาที่สุด
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)

        // นาฬิกาตัวเดียวขับทั้งสถานะบอร์ดและตัวจับเวลาโควตา — ตัวจับเวลาสองตัวในโปรเซส
        // เดียวกันไม่ได้ทำให้อะไรเที่ยงขึ้น มีแต่จะต้องมาไล่ดูว่าใครยิงก่อนใคร
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshLink()
            self.poller.tick()
            // แถวโควตาที่ daemon อ่านไว้แล้ว ไม่ใช่การอ่านไฟล์รอบที่สองทุกวินาที
            self.starter.tick(usage: self.usage)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // ฆ่าลูกก่อนตาย ไม่งั้นลูกกำพร้ายิงต่อโดยไม่มีใครอ่านผล
        poller?.stop()
        starter?.stop()
        daemon?.stop()
    }

    // MARK: - เมนู

    /// เมนูเดิมทั้งอัน ลบแค่สองบรรทัดบนที่ย้ายไปอยู่ท้าย popover แล้ว
    ///
    /// เฟืองเด้ง NSMenu ไม่ใช่หน้า Settings ที่วาดเอง — ติ๊กถูก, submenu, slider ในเมนู
    /// และ Quit ทำงานถูกอยู่แล้ว การวาดใหม่เป็น NSView คือการรื้อของที่ใช้ได้
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        boardItem.submenu = NSMenu()
        menu.addItem(boardItem)
        showBoards(boards)
        menu.addItem(.separator())

        menu.addItem(brightnessItem())
        menu.addItem(.separator())

        keyItem.target = self
        menu.addItem(keyItem)

        // เมนูย่อยของ `refreshItem` เป็นของ `showIntervals` — ที่นี่แค่หาที่ให้มันยืน
        // การ `= NSMenu()` ตรงนี้จะล้างรายการที่เพิ่งเติมไปเมื่อครู่ เพราะเมนูถูกสร้าง
        // แบบ lazy คือ *หลัง* การเติมครั้งแรกเสมอ
        //
        // ตัวสลับ org ไม่อยู่ในเมนูนี้แล้ว — มันอยู่หลังลูกศรข้างชื่อ org ที่หัวแผง ซึ่งเป็น
        // ที่เดียวกับที่ชื่อที่ใช้อยู่แสดงอยู่ ที่สลับสองที่แปลว่าผู้ใช้ต้องจำว่าอันไหนคืออันจริง
        menu.addItem(refreshItem)

        // อยู่ในกลุ่มโควตา ไม่ใช่กลุ่มติดตั้ง — มันตัดสินว่าเลขโควตาจะมีมาให้ดูไหม
        // ซึ่งเป็นคำถามเดียวกับที่รายการเหนือมันตอบ
        autoStartItem.target = self
        menu.addItem(autoStartItem)
        menu.addItem(.separator())

        hooksItem.target = self
        menu.addItem(hooksItem)

        statuslineItem.target = self
        statuslineItem.state = StatuslineInstaller.isInstalled ? .on : .off
        menu.addItem(statuslineItem)

        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        let log = NSMenuItem(title: "Open log", action: #selector(openLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)

        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                       keyEquivalent: "q"))
        return menu
    }

    private func brightnessItem() -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 40))
        let label = NSTextField(labelWithString: "Brightness")
        label.frame = NSRect(x: 14, y: 20, width: 120, height: 16)
        label.font = .menuFont(ofSize: 12)
        view.addSubview(label)

        brightness.frame = NSRect(x: 14, y: 2, width: 192, height: 18)
        brightness.target = self
        brightness.action = #selector(brightnessChanged)
        brightness.isContinuous = false  // ส่งตอนปล่อยเมาส์ ไม่ใช่ทุกพิกเซลที่ลาก
        view.addSubview(brightness)

        let item = NSMenuItem()
        item.view = view
        return item
    }

    // MARK: - อัปเดตหน้าตา

    /// สถานะบอร์ดอยู่ท้าย popover ไม่ใช่ที่ไอคอน
    ///
    /// เคยหรี่ไอคอนตอนต่อบอร์ดไม่ติด แต่พอไอคอนกลายเป็นตัวเลขโควตา การหรี่กลับกลาย
    /// เป็นการทำให้ข้อมูลที่ยังถูกต้องอยู่ (โควตาไม่ได้มาจากบอร์ด) ดูเหมือนใช้ไม่ได้
    private func refreshLink() {
        panel.showBoard(connected: ble.isConnected)
    }

    /// รายการบอร์ดที่สแกนเจอ — ติ๊กตัวที่ผู้ใช้เลือกไว้ และวงเล็บบอกตัวที่กำลังคุยอยู่จริง
    ///
    /// การเลือกบอร์ดต้องอยู่ตรงนี้ ไม่ใช่หน้า Bluetooth ของ macOS: peripheral ที่เป็น
    /// GATT ล้วนไม่โผล่ให้จับคู่ที่นั่น มีแต่แอปที่สแกนเองเท่านั้นที่เห็น
    private func showBoards(_ list: [Board]) {
        boards = list
        let menu = boardItem.submenu ?? NSMenu()
        menu.removeAllItems()

        let preferred = ble.preferredBoard
        boardItem.title = list.isEmpty
            ? "Board: none found"
            : "Board: \(list.first(where: { $0.isCurrent })?.name ?? "not connected")"

        let any = NSMenuItem(
            title: "Any board", action: #selector(chooseBoard(_:)), keyEquivalent: "")
        any.target = self
        any.state = preferred == nil ? .on : .off
        menu.addItem(any)

        if !list.isEmpty { menu.addItem(.separator()) }
        for board in list {
            let item = NSMenuItem(
                title: board.isCurrent ? "\(board.name) (connected)" : board.name,
                action: #selector(chooseBoard(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = board.id
            item.state = preferred == board.id ? .on : .off
            menu.addItem(item)
        }
        boardItem.submenu = menu
    }

    /// วาดแบดจ์ใหม่เฉพาะตอนภาพจะเปลี่ยนจริง — `show` ถูกเรียกทุกครั้งที่ snapshot ขยับ
    /// ซึ่งรวมถึงนาฬิกาที่เดินทุกนาที ส่วนโควตาขยับนานๆ ครั้ง
    private func showBadge(_ badge: MenuBadge?) {
        // ถาม*ปุ่ม* ไม่ใช่แอป — แถบเมนูมืดได้ทั้งที่ทั้งระบบยังเป็นธีมสว่าง
        let dark = statusItem.button?.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let drawn = Drawn(badge: badge, highlighted: panelIsOpen, dark: dark)
        guard drawn != lastDrawn || statusItem.button?.image == nil else { return }
        lastDrawn = drawn
        guard let badge else {
            // ยังไม่เคยรู้โควตาเลย หรือหน้าต่างหมุนไปแล้วโดยไม่มีค่าใหม่ — ถอยไปเป็นไอคอนเดิม
            statusItem.button?.image = MenuBadgeImage.fallback()
            statusItem.button?.toolTip = "tamaclaude — no usage figures yet"
            return
        }
        statusItem.button?.image = MenuBadgeImage.make(
            badge, highlighted: panelIsOpen, dark: dark)
        statusItem.button?.toolTip = MenuBadgeImage.description(badge)
    }

    private func show(_ snapshot: Snapshot) {
        usage = snapshot.usage
        showBadge(MenuBadge.from(snapshot.usage))
        panel.showSessions(snapshot)
    }

    /// รอบการยิง — ติ๊กตัวที่ใช้อยู่ ไม่มีตัวเลือก 30 วินาที (เหตุผลอยู่ที่ `PollInterval`)
    private func showIntervals() {
        let menu = refreshItem.submenu ?? NSMenu()
        menu.removeAllItems()
        refreshItem.title = "Refresh quota: \(poller.interval.title)"
        for interval in PollInterval.allCases {
            let item = NSMenuItem(
                title: interval.title, action: #selector(chooseInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = interval.rawValue
            item.state = interval == poller.interval ? .on : .off
            menu.addItem(item)
        }
        refreshItem.submenu = menu
    }

    /// ติ๊กอ่านจาก `starter` ไม่ใช่จาก `UserDefaults` — ตัวที่ตัดสินใจจริงคือตัวที่ควรถูกถาม
    private func showAutoStart() {
        autoStartItem.state = starter.enabled ? .on : .off
    }

    /// รายการ org หลังลูกศรข้างชื่อที่หัวแผง — สร้างใหม่ทุกครั้งที่กด
    ///
    /// ติ๊กอ่านจากตัวที่ *ยิงจริง* ไม่ใช่จากค่าที่จำไว้ ตัวที่จำไว้แล้วหายไปจากบัญชี
    /// จะทำให้ไม่มีติ๊กสักอันทั้งที่กำลังยิงอยู่ตัวหนึ่ง
    private func showOrgMenu(from button: NSButton) {
        let current = poller.currentOrg
        let menu = NSMenu()
        for org in poller.orgs {
            let item = NSMenuItem(
                title: org.name, action: #selector(chooseOrg(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = org.id
            item.state = org.id == current ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -2), in: button)
    }

    /// แผงท้ายมีสองบรรทัดที่พูดคนละเรื่อง — ท่อพัง กับ ค่าเก่าแค่ไหน
    ///
    /// บรรทัดสรุปจากลูก (เช่น `HTTP 503`) ไปอยู่ใน tooltip ไม่ใช่บรรทัดที่สาม: มันตอบ
    /// คำถามที่เกิดขึ้นนานๆ ครั้ง ("ทำไมค่าถึงเก่า") การให้มันกินที่ถาวรคือการเอาเสียง
    /// รบกวนไปวางไว้ตรงหน้าตลอดเวลา
    private func redrawQuota() {
        redrawPanel()
        showIntervals()
    }

    /// เฉพาะแผง ไม่แตะเมนู — นาฬิกาวินาทีเรียกตัวนี้ เพราะรายการในเมนูเฟืองมาจากสถานะ
    /// ของ poller ซึ่งไม่ได้ขยับทุกวินาที และการสร้าง submenu ใหม่ขณะที่ผู้ใช้กางเมนูอยู่
    /// ทำให้แถบไฮไลต์ที่เขากำลังเลื่อนหลุด
    private func redrawPanel() {
        noteRefreshFinished()
        let hasKey = SessionKeyFile.isUsable()
        panel.showHeading(
            PanelText.heading(orgs: poller.orgs, current: poller.currentOrg, hasKey: hasKey),
            switchable: PanelText.canSwitchOrg(orgs: poller.orgs, hasKey: hasKey))
        panel.showRefresh(
            RefreshControl.state(
                running: poller.isRunning, hasKey: hasKey, finished: refreshFinished))
        panel.showQuota(
            problem: PanelText.keyProblem(poller.blocked),
            age: PanelText.updated(stamp: UsageReader.stamp()),
            cards: QuotaCard.cards(UsageReader.read()),
            detail: poller.status)
    }

    /// รอบของปุ่มจบเมื่อไร การเย็นตัวเริ่มเมื่อนั้น
    ///
    /// นับจากตอน *จบ* ไม่ใช่ตอนเริ่ม ไม่งั้นรอบที่ใช้เวลาสิบวินาทีจะพ้นการเย็นตัวไปแล้ว
    /// ตั้งแต่วินาทีที่มันคืนค่า ซึ่งแปลว่าไม่มีการเย็นตัวเลยสำหรับรอบที่ช้า
    private func noteRefreshFinished() {
        guard manualRefresh, !poller.isRunning else { return }
        manualRefresh = false
        refreshFinished = Date()
    }

    // MARK: - popover เปิด/ปิด

    @objc private func togglePanel() {
        popover.isShown ? popover.performClose(nil) : openPanel()
    }

    private func openPanel() {
        guard let button = statusItem.button else { return }
        // แอปที่ไม่มี Dock ไม่ได้ active เองตอนคลิกแถบเมนู ปุ่มในแผงจะกดไม่ติด
        NSApp.activate(ignoringOtherApps: true)
        // การเปิดแผงคือสัญญาณความตั้งใจที่ชัดพอจะยิงเอง ไม่ต้องรอให้ผู้ใช้กดปุ่มเพื่อบอก
        // สิ่งที่เขาบอกไปแล้วด้วยการเปิด — แต่ยิงเฉพาะตอนค่าที่มีเก่ากว่ารอบที่เขาตั้งไว้
        // ไม่งั้นทุกครั้งที่ชำเลืองดูจะกลายเป็นการยิงหนึ่งรอบ
        if RefreshControl.wantsPoll(
            interval: poller.interval, stamp: UsageReader.stamp(), polled: poller.lastStarted) {
            poller.pollNow()
        }
        // อายุของค่ากับ countdown เดินตลอดเวลาแต่ไม่มีใครเห็นตอนแผงปิด — คิดใหม่ตอนเปิด
        // แล้วเดินทุกวินาทีตราบใดที่ยังเปิดอยู่ ดีกว่าอ่าน cache จากดิสก์ทุกวินาที
        // ตลอดเวลาเพื่อข้อความที่ไม่มีใครมอง
        redrawQuota()
        panelTicks?.invalidate()
        let ticks = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.redrawPanel()
        }
        // `.common` ไม่ใช่ `.default` — เมนูเฟืองที่กางอยู่ทำให้ run loop เข้าโหมด tracking
        // แล้ว timer โหมดปกติหยุดยิงทั้งที่แผงยังเห็นอยู่เต็มๆ ตัวเลขที่ค้างตอนนั้น
        // คืออาการเดียวกับที่ฟีเจอร์นี้มีไว้แก้
        RunLoop.main.add(ticks, forMode: .common)
        panelTicks = ticks
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // popover ที่ไม่ใช่ .transient ไม่ปิดตัวเอง — คลิกนอกแอปคือสัญญาณเดียวที่เหลือ
        outsideClicks = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.popover.performClose(nil)
        }
        setHighlighted(true)
    }

    /// เก็บกวาดที่ `popoverDidClose` ที่เดียว ไม่ใช่ที่ทุกจุดที่สั่งปิด — ทางปิดมีหลายทาง
    /// (ปุ่มบนแถบเมนู, คลิกนอกแอป, ระบบสั่งปิดเอง) ตัวดักคลิกที่ค้างอยู่แม้แผงหายไปแล้ว
    /// คือ monitor ที่ไม่มีวันถูกถอด
    func popoverDidClose(_ notification: Notification) {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
        // ไม่มีใครดูอยู่แล้วยังวาดคือเผาแบตเปล่า — และเป็น timer ที่ไม่มีวันถูกหยุด
        // ถ้าหยุดที่ทุกจุดที่สั่งปิดแทนที่จะหยุดที่นี่ที่เดียว
        panelTicks?.invalidate()
        panelTicks = nil
        setHighlighted(false)
    }

    /// ปุ่มบนแถบเมนูถูกถมด้วยสีเน้นตอนแผงเปิด ภาพที่ไม่ใช่ template จึงต้องวาดใหม่
    ///
    /// ต้องถมเอง: การถมมาฟรีกับ `statusItem.menu` เท่านั้น ปุ่มที่เด้ง popover
    /// ดูเหมือนไม่ได้ถูกกดถ้าไม่บอก
    private func setHighlighted(_ on: Bool) {
        panelIsOpen = on
        statusItem.button?.highlight(on)
        showBadge(lastDrawn?.badge)
    }

    /// ติ๊กถูกสองอันอ่านค่าจริงทุกครั้งที่เมนูเด้ง ไม่ใช่ครั้งเดียวตอนสร้างเมนู —
    /// ทั้งคู่แก้ที่อื่นได้ (settings.json, หน้า Login Items ของระบบ) โดยแอปไม่รู้เรื่อง
    private func showGearMenu(from button: NSButton) {
        statuslineItem.state = StatuslineInstaller.isInstalled ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        // ไฟล์ key แก้จากข้างนอกได้เหมือนกัน — อ่านสภาพจริงทุกครั้งที่เมนูเด้ง
        keyItem.title = SessionKeyFile.isUsable() ? "Replace session key…" : "Set session key…"
        showAutoStart()
        showIntervals()
        gearMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: -2), in: button)
    }

    // MARK: - การกระทำ

    @objc private func chooseBoard(_ sender: NSMenuItem) {
        let id = sender.representedObject as? UUID
        ble.preferredBoard = id
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: Self.preferredKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.preferredKey)
        }
        showBoards(boards)
    }

    @objc private func chooseInterval(_ sender: NSMenuItem) {
        let interval = PollInterval.stored(sender.representedObject as? Int)
        poller.interval = interval
        UserDefaults.standard.set(interval.rawValue, forKey: Self.intervalKey)
        // เลือกรอบใหม่แล้วต้องเห็นผลเดี๋ยวนี้ ไม่ใช่รออีกหนึ่งรอบเพื่อพิสูจน์ว่ามันทำงาน
        poller.pollNow()
        showIntervals()
    }

    @objc private func toggleAutoStart() {
        starter.enabled.toggle()
        UserDefaults.standard.set(starter.enabled, forKey: Self.autoStartKey)
        showAutoStart()
    }

    @objc private func chooseOrg(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        poller.preferredOrg = id
        UserDefaults.standard.set(id, forKey: Self.orgKey)
        // ลูกที่วิ่งอยู่ถาม org ตัวเก่า คำตอบของมันจึงไม่ใช่สิ่งที่ผู้ใช้เพิ่งขอ ฆ่าทิ้งก่อน
        // ไม่งั้น `refreshNow` จะถอยออกเพราะมีรอบวิ่งอยู่ แล้วการเลือกจะเงียบไปเฉยๆ
        // จนกว่าจะครบรอบถัดไป — ซึ่งเมื่อรอบเป็น `Off` แปลว่าตลอดกาล
        poller.stop()
        poller.refreshNow()
        redrawPanel()
    }

    /// ช่องกรอกแบบปิดบังตัวอักษร แล้วแอปเขียนไฟล์ mode 600 ให้เอง
    ///
    /// ไม่ให้ผู้ใช้ไปสร้างไฟล์เอง: `sessionKey` เป็น credential เต็มบัญชี คนที่ลืม
    /// `chmod 600` จะเปิดบัญชีทั้งใบให้ทุกคนบนเครื่องโดยไม่รู้ตัว · key ไม่เคยถูก
    /// ใส่กลับเข้าช่องกรอกและไม่เคยโผล่ในข้อความไหน แม้แต่ตอนล้มเหลว
    @objc private func setSessionKey() {
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "sessionKey cookie from claude.ai"

        let a = NSAlert()
        a.messageText = "Set the claude.ai session key"
        a.informativeText =
            "Browser DevTools → Application → Cookies → claude.ai → sessionKey.\n"
            + "It is a full account credential; tamaclaude stores it readable only by you."
        a.accessoryView = field
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Cancel")
        // แอปไม่มีหน้าต่าง ช่องกรอกจึงไม่ได้โฟกัสเอง ผู้ใช้จะพิมพ์ลงที่ว่าง
        NSApp.activate(ignoringOtherApps: true)
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }

        do {
            try SessionKeyFile.write(field.stringValue)
        } catch let failure as UsagePoll.Failure {
            alert("Could not save the session key", failure.message)
            return
        } catch {
            alert("Could not save the session key", "\(error)")
            return
        }
        // ตั้ง key ใหม่แล้วกลับมายิงเองทันที ไม่ต้องปิดเปิดแอป
        poller.keyWasSet()
    }

    /// ปุ่ม refresh ที่หัวแผง — ทางออกฉุกเฉิน ไม่ใช่ทางปกติ
    ///
    /// `refreshNow` ข้าม `Off` และข้ามล็อก key หมดอายุ (เหตุผลอยู่ที่นั่น) วินัยที่เหลือ
    /// คือการเย็นตัว ซึ่งอยู่ที่ `RefreshControl` · `manualRefresh` อ่านจาก `isRunning`
    /// ไม่ใช่ตั้งเป็น `true` ดื้อๆ — รอบที่ไม่ได้เริ่มจริง (ไม่มี key) จะทำให้ปุ่มค้าง
    /// รอรอบที่ไม่มีวันจบ
    @objc private func refreshQuota() {
        poller.refreshNow()
        manualRefresh = poller.isRunning
        redrawPanel()
    }

    @objc private func woke() {
        poller?.pollNow()
    }

    @objc private func brightnessChanged() {
        let value = Int(brightness.doubleValue.rounded())
        ble.sendConfig(Data("{\"b\":\(value)}".utf8))
    }

    @objc private func installHooks() {
        do {
            try HookInstaller.install()
            alert(
                "Hooks installed",
                "Claude Code will report to tamaclaude from the next session onwards.")
        } catch {
            alert("Could not install hooks", "\(error)")
        }
    }

    /// เปิด/ปิดการยึดช่อง statusLine ซึ่งเป็นทางเดียวที่ตัวเลขโควตาเดินทางมาถึงบอร์ด
    ///
    /// พูดกับผู้ใช้ด้วยผลลัพธ์ที่เขาเห็น ("แสดงโควตาบนจอ") ไม่ใช่กลไก ("ยึด statusLine")
    /// แต่ต้องบอกให้ชัดว่าไปแตะ settings.json เพราะเป็นไฟล์ที่เขาแก้เองอยู่
    @objc private func toggleStatusline() {
        do {
            if StatuslineInstaller.isInstalled {
                try StatuslineInstaller.uninstall()
                alert("Usage display turned off",
                      "Your previous status line command has been restored.")
            } else {
                let previous = StatuslineInstaller.previousCommand()
                try StatuslineInstaller.install()
                alert(
                    "Usage display turned on",
                    previous.map {
                        "Claude Code reports your quota to tamaclaude from the next render "
                            + "onwards. Your own status line still runs and looks the same:\n\n\($0)"
                    } ?? "Claude Code reports your quota to tamaclaude from the next render onwards.")
            }
        } catch {
            alert("Could not change the usage display", "\(error)")
        }
        statuslineItem.state = StatuslineInstaller.isInstalled ? .on : .off
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Could not change the login item", "\(error)")
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Paths.log)
    }

    private func alert(_ title: String, _ body: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        a.runModal()
    }
}

enum MenuBar {
    static func run() -> Never {
        let app = NSApplication.shared
        // ไม่มีไอคอนใน Dock ไม่มีหน้าต่าง — อยู่บนแถบเมนูอย่างเดียว
        app.setActivationPolicy(.accessory)
        let delegate = MenuBarApp()
        app.delegate = delegate
        app.run()
        exit(0)
    }
}
