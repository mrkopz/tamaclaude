import Foundation

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
    /// ลูกพูดกลับมาแค่ exit code: การจำแนกว่าความล้มเหลวชนิดไหนควรหยุดยิงถาวร
    /// เป็นเรื่องของใบถัดไป ใบนี้ลองใหม่รอบหน้าเสมอ
    public typealias Launcher = (_ done: @escaping (Int32) -> Void) -> () -> Void

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

    public var enabled: Bool

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
            stop()
            finishedAt = now
            return
        }
        if pendingFinish {
            pendingFinish = false
            finishedAt = now
        }

        guard enabled, !hasWindow, arm == .ready else { return }
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

    private func finished(_ gen: Int, _ code: Int32) {
        guard gen == generation else { return }
        startedAt = nil
        kill = nil
        pendingFinish = true
    }
}

/// `claude` อยู่ที่ไหน
///
/// แอปที่ถูกปล่อยผ่าน LaunchServices ได้ PATH ของ launchd ซึ่งไม่มีที่ที่ `claude`
/// อยู่จริงสักที่ การเรียกชื่อเปล่าๆ จึงล้มเหลวเสมอบนเครื่องที่ติดตั้งไว้ถูกต้อง
public enum ClaudeBinary {
    public static var candidates: [URL] {
        [
            Paths.home.appendingPathComponent(".local/bin/claude"),
            Paths.home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
    }

    /// ตัวแรกที่มีอยู่จริงและ execute ได้
    public static func find(_ list: [URL] = candidates) -> URL? {
        list.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

/// ตัว spawn จริง — บางจนไม่มี logic ให้เทสต์ ตรรกะทั้งหมดอยู่ใน `SessionStarter`
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

    /// `-p` = one-shot print mode: ไม่มี TTY ไม่มีหน้าต่าง Terminal โผล่ ลูกจบเอง
    ///
    /// `haiku` เพราะหน้าต่าง 5 ชั่วโมงนับรวมทุกโมเดล (เฉพาะ `weekly_scoped` เท่านั้น
    /// ที่แยกตามโมเดล) โมเดลถูกที่สุดจึงเปิดหน้าต่างได้เท่ากับโมเดลแพงที่สุด
    ///
    /// MCP ปิดทั้งหมด: schema ของ server ทุกตัวที่ผู้ใช้ตั้งไว้คือส่วนที่ใหญ่ที่สุดของ
    /// ค่าเปิด session · **hooks ไม่ปิด** เพราะเป็นทางเดียวที่ daemon จะรู้ว่ามี session
    /// และการที่มาสคอตขยับคือครึ่งหนึ่งของเหตุผลที่ฟีเจอร์นี้มีอยู่
    public static func launcher(_ binary: @escaping () -> URL? = { ClaudeBinary.find() })
        -> SessionStarter.Launcher {
        { done in
            guard let executable = binary() else {
                Log.info("auto-start: no claude binary found, nothing was started")
                DispatchQueue.main.async { done(1) }
                return {}
            }

            let process = Process()
            process.executableURL = executable
            process.arguments = [
                "-p", prompt, "--model", "haiku", "--strict-mcp-config", "--mcp-config", "{}",
            ]
            process.currentDirectoryURL = workDir()
            // ไม่มีใครอ่านสิ่งที่ลูกพูด — pipe ที่ไม่มีคนอ่านจะบล็อกลูกจนโดนฆ่าตอนครบ
            // 30 วินาทีโดยไม่มีเหตุผล
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                let code = finished.terminationStatus
                Log.info("auto-start: the session ended with code \(code)")
                DispatchQueue.main.async { done(code) }
            }

            do {
                Log.info("auto-start: starting a session with \(executable.path)")
                try process.run()
            } catch {
                Log.info("auto-start: could not run \(executable.path): \(error)")
                DispatchQueue.main.async { done(1) }
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
