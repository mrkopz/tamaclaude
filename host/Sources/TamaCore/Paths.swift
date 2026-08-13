import Foundation

/// ที่อยู่ไฟล์ทั้งหมดของฝั่ง Mac
public enum Paths {
    public static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    public static var stateDir: URL {
        home.appendingPathComponent(".tamaclaude", isDirectory: true)
    }

    /// Unix socket ที่ hook คุยกับ daemon
    /// sun_path จำกัด 104 ไบต์ พาธนี้สั้นพอเสมอเพราะอยู่ใต้ home
    public static var socket: URL {
        stateDir.appendingPathComponent("daemon.sock")
    }

    public static var toolConfig: URL {
        stateDir.appendingPathComponent("tools.json")
    }

    /// session key ของ claude.ai — credential เต็มบัญชี ต้องเป็น mode 600
    /// อยู่ใต้ state dir ไม่ใช่ใน repo ไหน และไม่เคยผ่าน argv หรือ env
    public static var sessionKey: URL {
        stateDir.appendingPathComponent("session-key")
    }

    /// key ของ Finnhub สำหรับหน้าหุ้น — กติกาไฟล์เดียวกับ `sessionKey` (mode 600,
    /// ไม่ผ่าน argv, ไม่ผ่าน env, ไม่ลง log) แม้จะเป็น credential ที่เล็กกว่ามาก:
    /// มันคือโควตาของผู้ใช้ และกฎที่มีข้อยกเว้นคือกฎที่ไม่มีใครจำได้ว่าใช้กับใบไหน
    public static var finnhubKey: URL {
        stateDir.appendingPathComponent("finnhub-key")
    }

    /// กุญแจปิดผนึกเฟรมบน LAN — 32 ไบต์เป็น hex, mode 600 เหมือน `sessionKey`
    /// คนละอย่างกับ `sessionKey` โดยสิ้นเชิง: อันนี้เปิดได้แค่ช่องคุยกับบอร์ด (`LanKey`)
    public static var lanKey: URL {
        stateDir.appendingPathComponent("lan-key")
    }

    public static var log: URL {
        stateDir.appendingPathComponent("daemon.log")
    }

    /// สคริปต์ที่เรายึดช่อง `statusLine.command` ไว้ — เขียน cache แล้วส่งงานวาดต่อ
    public static var statusline: URL {
        stateDir.appendingPathComponent("statusline.sh")
    }

    /// cache โควตาที่ statusline เขียน — ที่อยู่เดิมของ Claude Usage.app
    /// ใช้ที่เดียวกันเพื่อให้ statusline เดิมของผู้ใช้อ่านต่อได้โดยไม่ต้องแก้อะไร
    public static var usageCache: URL {
        home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent(".statusline-usage-cache")
    }

    /// งบต่อเดือนเป็นดอลลาร์ — ตัวเลขล้วนบรรทัดเดียว ผู้ใช้แก้เองด้วยมือ
    ///
    /// แยกจาก `usageCache` เพราะเป็นคนละอายุ: cache ถูกเขียนทับทุกสิบวินาที
    /// ส่วนงบเป็นค่าที่ผู้ใช้ตั้งแล้วลืมไปเป็นเดือน การอยู่ไฟล์เดียวกันแปลว่า
    /// วันหนึ่งที่ cache เขียนพลาด งบจะหายไปด้วยโดยไม่มีใครสังเกต
    public static var budget: URL {
        stateDir.appendingPathComponent("budget")
    }

    /// ยอดเงินสะสมรายสัปดาห์ต่อ session — สถานะของ `SpendLedger`
    ///
    /// ไม่ใช่ credential แต่เป็น mode 600 เหมือนกัน: มันบอกได้ว่าเครื่องนี้
    /// ทำงานหนักแค่ไหนและเมื่อไร ซึ่งไม่ใช่เรื่องของผู้ใช้อื่นบนเครื่องเดียวกัน
    public static var spendLedger: URL {
        stateDir.appendingPathComponent("spend.json")
    }

    @discardableResult
    public static func ensureStateDir() -> Bool {
        (try? FileManager.default.createDirectory(
            at: stateDir, withIntermediateDirectories: true)) != nil
    }
}

/// log แบบง่ายที่สุดที่ยังใช้งานได้ — เขียน stderr เสมอ
///
/// เขียนลงไฟล์ด้วยเมื่อเปิด `toFile` เพราะตอนถูกปล่อยผ่าน LaunchServices (`open`)
/// ไม่มีใครเห็น stderr เลย ซึ่งเป็นวิธีเดียวที่ขอสิทธิ์ Bluetooth ได้สำเร็จ
public enum Log {
    public nonisolated(unsafe) static var verbose = false
    public nonisolated(unsafe) static var toFile = false

    private static let lock = NSLock()

    public static func info(_ msg: @autoclosure () -> String) {
        let line = "[tamaclaude] \(msg())\n"
        FileHandle.standardError.write(Data(line.utf8))
        guard toFile else { return }
        lock.lock()
        defer { lock.unlock() }
        let url = Paths.log
        // ตัดทิ้งเมื่อโตเกิน 1MB — log ที่โตไม่หยุดคือปัญหาถัดไปที่ไม่อยากได้
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size]
            as? Int, size > 1 << 20 {
            try? FileManager.default.removeItem(at: url)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    public static func debug(_ msg: @autoclosure () -> String) {
        guard verbose else { return }
        info(msg())
    }
}
