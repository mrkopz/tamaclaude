import Darwin
import Foundation

/// spawn ลูกที่ไม่ยืมตัวตนของแอปไปขอสิทธิ์ TCC
///
/// TCC ผูกคำขอสิทธิ์กับ "responsible process" ซึ่งปริยายคือบรรพบุรุษที่เป็นแอป ไม่ใช่ตัวที่แตะ
/// ของจริง · `claude` ที่เป็นลูกของ TamaClaude.app จึงทำให้ทุกอย่างที่มันอ่านถูกถามในนาม
/// TamaClaude — เห็นได้จาก `tccd` ตรงๆ:
///
///     AUTHREQ_ATTRIBUTION: responsible={com.tamaclaude.daemon},
///                          accessing={com.anthropic.claude-code}
///     AUTHREQ_PROMPTING: service=kTCCServiceSystemPolicyDocumentsFolder,
///                        subject=Sub:{com.tamaclaude.daemon}
///
/// และเพราะลายเซ็นเป็น adhoc ("Failed to match existing code requirement") คำตอบของผู้ใช้
/// ไม่เคยถูกจำ กล่องสิทธิ์จึงเด้งใหม่ทุกรอบที่ `SessionStarter` เปิด session ให้เอง
///
/// `responsibility_spawnattrs_setdisclaim` คือ SPI ที่บอกให้ลูกรับผิดชอบตัวเอง (Chrome และ
/// Electron ใช้ทางเดียวกัน) · ต้องลงมาที่ `posix_spawn` เพราะ `Process` ไม่เปิดให้ตั้ง
/// spawn attribute เลยสักตัว
public enum Spawn {
    public enum Problem: Error, CustomStringConvertible {
        /// `posix_spawn` ตอบ errno มา — ไฟล์หาย สิทธิ์ไม่พอ หรือไม่ใช่ไบนารีของสถาปัตยกรรมนี้
        case failed(Int32)

        public var description: String {
            switch self {
            case .failed(let code): return "posix_spawn failed (\(code))"
            }
        }
    }

    /// ลูกหนึ่งตัว — ผิวเท่าที่ผู้เรียกใช้จริง ไม่ใช่ `Process` ย่อส่วน
    public final class Child: @unchecked Sendable {
        public let pid: pid_t
        private let lock = NSLock()
        private var alive = true
        /// ต้องถือไว้ ไม่งั้น source ถูกปล่อยแล้วไม่มีใครมาเก็บศพลูก
        private var watcher: DispatchSourceProcess?

        init(pid: pid_t) {
            self.pid = pid
        }

        public var isRunning: Bool {
            lock.lock()
            defer { lock.unlock() }
            return alive
        }

        func watch(_ source: DispatchSourceProcess) {
            lock.lock()
            watcher = source
            lock.unlock()
        }

        func buried() {
            lock.lock()
            alive = false
            watcher = nil
            lock.unlock()
        }

        /// ขอให้จบเอง — สัญญาณไปถึงลูกที่ยังไม่ถูกเก็บศพเท่านั้น pid ที่ถูกใช้ซ้ำแล้ว
        /// จะได้ TERM แทนใครก็ไม่รู้
        public func terminate() {
            guard isRunning else { return }
            Darwin.kill(pid, SIGTERM)
        }

        public func forceKill() {
            guard isRunning else { return }
            Darwin.kill(pid, SIGKILL)
        }
    }

    /// สถานะขาออกในรูปเดียวกับ `Process.terminationStatus` — ตายด้วยสัญญาณคือ 128 + เลขสัญญาณ
    /// (`SIGTERM` = 143) เพราะ `SessionProcess.classify` ถูกเขียนกับเลขชุดนั้น
    public static func exitCode(_ status: Int32) -> Int32 {
        if status & 0x7f == 0 { return (status >> 8) & 0xff }
        return 128 + (status & 0x7f)
    }

    /// `int responsibility_spawnattrs_setdisclaim(posix_spawnattr_t *attrs, int disclaim)`
    ///
    /// ไม่มี header สาธารณะ — หาไม่เจอแปลว่า macOS รุ่นนี้ไม่มีให้ใช้ ซึ่งยังต้อง spawn ต่อได้
    /// แค่ได้พฤติกรรมเดิม · รับ *พอยน์เตอร์ไปยังตัวแปร* attr ไม่ใช่ตัว attr เอง — ส่งผิดชั้นแล้ว
    /// ได้ EINVAL (22) กลับมาเงียบๆ และลูกก็ยังยืมตัวตนเราไปเหมือนเดิม
    typealias Disclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    private static let disclaim: Disclaim? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), // RTLD_DEFAULT
            "responsibility_spawnattrs_setdisclaim") else { return nil }
        return unsafeBitCast(symbol, to: Disclaim.self)
    }()

    /// ใครเป็นคนรับผิดชอบสิทธิ์ของ pid นี้ในสายตา TCC — `nil` เมื่อถามไม่ได้
    ///
    /// มีไว้ให้เทสต์เท่านั้น และมีเพราะเทสต์ที่ดูแค่ค่าที่ส่งเข้า `posix_spawn` จะผ่านทั้งที่
    /// ลูกยังยืมตัวตนเราอยู่ · ตอบเป็นตัวลูกเอง = disclaim ติด
    public static func responsible(of pid: pid_t) -> pid_t? {
        typealias Ask = @convention(c) (pid_t) -> pid_t
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
            "responsibility_get_pid_responsible_for_pid") else { return nil }
        let answer = unsafeBitCast(symbol, to: Ask.self)(pid)
        return answer > 0 ? answer : nil
    }

    /// `output` รับทั้ง stdout และ stderr เหมือนกันหมด — ผู้เรียกอ่านที่เดียว
    ///
    /// ปลายเขียนถูกปิดในฝั่งพ่อทันทีหลัง spawn: เหลือไว้แปลว่า EOF ไม่มีวันมาถึงแม้ลูกจะตายแล้ว
    @discardableResult
    public static func disclaimed(
        executable: URL,
        arguments: [String] = [],
        currentDirectory: URL? = nil,
        output: Pipe,
        onExit: @escaping (Int32) -> Void
    ) throws -> Child {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }

        // ล้มแล้วต้องดัง: ธงที่ตั้งไม่ติดไม่ทำให้อะไรพัง มันแค่พาพฤติกรรมเก่ากลับมาเงียบๆ
        // ซึ่งเป็นความล้มเหลวชนิดที่ไม่มีใครเห็นจนกว่ากล่องสิทธิ์จะเด้งอีกในอีกห้าชั่วโมง
        if let disclaim {
            let rc = disclaim(&attr, 1)
            if rc != 0 { Log.info("spawn: could not disclaim the child (\(rc))") }
        } else {
            Log.info("spawn: cannot disclaim the child, it will ask for permissions as us")
        }

        // ปิด fd ทุกตัวที่ไม่ได้สั่งไว้ใน file actions — ปลายอ่านของ pipe ที่หลุดติดลูกไปด้วย
        // ทำให้ EOF ไม่มาถึงพ่อ และคนอ่านจะค้างรอไบต์ที่ไม่มีใครเขียนแล้ว
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        // stdin ต้องมีจริงและต้องจบทันที — ลูกที่รอ input บนสายที่ไม่มีใครพิมพ์คือลูกที่ค้าง
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        let writer = output.fileHandleForWriting.fileDescriptor
        posix_spawn_file_actions_adddup2(&actions, writer, 1)
        posix_spawn_file_actions_adddup2(&actions, writer, 2)
        if let currentDirectory {
            posix_spawn_file_actions_addchdir_np(&actions, currentDirectory.path)
        }

        var argv: [UnsafeMutablePointer<CChar>?] = ([executable.path] + arguments).map { strdup($0) }
        argv.append(nil)
        defer { for slot in argv { free(slot) } }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, executable.path, &actions, &attr, &argv, environ)
        guard rc == 0 else { throw Problem.failed(rc) }

        try? output.fileHandleForWriting.close()

        let child = Child(pid: pid)
        let source = DispatchSource.makeProcessSource(
            identifier: pid, eventMask: .exit, queue: .global())
        source.setEventHandler {
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            source.cancel()
            child.buried()
            onExit(exitCode(status))
        }
        child.watch(source)
        source.resume()
        return child
    }
}
