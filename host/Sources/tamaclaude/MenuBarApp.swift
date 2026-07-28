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

    private let popover = NSPopover()
    private let panel = PanelViewController()
    private lazy var gearMenu: NSMenu = buildMenu()
    /// ตัวดักคลิกนอกแอปตอน popover เปิด — มีอยู่ก็ต่อเมื่อ popover เปิดอยู่
    private var outsideClicks: Any?

    private let boardItem = NSMenuItem(title: "Board", action: nil, keyEquivalent: "")
    private var boards: [Board] = []
    private let hooksItem = NSMenuItem(
        title: "Install hooks in ~/.claude/settings.json", action: #selector(installHooks),
        keyEquivalent: "")
    private let statuslineItem = NSMenuItem(
        title: "Show usage on the board", action: #selector(toggleStatusline), keyEquivalent: "")
    private let loginItem = NSMenuItem(
        title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
    private let brightness = NSSlider(value: 100, minValue: 5, maxValue: 100, target: nil,
                                      action: nil)

    /// ภาพที่วาดไปแล้ว — ไฮไลต์เป็นส่วนหนึ่งของภาพ ไม่ใช่แค่ค่าโควตา
    private struct Drawn: Equatable {
        var badge: MenuBadge?
        var highlighted: Bool
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

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshLink()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        let drawn = Drawn(badge: badge, highlighted: panelIsOpen)
        guard drawn != lastDrawn || statusItem.button?.image == nil else { return }
        lastDrawn = drawn
        guard let badge else {
            // ยังไม่เคยรู้โควตาเลย หรือหน้าต่างหมุนไปแล้วโดยไม่มีค่าใหม่ — ถอยไปเป็นไอคอนเดิม
            statusItem.button?.image = MenuBadgeImage.fallback()
            statusItem.button?.toolTip = "tamaclaude — no usage figures yet"
            return
        }
        statusItem.button?.image = MenuBadgeImage.make(badge, highlighted: panelIsOpen)
        statusItem.button?.toolTip = MenuBadgeImage.description(badge)
    }

    private func show(_ snapshot: Snapshot) {
        showBadge(MenuBadge.from(snapshot.usage))
        panel.showSessions(snapshot)
    }

    // MARK: - popover เปิด/ปิด

    @objc private func togglePanel() {
        popover.isShown ? popover.performClose(nil) : openPanel()
    }

    private func openPanel() {
        guard let button = statusItem.button else { return }
        // แอปที่ไม่มี Dock ไม่ได้ active เองตอนคลิกแถบเมนู ปุ่มในแผงจะกดไม่ติด
        NSApp.activate(ignoringOtherApps: true)
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
