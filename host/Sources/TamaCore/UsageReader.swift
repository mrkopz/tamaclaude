import Foundation

/// อ่าน utilization ของโควตาจาก cache ที่ statusline เขียนไว้
///
/// daemon ไม่เคยยิงเน็ตเองและไม่เคยถือ credential — ตัวเลขทั้งหมดมาจาก `rate_limits`
/// ที่ Claude Code ป้อนเข้า stdin ของ statusline แล้ว statusline เขียนลงไฟล์นี้
///
/// รูปแบบไฟล์เป็น KEY=VALUE บรรทัดละคีย์ ตามที่ Claude Usage.app ใช้อยู่เดิม
/// (คีย์เดียวกัน เวลาเป็น ISO8601 เหมือนกัน) ทั้งสองฝ่ายจึงเขียนไฟล์เดียวกันได้
/// โดยไม่ขัดกัน — ความหมายตรงกัน ใครเขียนทีหลังก็ถูก
///
/// **ไม่มี TTL** — เปอร์เซ็นต์จะขยับได้ก็ต่อเมื่อผู้ใช้เรียก Claude ดังนั้นค่าที่เก่า
/// *คือ* ค่าที่ถูก สิ่งเดียวที่ทำให้มันหมดอายุคือ `resets_at` ที่ผ่านไปแล้ว
/// ซึ่งเป็นเส้นตายจริงในโดเมนนี้ ไม่ต้องเดาด้วยเลขวิเศษ
public enum UsageReader {
    /// ความยาวหน้าต่างเป็นวินาที — ต้องตรงกับ `[usage]` ใน tools/layout.toml
    public static let sessionWindow = 18_000  // 5 ชั่วโมง
    public static let weeklyWindow = 604_800  // 7 วัน

    /// อ่านแล้วแปลงเป็น `[session, weekly]` พร้อมส่งขึ้นบอร์ด
    ///
    /// คืน `nil` เมื่อไม่มีอะไรจะบอกเลย (ไฟล์หาย/อ่านไม่ได้/ไม่มีคีย์ที่รู้จักสักตัว)
    /// ซึ่งบอร์ดตีความว่าให้กลับไปเป็นนาฬิกา — โครงเปล่าดูเหมือนอุปกรณ์พัง
    public static func read(now: Date = Date(), from url: URL = Paths.usageCache) -> [UsageSnap]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let fields = parse(text)

        let session = snap(
            percent: fields["UTILIZATION"], resets: fields["RESETS_AT"], now: now)
        // ช่องรายสัปดาห์มีผู้สมัครสองราย และ **ของจริงชนะเสมอ**
        //
        // `WEEKLY_*` คือโควตาที่ Anthropic รายงานมา ส่วน `BUDGET_*` คือยอดเงินที่
        // เราหารด้วยงบของผู้ใช้เอง (ดู `SpendLedger`) การเลือกอยู่ที่นี่ที่เดียว
        // ไม่ใช่ตอนเขียน เพราะไฟล์นี้มีผู้เขียนหลายราย: session ที่ auth ด้วย
        // subscription เขียน `WEEKLY_*` ส่วน session ที่ auth ด้วย API key เขียน
        // `BUDGET_*` และทั้งคู่ทำงานสลับกันบนเครื่องเดียวกันได้ ถ้าตัดสินตอนเขียน
        // แถบจะสลับความหมายตามว่าใครวาดทีหลัง — ตรงนี้เห็นทั้งสองคีย์พร้อมกัน
        let keys = weeklyKeys(fields, now: now)
        let weekly = snap(percent: fields[keys.percent], resets: fields[keys.resets], now: now)

        guard session.isKnown || weekly.isKnown else { return nil }
        return [session, weekly]
    }

    /// ช่องรายสัปดาห์ควรอ่านจากคีย์ชุดไหน — **เจ้าของกฎ "ของจริงชนะเสมอ" ที่เดียว**
    ///
    /// `WEEKLY_*` คือโควตาที่ Anthropic รายงานมา ส่วน `BUDGET_*` คือยอดเงินที่เรา
    /// หารด้วยงบของผู้ใช้เอง (ดู `SpendLedger`) — คนละคำกล่าวอ้างกันโดยสิ้นเชิง
    /// ADR ของโปรเจกต์ยืนว่า utilization is reported, never derived ค่าที่เรา
    /// คำนวณเองจึงเข้าได้เฉพาะตอนที่ไม่มีค่าที่รายงานมาให้ใช้
    ///
    /// การเลือกอยู่ตอน *อ่าน* ไม่ใช่ตอนเขียน เพราะไฟล์ cache มีผู้เขียนหลายราย:
    /// session ที่ auth ด้วย subscription เขียน `WEEKLY_*` ส่วน session ที่ auth
    /// ด้วย API key เขียน `BUDGET_*` ผู้ใช้คนเดียวเปิดทั้งสองแบบพร้อมกันได้ ถ้า
    /// ตัดสินตอนเขียน แถบจะสลับความหมายตามว่า session ไหนวาดทีหลัง
    ///
    /// "ไม่มีค่าที่รายงานมาให้ใช้" รวมถึงหน้าต่างที่หมุนไปแล้วโดยยังไม่มีใครอัปเดต
    /// cache — `snap` ถือว่าเปอร์เซ็นต์ของหน้าต่างแบบนั้นคือ "ไม่รู้" อยู่แล้ว
    public static func weeklyKeys(
        _ fields: [String: String], now: Date
    ) -> (percent: String, resets: String) {
        let reported = ("WEEKLY_UTILIZATION", "WEEKLY_RESETS_AT")
        let derived = ("BUDGET_UTILIZATION", "BUDGET_RESETS_AT")
        let usable = snap(
            percent: fields[reported.0], resets: fields[reported.1], now: now
        ).percent != UsageSnap.unknown
        return usable ? reported : derived
    }

    /// เวลาในหน้าต่างเดินไปกี่เปอร์เซ็นต์แล้ว — ตำแหน่งของขีด pace
    ///
    /// อยู่ที่นี่เพราะที่นี่เป็นเจ้าของความยาวหน้าต่าง และเพราะแบดจ์บนแถบเมนูกับการ์ด
    /// ใน popover ต้องได้ตัวเลขเดียวกันเสมอ — สองสูตรที่เขียนแยกกันจะเพี้ยนกันวันหนึ่ง
    ///
    /// การหารลงพื้นไม่ทำให้เกณฑ์เพี้ยน: `percent > floor(pace)` ให้ผลเดียวกับ
    /// `percent * window > elapsed * 100` ทุกกรณี เพราะ percent เป็นจำนวนเต็ม
    public static func elapsedPercent(remaining: Int, window: Int) -> Int {
        guard remaining != UsageSnap.unknown, window > 0 else { return UsageSnap.unknown }
        // countdown ที่ยาวกว่าหน้าต่างแปลว่านาฬิกาสองฝั่งไม่ตรงกัน ไม่ใช่ว่าเวลาเดินถอยหลัง
        let elapsed = min(window, max(0, window - remaining))
        return elapsed * 100 / window
    }

    /// เวลาที่ cache ถูกเขียนครั้งล่าสุด — คนละเรื่องกับ `resets_at` ของหน้าต่าง
    ///
    /// ใช้ตอบคำถาม "ค่านี้อายุเท่าไร" ซึ่งเป็นคนละคำถามกับ "ท่อยังเดินอยู่ไหม" ค่าที่
    /// เก่ายังถูกได้ (เปอร์เซ็นต์ขยับก็ต่อเมื่อมีการเรียก Claude) แต่ผู้ใช้ควรรู้ว่าเก่าแค่ไหน
    public static func stamp(from url: URL = Paths.usageCache) -> Date? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
            let raw = parse(text)["TIMESTAMP"], let seconds = TimeInterval(raw)
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eq])
            let value = String(line[line.index(after: eq)...])
                .trimmingCharacters(in: .whitespaces)
            // ค่าว่างนับเป็น "ไม่มีคีย์" — ไฟล์ที่เขียนครึ่งๆ ต้องไม่กลายเป็น 0%
            if !value.isEmpty { out[key] = value }
        }
        return out
    }

    /// เปอร์เซ็นต์และเวลาหายไปทีละตัวได้ — เอกสารระบุว่าแต่ละหน้าต่างอาจไม่มีมาอิสระกัน
    static func snap(percent: String?, resets: String?, now: Date) -> UsageSnap {
        var snap = UsageSnap()
        if let percent, let value = Int(percent), (0...100).contains(value) {
            snap.percent = value
        }
        if let resets, let date = parseISO(resets) {
            let raw = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
            // ปัดลงเป็นนาที — บอร์ดนับถอยลงเอง ค่าที่ส่งจึงไม่ควรเปลี่ยนทุกวินาที
            // ไม่งั้น snapshot ต่างกันทุก tick แล้ว BLE โดนยิงวินาทีละครั้ง
            // ที่ความละเอียดนาที มันเปลี่ยนพร้อมกับนาฬิกา `c` ซึ่งยิงอยู่แล้ว = ไม่มีของเพิ่ม
            snap.remaining = raw > 0 ? max(60, raw / 60 * 60) : 0
        }
        // หน้าต่างหมุนไปแล้วโดยที่ยังไม่มีใครอัปเดต cache: เปอร์เซ็นต์ที่ถืออยู่ผิดแน่นอน
        // ตัวเลขที่ถูกคือ "ไม่รู้" ไม่ใช่ 0 — ห้ามเดา
        if snap.remaining == 0 { snap.percent = UsageSnap.unknown }
        return snap
    }

    static func parseISO(_ s: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
