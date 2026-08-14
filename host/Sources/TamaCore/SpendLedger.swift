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

    /// หน้าต่างสั้น — ต้องตรงกับ `UsageReader.sessionWindow` และ `session_window`
    /// ใน `tools/layout.toml` ด้วยเหตุผลเดียวกับ `window`
    static let sessionWindow = TimeInterval(UsageReader.sessionWindow)

    /// สถานะของหน้าต่างหนึ่งบาน — พร้อมส่งเข้าช่องหนึ่งช่องของ cache
    public struct Reading: Equatable {
        public var percent: Int
        public var resetsAt: Date
        public var spentUSD: Double
        public var allowanceUSD: Double
    }

    /// ทั้งสองบานที่จอวาด — แถว "Current" กับแถว "Weekly"
    public struct Readings: Equatable {
        public var session: Reading
        public var weekly: Reading
    }

    /// บันทึกยอดของ session หนึ่ง แล้วคืนสถานะของทั้งสองหน้าต่าง
    ///
    /// คืน `nil` เมื่อยังบอกอะไรไม่ได้ — งบเป็นศูนย์หรือติดลบ (ตั้งค่าพัง) ซึ่ง
    /// ต้องเงียบ ไม่ใช่เดาเป็น 0% หรือ 100%
    @discardableResult
    public static func record(
        sessionID: String,
        costUSD: Double,
        reportsQuota: Bool = false,
        account: String? = nil,
        now: Date = Date(),
        monthlyUSD: Double? = nil,
        at url: URL = Paths.spendLedger,
        calendar: Calendar = .current
    ) -> Readings? {
        let budget = monthlyUSD ?? readBudget()
        guard budget > 0, costUSD >= 0, costUSD.isFinite else { return nil }

        var state = load(at: url)
        let start = windowStart(containing: now, calendar: calendar)

        // หน้าต่างหมุนแล้ว: ยก `latest` ของทุก session ขึ้นเป็นฐานใหม่ของบานนั้น
        // ยอดที่ใช้ไปในหน้าต่างก่อนจึงไม่ตามมาถูกนับซ้ำในหน้าต่างนี้
        //
        // ต้องหมุน **ก่อน** รับค่าใหม่เข้า `latest` ไม่งั้นเงินที่เพิ่งใช้ในหน้าต่างใหม่
        // จะถูกยกขึ้นเป็นฐานไปด้วย แล้วหายไปจากยอดทั้งที่เพิ่งจ่าย
        if state.windowStart != start {
            state.windowStart = start
            for (id, entry) in state.sessions { state.sessions[id]?.base = entry.latest }
        }
        // หน้าต่างสั้นเกาะกิจกรรม ไม่ใช่เกาะปฏิทิน — มันเริ่มนับเมื่อมีการใช้ครั้งแรก
        // หลังบานก่อนหมดอายุ เหมือนหน้าต่าง 5 ชั่วโมงจริงของ Claude ถ้าไปยึดขอบ
        // ปฏิทิน (เช่นทุก 5 ชม.นับจากเที่ยงคืน) 24 หารด้วย 5 ไม่ลงตัว บานสุดท้าย
        // ของวันจะสั้นกว่าเพื่อน แล้วขีด pace ของบานนั้นจะโกหก
        if now.timeIntervalSince(state.sessionStart) >= sessionWindow {
            state.sessionStart = now
            for (id, entry) in state.sessions { state.sessions[id]?.sessionBase = entry.latest }
        }

        // `total_cost_usd` ของ session เดิมเพิ่มอย่างเดียว — ค่าที่ลดลงแปลว่า
        // Claude Code เริ่มนับใหม่ (เช่น `/clear` ที่ยัง id เดิม) ยึดค่าสูงสุดไว้
        // เป็นทางที่ปลอดภัยกว่าสำหรับสัญญาณเตือนงบ: นับเกินดีกว่านับขาด
        var entry = state.sessions[sessionID]
            ?? Entry(base: costUSD, sessionBase: costUSD, latest: costUSD, seen: now)
        entry.latest = max(entry.latest, costUSD)
        entry.base = min(entry.base, entry.latest)
        entry.sessionBase = min(entry.sessionBase, entry.latest)
        entry.seen = now
        entry.subscription = entry.subscription || reportsQuota
        // ป้ายล่าสุดชนะ — ผู้ใช้ย้าย session ระหว่างบัญชีไม่ได้ แต่การติดตั้งใหม่
        // เปลี่ยนชื่อได้ และค่าที่ใหม่กว่าคือค่าที่ตรงกับสิ่งที่อยู่บนดิสก์ตอนนี้
        if let account { entry.account = account }
        state.sessions[sessionID] = entry

        state.sessions = state.sessions.filter { now.timeIntervalSince($0.value.seen) < staleAfter }
        save(state, at: url)

        return readings(of: state, budget: budget, now: now, calendar: calendar)
    }

    /// สถานะปัจจุบันโดยไม่บันทึกอะไรเลย — เส้นทางอ่านล้วน
    ///
    /// มีไว้ให้ `UsageReader` เรียกตอนที่ cache ไม่มีค่างบให้ ledger คือแหล่งจริง
    /// ของตัวเลขนี้ ส่วน cache เป็นแค่ตัวกลางที่ statusline เขียนผ่าน — ผูกการแสดงผล
    /// ไว้กับตัวกลางแปลว่าลบ cache ทีเดียวแล้วแถบหายจนกว่า statusline จะยอมยิงอีก
    /// ซึ่งบน surface บางแบบคือนานมาก
    ///
    /// **ต้องไม่เขียนไฟล์** — ถูกเรียกจากรอบ publish ของ daemon ซึ่งเกิดบ่อยกว่า
    /// การใช้งานจริงหลายเท่า การเขียนทุกรอบจะเปลี่ยนหน้าต่างห้าชั่วโมงที่เกาะกิจกรรม
    /// ให้กลายเป็นหน้าต่างที่เลื่อนตามการวาดจอ ซึ่งไม่มีความหมายอะไรเลย
    public static func current(
        now: Date = Date(),
        monthlyUSD: Double? = nil,
        at url: URL = Paths.spendLedger,
        calendar: Calendar = .current
    ) -> Readings? {
        let budget = monthlyUSD ?? readBudget()
        guard budget > 0 else { return nil }
        let state = load(at: url)
        guard !state.sessions.isEmpty else { return nil }

        // หน้าต่างที่หมดอายุแล้วต้องรายงานเป็นบานใหม่ที่ยอดเป็นศูนย์ ไม่ใช่ยอดค้าง
        // ของบานก่อน — แต่ไม่บันทึกลงดิสก์ รอให้ `record` ทำตอนมีการใช้จริง
        var view = state
        let start = windowStart(containing: now, calendar: calendar)
        if view.windowStart != start {
            view.windowStart = start
            for (id, e) in view.sessions { view.sessions[id]?.base = e.latest }
        }
        if now.timeIntervalSince(view.sessionStart) >= sessionWindow {
            view.sessionStart = now
            for (id, e) in view.sessions { view.sessions[id]?.sessionBase = e.latest }
        }
        return readings(of: view, budget: budget, now: now, calendar: calendar)
    }

    /// แปลงสถานะเป็นสองแถวที่จอวาด — เจ้าของสูตรที่เดียว ทั้งเส้นทางอ่านและเขียน
    static func readings(
        of state: State, budget: Double, now: Date, calendar: Calendar
    ) -> Readings? {
        let days = Double(calendar.range(of: .day, in: .month, for: now)?.count ?? 30)
        // นับเฉพาะ session ที่จ่ายตาม token จริง — `total_cost_usd` ของ session ที่
        // อยู่ในโควตา subscription เป็นตัวเลขสมมติว่า "ถ้าจ่ายรายทางจะเท่านี้"
        // ผู้ใช้ไม่ได้จ่ายมันจริง การเอามารวมในงบที่ตั้งไว้คุมเงินจริงคือการปนสอง
        // สกุลเงินที่ไม่เท่ากันเข้าด้วยกัน แล้วแถบจะสูงกว่าความจริงตลอด
        let allowed = allowedAccounts()
        let metered = state.sessions.values.filter {
            guard !$0.subscription else { return false }
            // ไม่มีรายชื่อ = นับหมด · มีรายชื่อ = นับเฉพาะที่อยู่ในนั้น
            // session ที่ยังไม่มีป้าย (บันทึกไว้ก่อนมีฟีเจอร์นี้) ถือว่าไม่อยู่ในรายชื่อ
            guard let allowed else { return true }
            return $0.account.map(allowed.contains) ?? false
        }
        let weekly = reading(
            spent: metered.reduce(0.0) { $0 + max(0, $1.latest - $1.base) },
            allowance: budget * 7.0 / days,
            resetsAt: state.windowStart.addingTimeInterval(window))
        let session = reading(
            spent: metered.reduce(0.0) { $0 + max(0, $1.latest - $1.sessionBase) },
            allowance: budget * (sessionWindow / 86_400) / days,
            resetsAt: state.sessionStart.addingTimeInterval(sessionWindow))

        guard let weekly, let session else { return nil }
        return Readings(session: session, weekly: weekly)
    }

    /// เปอร์เซ็นต์ที่ `UsageReader.snap` รับได้ — ปัดเป็นจำนวนเต็มและตัดที่ 100
    ///
    /// ค่าที่เกิน 100 จะถูก `snap` ทิ้งทั้งบานแล้วกลายเป็น "ไม่รู้" ซึ่งแย่กว่า
    /// "เต็ม" มาก: คนที่ใช้เกินงบต้องเห็นแถบแดงเต็ม ไม่ใช่แถบว่าง
    static func reading(spent: Double, allowance: Double, resetsAt: Date) -> Reading? {
        guard allowance > 0 else { return nil }
        return Reading(
            percent: min(100, max(0, Int((spent / allowance * 100).rounded()))),
            resetsAt: resetsAt,
            spentUSD: spent,
            allowanceUSD: allowance)
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

    /// บัญชีที่งบจะนับ — `nil` แปลว่าไม่ได้จำกัด ไม่ใช่ "ไม่มีสักบัญชี"
    ///
    /// ไฟล์ว่างเปล่าก็คืน `nil` ด้วย: คนที่สร้างไฟล์แล้วยังไม่ได้พิมพ์อะไรลงไป
    /// ไม่ได้ตั้งใจจะปิดแถบทั้งอัน
    public static func allowedAccounts(at url: URL = Paths.budgetAccounts) -> Set<String>? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let names = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return names.isEmpty ? nil : Set(names)
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

    /// ฐานสองตัวต่อหนึ่ง session เพราะสองหน้าต่างหมุนคนละจังหวะ — `base` เป็นของ
    /// สัปดาห์ `sessionBase` เป็นของบาน 5 ชั่วโมง ส่วน `latest` ใช้ร่วมกัน
    struct Entry {
        var base: Double
        var sessionBase: Double
        var latest: Double
        var seen: Date
        /// session นี้เคยส่ง `rate_limits` มาไหม — คือมัน auth ด้วย subscription
        ///
        /// **ติดแล้วติดเลย** เพราะ `rate_limits` โผล่หลัง API response แรกเท่านั้น
        /// การ render รอบแรกๆ ของ session subscription จึงหน้าตาเหมือน API key
        /// ถ้าไม่จำไว้ มันจะสลับไปมาแล้วยอดเงินกระพริบตาม
        var subscription: Bool = false
        /// บัญชีที่ session นี้มาจาก — ชื่อ config dir ที่ตัวติดตั้งฝังไว้ในสคริปต์
        var account: String? = nil
    }

    struct State {
        var windowStart: Date
        var sessionStart: Date
        var sessions: [String: Entry]
    }

    static func load(at url: URL) -> State {
        let empty = State(windowStart: .distantPast, sessionStart: .distantPast, sessions: [:])
        guard let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let start = (root["window_start"] as? NSNumber)?.doubleValue
        else { return empty }

        var sessions: [String: Entry] = [:]
        for case let (id, raw as [String: Any]) in root["sessions"] as? [String: Any] ?? [:] {
            guard let base = (raw["base"] as? NSNumber)?.doubleValue,
                let latest = (raw["latest"] as? NSNumber)?.doubleValue,
                let seen = (raw["seen"] as? NSNumber)?.doubleValue
            else { continue }
            // ไฟล์ที่เขียนไว้ก่อนมีบาน 5 ชั่วโมงไม่มี `session_base` — ถือว่าเท่ากับ
            // `latest` คือเริ่มนับบานสั้นใหม่จากตรงนี้ ไม่ใช่ยกยอดทั้งสัปดาห์มาใส่
            let sessionBase = (raw["session_base"] as? NSNumber)?.doubleValue ?? latest
            sessions[id] = Entry(
                base: base, sessionBase: sessionBase, latest: latest,
                seen: Date(timeIntervalSince1970: seen),
                subscription: (raw["subscription"] as? NSNumber)?.boolValue ?? false,
                account: raw["account"] as? String)
        }
        return State(
            windowStart: Date(timeIntervalSince1970: start),
            sessionStart: Date(
                timeIntervalSince1970: (root["session_start"] as? NSNumber)?.doubleValue ?? 0),
            sessions: sessions)
    }

    static func save(_ state: State, at url: URL) {
        var sessions: [String: Any] = [:]
        for (id, entry) in state.sessions {
            sessions[id] = [
                "base": entry.base,
                "session_base": entry.sessionBase,
                "latest": entry.latest,
                "seen": entry.seen.timeIntervalSince1970,
                "subscription": entry.subscription,
                "account": entry.account as Any,
            ].compactMapValues { $0 is NSNull ? nil : $0 }
        }
        let root: [String: Any] = [
            "window_start": state.windowStart.timeIntervalSince1970,
            "session_start": state.sessionStart.timeIntervalSince1970,
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
