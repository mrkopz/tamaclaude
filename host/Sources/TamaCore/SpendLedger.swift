import Foundation

/// ยอดเงินที่ Claude Code ใช้ไปในหน้าต่างเจ็ดวัน เทียบกับงบที่ผู้ใช้ตั้งไว้
///
/// มีไว้สำหรับบัญชีที่ auth ด้วย API key ของ Console ซึ่ง **ไม่มี `rate_limits`
/// มาให้เลย** (เอกสาร statusline ระบุว่า `rate_limits` มีเฉพาะผู้ใช้ Claude.ai
/// Pro/Max) แถบโควตาของคนกลุ่มนี้จึงว่างตลอดกาล ทั้งที่ payload เดียวกันพก
/// `cost.total_cost_usd` มาให้อยู่แล้วทุกงวด
///
/// **ตัวเลขนี้เราคำนวณเอง ไม่ใช่ค่าที่ Anthropic รายงานมา** ซึ่งขัดกับหลัก
/// "utilization is reported, never derived" ที่ใช้กับอีกสองทางเข้า — จึงมีกติกา
/// ข้อเดียวที่ห้ามพลาด: **ของจริงชนะเสมอ** ถ้า `rate_limits.seven_day` โผล่มา
/// เมื่อไร ค่าจากที่นี่ต้องไม่ถูกเขียนลงช่องนั้นอีก (ดู `UsageWriter.ingest`)
///
/// ## ทำไมเป็นรายสัปดาห์ ทั้งที่ผู้ใช้คิดเป็นรายเดือน
///
/// ความยาวหน้าต่างถูกคอมไพล์อยู่ในบอร์ด (`weekly_window = 604800` ใน
/// `tools/layout.toml`) และบอร์ดใช้มันคำนวณขีด pace เอง — snapshot ไม่ได้ส่ง
/// ความยาวไปด้วย ยัดหน้าต่างรายเดือนลงช่องนี้ = ขีด pace ค้างที่ 0 เกือบทั้งเดือน
/// เพราะ `elapsed = max(0, window - remaining)` ติดลบแล้วถูกปัดเป็นศูนย์
///
/// งบรายเดือนจึงถูกเฉลี่ยเป็นรายสัปดาห์ตามจำนวนวันจริงของเดือนนั้น สิ่งที่ได้คือ
/// **สัญญาณจังหวะการใช้ ไม่ใช่เพดานแข็ง** — ตรงกับความหมายที่ขีด pace วาดอยู่แล้ว
public enum SpendLedger {
    /// งบต่อเดือนเป็นดอลลาร์เมื่อผู้ใช้ไม่ได้ตั้งไว้
    ///
    /// ศูนย์ไม่ใช่ค่าเริ่มต้นที่ปลอดภัย: มันทำให้ทุกยอดกลายเป็น 100% ทันที
    /// ผู้ใช้ที่ไม่เคยตั้งงบจะเห็นแถบแดงเต็มโดยไม่รู้ว่ามาจากไหน
    public static let defaultMonthlyUSD = 3000.0

    /// เจ็ดวันเป็นวินาที — ต้องตรงกับ `UsageReader.weeklyWindow` และ
    /// `weekly_window` ใน `tools/layout.toml` ไม่งั้นขีด pace บนบอร์ดจะเพี้ยน
    static let window = TimeInterval(UsageReader.weeklyWindow)

    /// session ที่ไม่ถูกพบมานานกว่านี้ถูกตัดทิ้งตอนบันทึก — กันไฟล์โตไม่หยุด
    ///
    /// สองเท่าของหน้าต่าง ไม่ใช่หนึ่งเท่า: session ที่เปิดค้างข้ามสัปดาห์ต้องเก็บ
    /// `base` ของมันไว้ ไม่งั้นพอกลับมาใช้อีกครั้ง ยอดสะสมทั้งก้อนจะถูกนับใหม่
    static let staleAfter = window * 2

    /// ผลของการบันทึกหนึ่งครั้ง — พร้อมส่งเข้าช่อง weekly ของ cache
    public struct Reading: Equatable {
        public var percent: Int
        public var resetsAt: Date
        public var spentUSD: Double
        public var allowanceUSD: Double
    }

    /// บันทึกยอดของ session หนึ่ง แล้วคืนสถานะของหน้าต่างปัจจุบัน
    ///
    /// คืน `nil` เมื่อยังบอกอะไรไม่ได้ — งบเป็นศูนย์หรือติดลบ (ตั้งค่าพัง) ซึ่ง
    /// ต้องเงียบ ไม่ใช่เดาเป็น 0% หรือ 100%
    @discardableResult
    public static func record(
        sessionID: String,
        costUSD: Double,
        now: Date = Date(),
        monthlyUSD: Double? = nil,
        at url: URL = Paths.spendLedger,
        calendar: Calendar = .current
    ) -> Reading? {
        let budget = monthlyUSD ?? readBudget()
        guard budget > 0, costUSD >= 0, costUSD.isFinite else { return nil }

        var state = load(at: url)
        let start = windowStart(containing: now, calendar: calendar)

        // หน้าต่างหมุนแล้ว: ยก `latest` ของทุก session ขึ้นเป็น `base` ใหม่
        // ยอดที่ใช้ไปในสัปดาห์ก่อนจึงไม่ตามมาถูกนับซ้ำในสัปดาห์นี้
        if state.windowStart != start {
            state.windowStart = start
            for (id, entry) in state.sessions {
                state.sessions[id] = Entry(base: entry.latest, latest: entry.latest, seen: entry.seen)
            }
        }

        // `total_cost_usd` ของ session เดิมเพิ่มอย่างเดียว — ค่าที่ลดลงแปลว่า
        // Claude Code เริ่มนับใหม่ (เช่น `/clear` ที่ยัง id เดิม) ยึดค่าสูงสุดไว้
        // เป็นทางที่ปลอดภัยกว่าสำหรับสัญญาณเตือนงบ: นับเกินดีกว่านับขาด
        var entry = state.sessions[sessionID] ?? Entry(base: costUSD, latest: costUSD, seen: now)
        entry.latest = max(entry.latest, costUSD)
        entry.base = min(entry.base, entry.latest)
        entry.seen = now
        state.sessions[sessionID] = entry

        state.sessions = state.sessions.filter { now.timeIntervalSince($0.value.seen) < staleAfter }
        save(state, at: url)

        let spent = state.sessions.values.reduce(0.0) { $0 + max(0, $1.latest - $1.base) }
        let allowance = weeklyAllowance(monthlyUSD: budget, now: now, calendar: calendar)
        guard allowance > 0 else { return nil }

        // ปัดเป็นจำนวนเต็มและตัดที่ 100 — `UsageReader.snap` รับเฉพาะ 0...100
        // ค่าที่เกินจะถูกทิ้งทั้งบานแล้วกลายเป็น "ไม่รู้" ซึ่งแย่กว่า "เต็ม"
        let percent = min(100, max(0, Int((spent / allowance * 100).rounded())))
        return Reading(
            percent: percent,
            resetsAt: start.addingTimeInterval(window),
            spentUSD: spent,
            allowanceUSD: allowance)
    }

    /// งบของสัปดาห์นี้ = งบเดือน × 7 ÷ จำนวนวันจริงของเดือนนั้น
    ///
    /// หารด้วยจำนวนวันจริง ไม่ใช่ 30 หรือ 4.35 คงที่ — กุมภาพันธ์กับมกราคมให้
    /// ค่าไม่เท่ากัน และผู้ใช้ที่เอาไปเทียบกับบิลจะเจอส่วนต่างที่อธิบายไม่ได้
    static func weeklyAllowance(
        monthlyUSD: Double, now: Date, calendar: Calendar
    ) -> Double {
        let days = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        return monthlyUSD * 7.0 / Double(days)
    }

    /// ต้นสัปดาห์ที่หน้าต่างนี้เริ่ม — ตามปฏิทินของเครื่อง
    ///
    /// ยึดขอบสัปดาห์ของปฏิทิน ไม่ใช่ "เจ็ดวันนับจากครั้งแรกที่เห็น" เพราะขอบที่
    /// ลอยตามการใช้งานทำให้ผู้ใช้ตอบไม่ได้ว่าแถบจะรีเซ็ตเมื่อไร และเทียบกับ
    /// สัปดาห์ก่อนไม่ได้เลย
    static func windowStart(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    /// อ่านงบรายเดือนจากไฟล์ — ตัวเลขล้วน หน่วยดอลลาร์
    ///
    /// ไฟล์ที่อ่านไม่ออกคืนค่า default ไม่ใช่ศูนย์: การพิมพ์ผิดหนึ่งตัวไม่ควร
    /// ทำให้แถบหายไปเงียบๆ โดยไม่มีอะไรบอกว่าเกิดอะไรขึ้น
    public static func readBudget(at url: URL = Paths.budget) -> Double {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return defaultMonthlyUSD
        }
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned), value > 0, value.isFinite else {
            return defaultMonthlyUSD
        }
        return value
    }

    // MARK: - สถานะบนดิสก์

    struct Entry {
        var base: Double
        var latest: Double
        var seen: Date
    }

    struct State {
        var windowStart: Date
        var sessions: [String: Entry]
    }

    static func load(at url: URL) -> State {
        guard let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let start = (root["window_start"] as? NSNumber)?.doubleValue
        else { return State(windowStart: .distantPast, sessions: [:]) }

        var sessions: [String: Entry] = [:]
        for case let (id, raw as [String: Any]) in root["sessions"] as? [String: Any] ?? [:] {
            guard let base = (raw["base"] as? NSNumber)?.doubleValue,
                let latest = (raw["latest"] as? NSNumber)?.doubleValue,
                let seen = (raw["seen"] as? NSNumber)?.doubleValue
            else { continue }
            sessions[id] = Entry(
                base: base, latest: latest, seen: Date(timeIntervalSince1970: seen))
        }
        return State(windowStart: Date(timeIntervalSince1970: start), sessions: sessions)
    }

    static func save(_ state: State, at url: URL) {
        var sessions: [String: Any] = [:]
        for (id, entry) in state.sessions {
            sessions[id] = [
                "base": entry.base,
                "latest": entry.latest,
                "seen": entry.seen.timeIntervalSince1970,
            ]
        }
        let root: [String: Any] = [
            "window_start": state.windowStart.timeIntervalSince1970,
            "sessions": sessions,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        else { return }

        // temp + rename เหมือน `UsageWriter.write` — statusline ยิงพร้อมกันได้
        // หลาย session ใครอ่านเจอไฟล์ที่เขียนค้างครึ่งทางจะรีเซ็ตยอดทั้งสัปดาห์
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tamaclaude.tmp")
        guard (try? data.write(to: tmp, options: .atomic)) != nil else { return }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        try? FileManager.default.removeItem(at: tmp)
    }
}
