import Foundation

/// การ์ดโควตาหนึ่งใบใน popover — ทุกอย่างที่ต้องวาด ยกเว้นวิธีวาด
///
/// อยู่ใน TamaCore ด้วยเหตุผลเดียวกับ `PanelText`: กฎว่าสีไหนขึ้นเมื่อไร ขีด pace
/// อยู่ตรงไหน และเวลารีเซ็ตอ่านว่าอะไร เป็นตรรกะล้วนที่เทสต์ได้บนเครื่องที่ไม่มีจอ
/// ส่วนที่เหลือ (`QuotaCardView`) เหลือแค่ "เอาค่าพวกนี้ไปวาด"
///
/// ภาษาภาพเดียวกับแผงบนบอร์ด — เกณฑ์สีและสูตร pace ต้องตรงกับ `usage_bar_color`
/// ใน `tools/gen/screen.py` และ `firmware/main/ct_ui.c`
public struct QuotaCard: Equatable, Sendable {
    /// ระดับที่สีอ่านออกมาได้ — ไม่ใช่ `NSColor` เพราะ TamaCore ไม่รู้จัก AppKit
    /// และเพราะ "ระดับ" คือสิ่งที่เทสต์ได้ ส่วน "สี" คือการตีความของมัน
    public enum Level: String, Sendable {
        case unknown, good, warn, crit
    }

    /// เกณฑ์สามขั้น — ต้องตรงกับ `warn_pct` / `crit_pct` ใน `tools/layout.toml`
    public static let warnPct = 60
    public static let critPct = 85

    /// ชื่อหน้าต่าง — สิ่งที่ตอบว่า "นี่คือโควตาก้อนไหน"
    public var title: String
    /// คำอธิบายสั้น — ตอบว่าหน้าต่างนี้นับอะไร ซึ่งชื่ออย่างเดียวไม่ได้บอก
    public var subtitle: String
    /// `UsageSnap.unknown` = ไม่รู้ ซึ่งไม่ใช่ศูนย์ (ADR-0001)
    public var percent: Int
    /// เวลาในหน้าต่างเดินไปกี่เปอร์เซ็นต์ = ตำแหน่งของขีดบนแถบ
    public var pace: Int
    public var level: Level
    /// ทั้งแบบสัมพัทธ์และสัมบูรณ์ในบรรทัดเดียว เช่น `Resets in 2h24m (Today 23:00)`
    public var reset: String

    public init(
        title: String, subtitle: String, percent: Int, pace: Int, level: Level, reset: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.percent = percent
        self.pace = pace
        self.level = level
        self.reset = reset
    }

    /// `[session, weekly]` — คืน `nil` เมื่อไม่มีอะไรจะบอกเลยทั้งสองหน้าต่าง
    ///
    /// การ์ดเปล่าสองใบอ่านได้ว่าอุปกรณ์พัง ทั้งที่ความจริงคือยังไม่เคยมีตัวเลขมาถึง
    /// หลักเดียวกับ "ไม่รู้โควตา → ไอคอนเดิม" บนแถบเมนู และ "ไม่เคยมีข้อมูล →
    /// ซ่อนแผงทั้งอัน" บนบอร์ด
    public static func cards(
        _ usage: [UsageSnap]?, now: Date = Date(), calendar: Calendar = .current
    ) -> [QuotaCard]? {
        guard let usage, usage.contains(where: \.isKnown) else { return nil }
        let session = usage.count > 0 ? usage[0] : UsageSnap()
        let weekly = usage.count > 1 ? usage[1] : UsageSnap()
        return [
            card(
                session, title: "Session", subtitle: "5 hour window",
                window: UsageReader.sessionWindow, now: now, calendar: calendar),
            card(
                weekly, title: "Weekly", subtitle: "All usage on the account",
                window: UsageReader.weeklyWindow, now: now, calendar: calendar),
        ]
    }

    static func card(
        _ snap: UsageSnap, title: String, subtitle: String, window: Int, now: Date,
        calendar: Calendar
    ) -> QuotaCard {
        let pace = UsageReader.elapsedPercent(remaining: snap.remaining, window: window)
        return QuotaCard(
            title: title, subtitle: subtitle, percent: snap.percent, pace: pace,
            level: level(percent: snap.percent, pace: pace),
            reset: resetLine(remaining: snap.remaining, now: now, calendar: calendar))
    }

    /// แดงทันทีที่ใช้เร็วกว่า pace ไม่ต้องรอถึง 85 — "60% ตอนเหลือเวลาอีกครึ่ง"
    /// เป็นปัญหาคนละแบบกับ "60% ตอนหมดเวลาพอดี" ส่วนเกณฑ์เปอร์เซ็นต์ยังอยู่ครบ
    /// เพราะการ์ดไล่สีสามขั้นได้ (ต่างจากแถบเมนูที่มีสองสถานะ ดู `MenuBadge`)
    public static func level(percent: Int, pace: Int) -> Level {
        guard percent != UsageSnap.unknown else { return .unknown }
        if pace != UsageSnap.unknown && percent > pace { return .crit }
        if percent >= critPct { return .crit }
        if percent >= warnPct { return .warn }
        return .good
    }

    /// สัมพัทธ์ตอบ "อีกนานไหม" สัมบูรณ์ตอบ "ตอนนั้นคือเมื่อไรของวัน" — คนละคำถาม
    /// และคำตอบของอันหลังคือสิ่งที่วางแผนงานต่อได้จริง
    public static func resetLine(remaining: Int, now: Date, calendar: Calendar) -> String {
        guard remaining != UsageSnap.unknown else { return "No reset time yet" }
        // ศูนย์ = หน้าต่างหมุนไปแล้วและเรายังไม่รู้ค่าใหม่ ไม่ใช่ "อีก 0 นาที"
        guard remaining > 0 else { return "Resetting now" }
        let at = now.addingTimeInterval(TimeInterval(remaining))
        return "Resets in \(shortSpan(remaining)) (\(clock(at, now: now, calendar: calendar)))"
    }

    /// ความละเอียดลดลงตามระยะ เหมือน `fmt_remaining` บนบอร์ด — วินาทีไม่เคยเปลี่ยน
    /// การตัดสินใจ และหน่วยที่สามทำให้บรรทัดยาวโดยไม่บอกอะไรเพิ่ม
    static func shortSpan(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return "\(hours)h\(String(format: "%02d", minutes))m" }
        // ต่ำกว่าหนึ่งนาทีปัดขึ้นเป็น 1m ไม่ใช่ 0m — "0m" อ่านเหมือนหมดแล้ว
        return "\(max(1, minutes))m"
    }

    /// วันนี้/พรุ่งนี้เรียกด้วยชื่อ ไกลกว่านั้นใช้ชื่อวัน แล้วค่อยเป็นวันที่เต็ม
    ///
    /// weekly รีเซ็ตได้ไกลถึงเจ็ดวัน ซึ่ง "Today/Tomorrow" ตอบไม่ได้ และ `23:00`
    /// เปล่าๆ ของวันที่ไม่รู้ว่าวันไหนคือเวลาที่อ่านผิดได้ทั้งบรรทัด
    static func clock(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = formatter("HH:mm", calendar: calendar).string(from: date)
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
        ).day ?? 0
        switch days {
        case ...0: return "Today \(time)"
        case 1: return "Tomorrow \(time)"
        case 2...6: return "\(formatter("EEE", calendar: calendar).string(from: date)) \(time)"
        default: return "\(formatter("d MMM", calendar: calendar).string(from: date)) \(time)"
        }
    }

    /// `en_US_POSIX` + รูปแบบตายตัว: บรรทัดนี้ต้องอ่านเหมือนกันทุกเครื่อง และเป็น
    /// ภาษาเดียวกับที่บอร์ดพูด (บอร์ดมีแต่ ASCII อยู่แล้ว) ส่วนโซนเวลาเอาของผู้ใช้
    static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f
    }
}
