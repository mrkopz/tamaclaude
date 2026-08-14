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
    public static func read(
        now: Date = Date(), from url: URL = Paths.usageCache,
        ledger: URL = Paths.spendLedger, accounts: URL = Paths.budgetAccounts,
        calendar: Calendar = .current
    ) -> [UsageSnap]? {
        var fields = (try? String(contentsOf: url, encoding: .utf8)).map(parse) ?? [:]
        fillBudget(&fields, now: now, ledger: ledger, accounts: accounts, calendar: calendar)

        let sKeys = sessionKeys(fields, now: now)
        let session = snap(percent: fields[sKeys.percent], resets: fields[sKeys.resets], now: now)
        let keys = weeklyKeys(fields, now: now)
        let weekly = snap(percent: fields[keys.percent], resets: fields[keys.resets], now: now)

        guard session.isKnown || weekly.isKnown else { return nil }
        return [session, weekly]
    }

    /// เติมค่างบจาก `SpendLedger` เมื่อ cache ไม่มีค่าที่ใช้ได้ให้
    ///
    /// cache เป็น **ตัวกลาง** ไม่ใช่แหล่งข้อมูลของงบ — statusline เป็นตัวเดียวที่
    /// เขียนมัน และมันยิงไม่สม่ำเสมอบน surface บางแบบ ผูกการแสดงผลไว้กับตัวกลาง
    /// แปลว่าลบไฟล์ทีเดียวแล้วแถบหายจนกว่า statusline จะยอมยิงอีก ทั้งที่ยอดเงิน
    /// ยังอยู่ครบใน ledger
    ///
    /// เติมเฉพาะช่องที่ว่างหรือหมดอายุ ไม่ทับของที่ใช้ได้อยู่ — กติกา "ห้ามถอยหลัง"
    /// ของ `UsageWriter.merge` ทำงานบน cache และต้องไม่ถูกลัดผ่าน
    ///
    /// ไม่แตะคีย์ของโควตาที่รายงานมา ตรงนั้นไม่มีทางเดาจาก ledger ได้เลย
    static func fillBudget(
        _ fields: inout [String: String], now: Date, ledger: URL, accounts: URL,
        calendar: Calendar
    ) {
        let pairs = [("BUDGET_UTILIZATION", "BUDGET_RESETS_AT"),
                     ("BUDGET_WEEKLY_UTILIZATION", "BUDGET_WEEKLY_RESETS_AT")]
        let missing = pairs.contains { pct, reset in
            snap(percent: fields[pct], resets: fields[reset], now: now).percent
                == UsageSnap.unknown
        }
        guard missing,
            let readings = SpendLedger.current(
                now: now, at: ledger, accounts: accounts, calendar: calendar)
        else { return }

        for (reading, pair) in zip([readings.session, readings.weekly], pairs) {
            guard snap(percent: fields[pair.0], resets: fields[pair.1], now: now).percent
                == UsageSnap.unknown
            else { continue }
            fields[pair.0] = String(reading.percent)
            fields[pair.1] = UsageWriter.iso(reading.resetsAt)
        }
    }

    /// # จอมีสองแถว บัญชีมีสองใบ — แถวละใบ
    ///
    /// เครื่องเดียวรันได้ทั้ง session ที่ auth ด้วย subscription (เขียน `UTILIZATION`
    /// / `WEEKLY_*` ที่ Anthropic รายงานมา) และ session ที่ auth ด้วย API key ของ
    /// Console (เขียน `BUDGET_*` ที่เราหารเอง — ดู `SpendLedger`) ถ้าทั้งสองแถวยึด
    /// กฎเดียวกันว่า "ของที่รายงานมาชนะ" บัญชีที่มี subscription จะกินทั้งสองแถว
    /// แล้วเจ้าของเครื่องมองไม่เห็นเลยว่างานฝั่งบริษัทใช้ไปเท่าไร
    ///
    /// แต่ละแถวจึงมี **ลำดับความสำคัญของตัวเอง** ไม่ใช่กฎกลางข้อเดียว:
    ///
    /// | แถว | ป้ายบนจอ | ตัวเลือกแรก | ตัวสำรอง |
    /// |:--|:--|:--|:--|
    /// | 0 | Current | โควตา 5 ชม. ที่รายงานมา | งบ 5 ชม. |
    /// | 1 | Weekly | งบรายสัปดาห์ | โควตา 7 วันที่รายงานมา |
    ///
    /// การจับคู่แบบนี้ทำให้ **ป้ายที่คอมไพล์ไว้ในเฟิร์มแวร์ยังพูดความจริง**: แถว 0
    /// เป็นหน้าต่างห้าชั่วโมงจริง แถว 1 เป็นหน้าต่างเจ็ดวันจริง ขีด pace ของทั้งคู่
    /// จึงคำนวณถูกโดยไม่ต้องแตะเฟิร์มแวร์ สิ่งที่จอบอกไม่ได้คือ *แถวไหนของบัญชีไหน* —
    /// บรรทัด statusline บอกแทนด้วยป้าย `Usage:` กับ `Budget:` (ดู `StatuslineRender`)
    ///
    /// ไม่ขัดกับ ADR "utilization is reported, never derived" — ตรงนั้นห้าม *กุ*
    /// ตัวเลขขึ้นมาเองเมื่อไม่มีของจริง ที่นี่มีของจริงสองก้อนคนละบัญชี แล้วเลือกว่า
    /// ช่องไหนโชว์ก้อนไหน ไม่มีอะไรถูกเดาขึ้นมา
    ///
    /// การเลือกอยู่ตอน *อ่าน* ไม่ใช่ตอนเขียน เพราะ cache มีผู้เขียนหลายราย ถ้าตัดสิน
    /// ตอนเขียน แถบจะสลับความหมายตามว่า session ไหนวาดทีหลัง
    ///
    /// "ใช้ไม่ได้" รวมถึงหน้าต่างที่หมุนไปแล้วโดยยังไม่มีใครอัปเดต cache — `snap`
    /// ถือว่าเปอร์เซ็นต์ของหน้าต่างแบบนั้นคือ "ไม่รู้" อยู่แล้ว
    public static func weeklyKeys(
        _ fields: [String: String], now: Date
    ) -> (percent: String, resets: String) {
        keys(
            fields, now: now,
            first: ("BUDGET_WEEKLY_UTILIZATION", "BUDGET_WEEKLY_RESETS_AT"),
            second: ("WEEKLY_UTILIZATION", "WEEKLY_RESETS_AT"))
    }

    /// ช่อง 5 ชั่วโมง (แถว "Current") — ของที่รายงานมาก่อน ดูตารางใน `weeklyKeys`
    public static func sessionKeys(
        _ fields: [String: String], now: Date
    ) -> (percent: String, resets: String) {
        keys(
            fields, now: now,
            first: ("UTILIZATION", "RESETS_AT"),
            second: ("BUDGET_UTILIZATION", "BUDGET_RESETS_AT"))
    }

    static func keys(
        _ fields: [String: String], now: Date,
        first: (String, String), second: (String, String)
    ) -> (percent: String, resets: String) {
        func usable(_ pair: (String, String)) -> Bool {
            snap(percent: fields[pair.0], resets: fields[pair.1], now: now)
                .percent != UsageSnap.unknown
        }
        if usable(first) { return first }
        // ตกมาตัวสำรองก็ต่อเมื่อมันมีอะไรให้จริงๆ — ไม่งั้นหน้าต่างที่เพิ่งหมุนจะเสีย
        // สถานะ "resetting" (เปอร์เซ็นต์ไม่รู้ แต่ `remaining == 0` ยังบอกอะไรได้)
        // แล้วทั้งแถวหายไปจากจอ กลายเป็นนาฬิกาแทน ซึ่งดูเหมือนอุปกรณ์พัง
        return usable(second) ? second : first
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

    /// เปิดให้ `--usage-print` เรียกได้ — ตัวไล่ปัญหาต้องเห็นสิ่งที่ตัวอ่านเห็น
    public static func parseForDiagnostics(_ text: String) -> [String: String] { parse(text) }

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
