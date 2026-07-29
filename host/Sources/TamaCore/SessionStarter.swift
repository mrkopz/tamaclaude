import Foundation

/// รอบหนึ่งจบลงด้วยอะไร — แยกเฉพาะเท่าที่เปลี่ยนการตัดสินใจของรอบถัดไป
///
/// เส้นแบ่งเดียวกับที่ `PollBlock` ใช้กับ session key: อันที่ล็อกคืออันที่ยิงต่อไปก็ได้ผล
/// เดิมทุกรอบ และไม่มีอะไรนอกจากคนที่จะเปลี่ยนมันได้
public enum SessionOutcome: Equatable {
    case ok
    /// ไม่มีอะไรถูกยิงเลย เพราะไม่มี `claude` ให้เรียก — พก path ที่ไล่หามาแล้วติดมาด้วย
    /// เพราะคนที่ติดตั้งไว้ที่แปลกๆ ต้องรู้ว่าเราไปมองที่ไหนมาบ้างถึงจะรู้ว่าต้องชี้ที่ไหน
    case noBinary([String])
    /// ลูกจบเพราะยังไม่ได้ login — ยิงอีกกี่รอบก็จบแบบเดิม
    case authFailed
    /// เน็ตสะดุด ถูกฆ่าเพราะครบเวลา หรือแยกไม่ออก — รอบหน้าก็หายเอง
    case failed
}

/// เหตุที่ session จะไม่ถูกเริ่มจนกว่าผู้ใช้จะลงมือ
///
/// คนละเรื่องกับ `PollBlock` แม้ทรงจะเหมือนกัน — "แอปเริ่ม session ไม่ได้" กับ
/// "session key หมดอายุ" ให้ผู้ใช้ทำคนละอย่าง การยุบเป็นชนิดเดียวคือการบังคับให้
/// ทุกที่ที่อ่านมันต้องแยกเองอีกที
public enum StartBlock: Equatable {
    /// หา `claude` ไม่เจอ — พก path ที่ไล่หามาแล้ว
    case noBinary([String])
    /// `claude` มีอยู่แต่ยังไม่ได้ login
    case notLoggedIn
}

/// เริ่ม Claude Code session สั้นๆ ให้เองเมื่อไม่มีหน้าต่าง 5 ชั่วโมงเปิดอยู่
///
/// นี่คือที่เดียวในฝั่ง host ที่ *ใช้* โควตาของผู้ใช้ ที่เหลืออ่านอย่างเดียว รั้วจึงไม่ใช่
/// ของประดับ: ตัวยิงที่ไม่มีรั้วจะเริ่ม session ใหม่ทุกวินาทีจนกว่าเลขจะโผล่ ซึ่งใช้เวลา
/// ได้ถึงหนึ่งรอบ poll เต็มๆ — เผาโควตาจริงเป็นสิบรอบเพื่อเปิดหน้าต่างเดียว
///
/// ไม่มี timer ของตัวเอง ด้วยเหตุผลเดียวกับ `UsagePoller` — ถูกป้อน `tick(now:usage:)`
/// จากนาฬิกาวินาทีละครั้งของแอป ตรรกะทั้งอันจึงเป็นฟังก์ชันของเวลาที่ถูกส่งเข้ามา
public final class SessionStarter {
    /// spawn หนึ่งตัว แล้วคืนวิธีฆ่ามัน — ทรงเดียวกับ `UsagePoller.Launcher`
    ///
    /// ลูกพูดกลับมาเป็น `SessionOutcome` ไม่ใช่ exit code ดิบ: การแปลจาก code กับ
    /// สิ่งที่ลูกพ่นออกมาเป็น "ชนิดของความล้มเหลว" เป็นความรู้ของฝั่งที่ spawn จริง
    /// (`SessionProcess.classify`) ส่วนที่นี่ตัดสินแค่ว่าชนิดไหนล็อกและชนิดไหนไม่ล็อก
    public typealias Launcher = (_ done: @escaping (SessionOutcome) -> Void) -> () -> Void

    /// ลูกที่ไม่จบใน 30 วินาทีถูกฆ่า — เลขเดียวกับ `UsagePoller.timeout` และด้วยเหตุผล
    /// เดียวกัน: ลูกที่ค้างกินช่องเดียวที่มีอยู่ไว้ตลอดกาล
    public static let timeout: TimeInterval = 30

    /// เว้นห้านาทีนับจากลูกตัวก่อนจบ
    ///
    /// อยู่คู่กับกติกาหนึ่งครั้งต่อหน้าต่างเสมอ ไม่ใช่แทนกัน — การเย็นตัวอย่างเดียวยังลองใหม่
    /// ชั่วนิรันดร์เมื่อ session เริ่มไม่ขึ้นจริง ส่วนกติกาหนึ่งครั้งต่อหน้าต่างอย่างเดียวยัง
    /// ยิงรัวได้ในช่วงก่อนที่รอบ poll จะรายงานหน้าต่างใหม่
    public static let cooldown: TimeInterval = 300

    /// กติกา "หนึ่งครั้งต่อหนึ่งหน้าต่าง" เขียนเป็นสถานะ ไม่ใช่การเทียบ id ของหน้าต่าง
    ///
    /// ฝั่ง host ไม่เคยเห็น id ของหน้าต่าง มีแต่ `resets_at` ที่แปลงเป็น countdown ไปแล้ว
    /// การเอาสตริงเวลามาเทียบข้าม seam คือการสร้างกฎสำเนาที่สองที่จะเพี้ยนจากแบดจ์วันหนึ่ง
    private enum Arm {
        /// ยังไม่ได้ยิงในหน้าต่างนี้
        case ready
        /// ยิงไปแล้ว รอเห็นหน้าต่างเกิดขึ้นจริงก่อน
        case spent
        /// เห็นหน้าต่างแล้ว พอมันหายไปคือหน้าต่างใหม่รอบหน้า
        case sawWindow
    }

    /// ติ๊กในเมนู — ปิดแล้วเปิดใหม่คือคำสั่ง "ลองอีกที" ที่ผู้ใช้มีให้ใช้
    ///
    /// การล้างสถานะเกิดตอน *เปิด* ไม่ใช่ตอนปิด: คนที่ปิดสวิตช์ไม่ได้กำลังบอกว่าเขาไปแก้
    /// อะไรมา และรอบที่ยังวิ่งอยู่ก็ยังจบของมันตามปกติ
    public var enabled: Bool {
        didSet {
            guard enabled, !oldValue else { return }
            unblock()
        }
    }

    /// เหตุที่จะไม่มี session จนกว่าผู้ใช้จะลงมือ — `nil` คือไม่มีอะไรจะบอก
    public private(set) var blocked: StartBlock?

    private let launch: Launcher
    private var arm: Arm = .ready
    private var startedAt: Date?
    private var finishedAt: Date?
    private var kill: (() -> Void)?
    /// ลูกที่ถูกฆ่าไปแล้วยังพูดทีหลังได้ — รุ่นที่ไม่ตรงกันคือเสียงจากอดีต
    private var generation = 0
    /// ลูกจบแล้วแต่ยังไม่มีใครบอกว่าตอนนี้กี่โมง
    ///
    /// เวลาที่ลูกจบมาถึงทาง callback ซึ่งไม่มีนาฬิกาติดมาด้วย การไปหยิบ `Date()`
    /// ตรงนั้นคือการเอานาฬิกาจริงกลับเข้ามาในตรรกะที่ตั้งใจให้ฉีดเวลาได้ทั้งอัน —
    /// tick ถัดไป (ห่างไม่เกินหนึ่งวินาที) เป็นคนประทับเวลาให้แทน
    private var pendingFinish = false

    public init(enabled: Bool = false, launch: @escaping Launcher) {
        self.enabled = enabled
        self.launch = launch
    }

    public var isRunning: Bool { startedAt != nil }

    /// `usage` คือแถวเดียวกับที่แบดจ์กิน — เงื่อนไขยิงคือ "แบดจ์ไม่มีอะไรจะบอก"
    ///
    /// ส่ง `[UsageSnap]?` เข้ามาทั้งก้อนแทนที่จะส่งเปอร์เซ็นต์ เพราะกฎว่า "มีหน้าต่างไหม"
    /// เป็นของ `MenuBadge` อยู่แล้ว (ไม่รู้ ≠ ศูนย์ · countdown ถึงศูนย์ = หน้าต่างตายแล้ว)
    /// การเขียนกฎนั้นซ้ำที่นี่คือกฎสำเนาที่สองที่รอวันเพี้ยน
    public func tick(now: Date = Date(), usage: [UsageSnap]?) {
        // เดินสถานะก่อนทุกทางออก แม้สวิตช์จะปิดหรือมีลูกวิ่งอยู่ — หน้าต่างที่เกิดและดับไป
        // ตอนที่เราไม่ได้มองก็ยังเป็นหน้าต่างที่ผ่านไปแล้วจริงๆ และหน้าต่างที่ลูกของเราเอง
        // เป็นคนเปิดมักโผล่ในตัวเลขตั้งแต่ลูกยังไม่ตาย
        let hasWindow = MenuBadge.from(usage) != nil
        observe(hasWindow)

        if let startedAt {
            guard now.timeIntervalSince(startedAt) >= Self.timeout else { return }
            // ลูกที่ถูกฆ่าตรงนี้ยังพูดผ่าน `finished` ไม่ได้แล้ว (รุ่นไม่ตรงกัน) บรรทัดนี้จึงเป็น
            // ที่เดียวที่บอกได้ว่ารอบนั้นจบยังไง — และมันไม่ล็อก ด้วยเหตุผลเดียวกับ `.failed`
            Log.info("auto-start: the session took too long and was stopped")
            stop()
            finishedAt = now
            return
        }
        if pendingFinish {
            pendingFinish = false
            finishedAt = now
        }

        guard enabled, blocked == nil, !hasWindow, arm == .ready else { return }
        if let finishedAt, now.timeIntervalSince(finishedAt) < Self.cooldown { return }
        start(now)
    }

    /// ปิดแอปแล้วต้องไม่มีลูกกำพร้า — เหตุผลเดียวกับ `UsagePoller.stop`
    public func stop() {
        kill?()
        generation += 1
        kill = nil
        startedAt = nil
    }

    private func observe(_ hasWindow: Bool) {
        switch (arm, hasWindow) {
        case (.spent, true): arm = .sawWindow
        case (.sawWindow, false): arm = .ready
        default: break
        }
    }

    private func start(_ now: Date) {
        generation += 1
        let gen = generation
        startedAt = now
        arm = .spent
        let handle = launch { [weak self] code in
            self?.finished(gen, code)
        }
        // ลูกที่เริ่มไม่ขึ้นตอบกลับมาแล้วตั้งแต่ก่อนบรรทัดนี้ได้ — เก็บวิธีฆ่าลูกที่ตายไปแล้วไว้
        // แปลว่า `stop()` รอบหน้าจะไปฆ่าอะไรบางอย่างที่ไม่ใช่ลูกของเรา
        if isRunning { kill = handle }
    }

    private func finished(_ gen: Int, _ outcome: SessionOutcome) {
        guard gen == generation else { return }
        startedAt = nil
        kill = nil
        pendingFinish = true

        // รอบที่ไม่สำเร็จไม่ได้เปิดหน้าต่างอะไรไว้ให้รอ — ปล่อยให้ `.spent` ค้างคือการ
        // รอหน้าต่างที่จะไม่มีวันมา ซึ่งทำให้ความล้มเหลว *ชั่วคราว* หนึ่งครั้งฆ่าฟีเจอร์นี้
        // ถาวรพอๆ กับล็อก แต่เงียบกว่า · การเย็นตัวยังกันการยิงรัวอยู่ และหน้าต่างที่ลูก
        // ตัวนั้นเผลอเปิดไว้จริง (เช่นถูก rate limit) ยังกันด้วย `hasWindow` เหมือนเดิม
        if outcome != .ok { arm = .ready }

        switch outcome {
        case .ok:
            blocked = nil
        case .noBinary(let searched):
            blocked = .noBinary(searched)
            Log.info(
                "auto-start: stopped — no claude binary in \(searched.joined(separator: ", "))")
        case .authFailed:
            blocked = .notLoggedIn
            Log.info("auto-start: stopped — claude is not logged in")
        case .failed:
            // แยกไม่ออกว่าเพราะอะไร ก็แปลว่าไม่มีอะไรให้ผู้ใช้ทำ — รอบหน้าที่ครบเงื่อนไข
            // ยิงตามปกติ การล็อกไว้ตรงนี้คือการปิดฟีเจอร์ทิ้งเพราะเน็ตสะดุดหนึ่งครั้ง
            break
        }
    }

    /// ล้างสถานะล็อกแล้วให้โอกาสยิงทันที — ไม่ต้องปิดเปิดแอป
    ///
    /// ล้าง `arm` ด้วย ไม่ใช่แค่ `blocked`: รอบที่ล็อกได้ยิงไปแล้วหนึ่งครั้ง จึงทิ้ง `.spent`
    /// ไว้เสมอ และหน้าต่างที่ `.spent` รออยู่จะไม่มีวันมา เพราะ session ที่จะเปิดมันคือ
    /// ตัวที่เพิ่งล้มเหลว — เท่ากับล็อกตัวที่สองที่ปลดไม่ได้ · การเย็นตัวก็ล้าง เพราะมันเป็น
    /// วินัยของนาฬิกาแอป ไม่ใช่ของคนที่เพิ่งลงมือแก้แล้วสั่งให้ลองใหม่
    private func unblock() {
        blocked = nil
        finishedAt = nil
        arm = .ready
    }
}

/// `claude` อยู่ที่ไหน
///
/// แอปที่ถูกปล่อยผ่าน LaunchServices ได้ PATH ของ launchd ซึ่งไม่มีที่ที่ `claude`
/// อยู่จริงสักที่ การเรียกชื่อเปล่าๆ จึงล้มเหลวเสมอบนเครื่องที่ติดตั้งไว้ถูกต้อง
public enum ClaudeBinary {
    /// ผลของการไล่หา — ตัวที่เจอ หรือรายการที่ไปมองมาแล้ว
    ///
    /// พก path ที่ค้นมากลับไปด้วยเสมอ เพราะข้อความ "หาไม่เจอ" ที่ไม่บอกว่าหาที่ไหน
    /// ไม่ได้ช่วยคนที่ติดตั้ง `claude` ไว้ที่แปลกๆ ให้รู้ว่าต้องชี้ที่ไหน
    public enum Found: Equatable {
        case at(URL)
        case missing([String])
    }

    /// path ที่ผู้ใช้ชี้เอง — ไม่มี UI โดยตั้งใจ
    ///
    ///     defaults write com.tamaclaude.daemon claudePath /where/claude/is
    ///
    /// ไม่มี UI เพราะคนที่ต้องใช้มันคือคนที่ติดตั้งไว้นอกทั้งสี่ที่ข้างล่าง ซึ่งพบได้น้อย
    /// เกินกว่าจะกินที่ถาวรในเมนูที่คนอื่นทั้งหมดต้องอ่านผ่าน
    public static let overrideKey = "claudePath"

    /// ที่ที่ `claude` อยู่ได้จริงบนเครื่องที่ติดตั้งตามปกติ
    public static var knownPaths: [URL] {
        [
            Paths.home.appendingPathComponent(".local/bin/claude"),
            Paths.home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
    }

    /// ค่าที่ผู้ใช้ตั้งไว้ ถ้ามีและไม่ใช่ที่ว่าง
    public static func override(_ defaults: UserDefaults = .standard) -> String? {
        let value = defaults.string(forKey: overrideKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// ค่าที่ผู้ใช้ชี้เอง *แทนที่* รายการทั้งอัน ไม่ใช่ถูกเติมต่อท้าย — คนที่ตั้งค่านี้รู้ว่า
    /// `claude` ตัวไหนคือตัวที่เขาต้องการ การไล่ต่อไปที่อื่นเมื่อตัวนั้นใช้ไม่ได้คือการเงียบๆ
    /// ไปใช้ตัวที่เขาไม่ได้เลือก
    public static func candidates(override: String? = ClaudeBinary.override()) -> [URL] {
        guard let override else { return knownPaths }
        return [URL(fileURLWithPath: (override as NSString).expandingTildeInPath)]
    }

    /// ตัวแรกที่มีอยู่จริงและ execute ได้
    public static func locate(_ list: [URL] = candidates()) -> Found {
        if let found = list.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return .at(found)
        }
        return .missing(list.map(\.path))
    }
}

/// ตัว spawn จริง — และคนเดียวที่รู้ว่า `claude` พูดว่าอะไรตอนไหน
///
/// การ spawn เองไม่มี logic ให้เทสต์ ส่วนที่มีคือ `classify` ซึ่งอยู่ตรงนี้เพราะมันเป็น
/// ความรู้เกี่ยวกับโปรเซสลูก ไม่ใช่กติกาว่าใครล็อกใครไม่ล็อก — กติกานั้นอยู่ที่ `SessionStarter`
public enum SessionProcess {
    /// สั้นที่สุดเท่าที่ยังเป็น session จริง — ราคาทั้งหมดของฟีเจอร์นี้คือค่าเปิด session
    static let prompt = "ok"

    /// cwd ของ session ที่ยิงเอง — ว่างเปล่า จึงไม่มี `CLAUDE.md` ของโปรเจกต์ไหน
    /// ถูกลากเข้าไปใน prompt ที่ไม่ได้ทำงานอะไร
    public static func workDir() -> URL {
        let dir = Paths.stateDir.appendingPathComponent("idle-session", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// exit code บอกแค่ว่า "ไม่สำเร็จ" — `claude` ใช้ 1 กับทุกอย่างที่ผิดพลาด
    ///
    /// สิ่งที่แยก "ยังไม่ได้ login" ออกจาก "เน็ตหลุด" ได้จึงเป็นข้อความที่มันพ่นออกมา
    /// ตอนตาย ไม่ใช่ตัวเลข · รายการนี้จงใจสั้นและตรงตัว: marker ที่กว้างเกินไปจะเปลี่ยน
    /// ความล้มเหลวชั่วคราวให้กลายเป็นล็อกถาวร ซึ่งเป็นความผิดพลาดที่ผู้ใช้ต้องมาปลดเอง
    /// ส่วน marker ที่แคบไปแค่ทำให้ยิงซ้ำอีกไม่กี่รอบจนกว่าจะมีคนสังเกต
    static let authMarkers = [
        "please run /login",
        "invalid api key",
        "oauth token has expired",
        "authentication_error",
    ]

    /// สิ่งที่ลูกพูดตอนตาย แปลเป็นชนิดของความล้มเหลว
    public static func classify(code: Int32, output: String) -> SessionOutcome {
        guard code != 0 else { return .ok }
        let text = output.lowercased()
        if authMarkers.contains(where: text.contains) { return .authFailed }
        return .failed
    }

    /// `-p` = one-shot print mode: ไม่มี TTY ไม่มีหน้าต่าง Terminal โผล่ ลูกจบเอง
    ///
    /// `haiku` เพราะหน้าต่าง 5 ชั่วโมงนับรวมทุกโมเดล (เฉพาะ `weekly_scoped` เท่านั้น
    /// ที่แยกตามโมเดล) โมเดลถูกที่สุดจึงเปิดหน้าต่างได้เท่ากับโมเดลแพงที่สุด
    ///
    /// MCP ปิดทั้งหมด: schema ของ server ทุกตัวที่ผู้ใช้ตั้งไว้คือส่วนที่ใหญ่ที่สุดของ
    /// ค่าเปิด session · **hooks ไม่ปิด** เพราะเป็นทางเดียวที่ daemon จะรู้ว่ามี session
    /// และการที่มาสคอตขยับคือครึ่งหนึ่งของเหตุผลที่ฟีเจอร์นี้มีอยู่
    public static func launcher(_ locate: @escaping () -> ClaudeBinary.Found = {
        ClaudeBinary.locate()
    }) -> SessionStarter.Launcher {
        { done in
            let executable: URL
            switch locate() {
            case .at(let found):
                executable = found
            case .missing(let searched):
                Log.info(
                    "auto-start: nothing started, no claude binary in "
                        + searched.joined(separator: ", "))
                DispatchQueue.main.async { done(.noBinary(searched)) }
                return {}
            }

            let process = Process()
            process.executableURL = executable
            process.arguments = [
                "-p", prompt, "--model", "haiku", "--strict-mcp-config", "--mcp-config", "{}",
            ]
            process.currentDirectoryURL = workDir()

            // สองสายรวมเป็น pipe เดียว: เราไม่ได้อ่านเพื่อเอาคำตอบ แต่เพื่อรู้ว่าตายเพราะ
            // อะไร และ `claude` ไม่ได้สัญญาว่าจะบ่นลงสายไหน · ต้องอ่านจริงด้วย —
            // pipe ที่ไม่มีคนอ่านจะบล็อกลูกจนโดนฆ่าตอนครบ 30 วินาทีโดยไม่มีเหตุผล
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let output = ChildOutput.draining(pipe)
            process.terminationHandler = { finished in
                output.drain(pipe)
                let code = finished.terminationStatus
                let outcome = classify(code: code, output: output.text)
                Log.info("auto-start: the session ended with code \(code) (\(outcome))")
                DispatchQueue.main.async { done(outcome) }
            }

            do {
                Log.info("auto-start: starting a session with \(executable.path)")
                try process.run()
            } catch {
                // ไฟล์มีอยู่และ execute ได้เมื่อครู่นี้เอง แต่รันไม่ขึ้น — แยกไม่ออกว่า
                // ถาวรหรือชั่วคราว จึงไม่ล็อก ด้วยกติกาเดียวกับความล้มเหลวที่อธิบายไม่ได้
                Log.info("auto-start: could not run \(executable.path): \(error)")
                pipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async { done(.failed) }
                return {}
            }

            return {
                guard process.isRunning else { return }
                process.terminate()
                // TERM แล้วยังไม่ตายใน 2 วินาที = ค้างจริง ไม่ใช่กำลังเก็บกวาด
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if process.isRunning { Foundation.kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
    }
}
