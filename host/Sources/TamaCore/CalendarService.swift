import Foundation

/// ปฏิทินใบไหนได้ขึ้นจอบ้าง — อยู่ใน `UserDefaults` เท่านั้น แอปเป็นบรรณาธิการเดียว
/// (เหตุผลเดียวกับ `CryptoSettings`)
///
/// เก็บ *รายชื่อที่เลือก* ไม่ใช่ *รายชื่อที่ปิด*: จอนี้วางให้คนอื่นเห็นได้ ปฏิทินใบใหม่ที่
/// โผล่มาเองใน macOS (ปฏิทินที่ถูกแชร์มา · บัญชีที่เพิ่งเพิ่ม) จึงต้องเงียบไว้ก่อนจนกว่า
/// ผู้ใช้จะติ๊กมันเอง ไม่ใช่ขึ้นจอทันทีเพราะไม่มีใครเคยปิดมัน
public struct CalendarSettings: Equatable, Sendable {
    /// identifier ของ EventKit ไม่ใช่ชื่อที่ผู้ใช้เห็น — ชื่อซ้ำกันได้ระหว่างบัญชี
    public private(set) var calendars: [String]

    public init(calendars: [String] = []) {
        var seen: Set<String> = []
        var out: [String] = []
        for id in calendars where !id.isEmpty && seen.insert(id).inserted {
            out.append(id)
        }
        self.calendars = out
    }

    /// ยังไม่ได้เลือกปฏิทินเลย = ยังไม่มีอะไรให้อ่าน (หน้านี้เปิดอยู่ไหมเป็นคำถามคนละข้อ)
    public var isUsable: Bool { !calendars.isEmpty }

    public func isOn(_ id: String) -> Bool { calendars.contains(id) }

    public mutating func setOn(_ id: String, _ on: Bool) {
        guard !id.isEmpty else { return }
        if on {
            guard !calendars.contains(id) else { return }
            calendars.append(id)
        } else {
            calendars.removeAll { $0 == id }
        }
    }

    public enum Key {
        public static let calendars = "calendarIDs"
    }

    public static func load(_ defaults: UserDefaults = .standard) -> CalendarSettings {
        CalendarSettings(calendars: defaults.array(forKey: Key.calendars) as? [String] ?? [])
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(calendars, forKey: Key.calendars)
    }
}

/// สิ่งที่หน้าปฏิทินต้องการจากระบบ — บางจนเทสต์สวมของปลอมแทนได้ทั้งใบ
///
/// มีอยู่เพื่อให้ *ตรรกะ* ไม่ต้องมี EventKit: `CalendarService` คุยกับ protocol นี้
/// เท่านั้น ส่วนตัวจริง (`EventKitCalendars`) ไม่มีอะไรนอกจากคัดลอกค่าออกมา
public protocol CalendarReading: AnyObject, Sendable {
    var access: CalendarAccess { get }
    /// ขอสิทธิ์จากผู้ใช้ — เรียกได้เมื่อ `access == .notDetermined` เท่านั้นที่มีผล
    /// (macOS จะไม่ถามซ้ำหลังถูกปฏิเสธไปแล้ว)
    func requestAccess(_ done: @escaping (CalendarAccess) -> Void)
    /// ปฏิทินทุกใบที่เครื่องนี้มี — หน้าตั้งค่าเอาไปให้ผู้ใช้ติ๊ก
    func calendars() -> [CalendarInfo]
    /// นัดในช่วงเวลาหนึ่งของปฏิทินที่เลือกไว้ — ไม่เรียง ไม่ตัด ไม่ตีความ
    func events(from: Date, to: Date, calendarIDs: [String]) -> [CalendarEvent]
}

/// หน้าปฏิทินฝั่ง Mac: อ่าน EventKit ทุก 5 นาที แล้ววาง page frame ไว้ให้ `PageHub`
///
/// รูปร่างเดียวกับ `WeatherService`/`CryptoService` — ตัวจัดตารางที่ถูกป้อนเวลา
/// (`FetchSchedule`) และการแปลงที่เป็นฟังก์ชันบริสุทธิ์ ต่างกันข้อเดียว: แหล่งข้อมูล
/// อยู่ในเครื่อง จึงไม่มี URL ไม่มี timeout และไม่มีอะไรที่ล้มเหลวชั่วคราวได้ (ADR-0005)
public final class CalendarService {
    /// มีเฟรมใหม่ — `observedAt` คือตอนที่ค่านี้ถูกอ่านมาจริง ซึ่งเป็นจุดตั้งต้นของ data age
    public var onFrame: ((CalendarFrame, Date) -> Void)?
    /// ประโยคล่าสุดที่หน้านี้พูดถึงตัวเอง — หน้าตั้งค่าเอาไปบอกผู้ใช้ว่าทำไมจอยังว่าง
    public private(set) var status: String?

    public private(set) var settings: CalendarSettings
    private let source: CalendarReading
    private var schedule: FetchSchedule

    public init(
        settings: CalendarSettings = CalendarSettings(),
        source: CalendarReading,
        interval: TimeInterval = CalendarPage.interval
    ) {
        self.settings = settings
        self.source = source
        self.schedule = FetchSchedule(interval: interval)
    }

    public var access: CalendarAccess { source.access }
    public var isRunning: Bool { schedule.running }

    /// ปฏิทินทุกใบที่เลือกได้ — ไม่มีสิทธิ์ก็ไม่มีรายการ ซึ่งเป็นคนละเรื่องกับ "ไม่มีปฏิทิน"
    /// และเป็นเหตุผลที่หน้าตั้งค่าต้องดู `access` ด้วย ไม่ใช่ดูแค่ลิสต์ว่าง
    public func available() -> [CalendarInfo] {
        guard source.access == .granted else { return [] }
        return source.calendars()
    }

    /// ผู้ใช้ติ๊กปฏิทินใบใหม่ (หรือเอาออก) — ของที่ถืออยู่ตอบคำถามคนละข้อทันที
    public func update(_ next: CalendarSettings) {
        guard next != settings else { return }
        settings = next
        status = nil
        schedule.invalidate()
    }

    /// หน้านี้เพิ่งถูกเปิดกลับมา — เฟรมที่เคยมีถูกบอร์ดลืมไปตอนปิด (ADR-0002)
    public func restart() {
        status = nil
        schedule.invalidate()
    }

    /// ขอสิทธิ์แล้วดึงทันทีถ้าได้ — ปุ่มในหน้าตั้งค่าเรียกทางนี้
    public func requestAccess(_ done: @escaping (CalendarAccess) -> Void) {
        source.requestAccess { [weak self] granted in
            self?.schedule.invalidate()
            done(granted)
        }
    }

    /// หนึ่งจังหวะของนาฬิกา — ต่างจากหน้าอื่นตรงที่ไม่มีอะไรรอ ทุกอย่างจบในเทิร์นเดียว
    ///
    /// รอบยังเดินแม้ยังไม่ได้สิทธิ์หรือยังไม่ได้เลือกปฏิทิน เพราะสภาพพวกนั้น *คือ* สิ่งที่
    /// หน้านี้ต้องบอก — จอที่ไม่เคยได้เฟรมเลยจะเขียนว่า "ยังไม่เคยได้ข้อมูล" ซึ่งอ่านว่า
    /// อุปกรณ์พัง ไม่ใช่ว่ายังไม่ได้กดอนุญาต
    public func tick(now: Date = Date()) {
        guard schedule.start(now: now) else { return }
        let state = self.state()
        let events =
            state == .ok
            ? source.events(
                from: now, to: now.addingTimeInterval(CalendarPage.window),
                calendarIDs: settings.calendars)
            : []
        let frame = CalendarPage.frame(events: events, now: now, state: state)
        schedule.finished(ok: true)
        status = Self.explain(frame.state)
        onFrame?(frame, now)
    }

    /// สภาพที่รู้ได้ก่อนอ่านนัด — สิทธิ์มาก่อน เพราะไม่มีสิทธิ์แล้วรายการปฏิทินก็ว่างเสมอ
    /// และ "ยังไม่ได้เลือกปฏิทิน" ที่ขึ้นจอตอนนั้นจะส่งผู้ใช้ไปกดผิดที่
    private func state() -> CalendarState {
        switch source.access {
        case .granted: return settings.isUsable ? .ok : .noCalendars
        case .denied: return .needsAccess
        case .notDetermined: return .notAsked
        }
    }

    private static func explain(_ state: CalendarState) -> String? {
        switch state {
        case .ok: return nil
        case .empty: return "Nothing in the next 7 days."
        case .needsAccess:
            return "Calendar access was refused."
        case .notAsked:
            return "TamaClaude has not asked for your calendars yet."
        case .noCalendars: return "Tick the calendars this screen may show."
        }
    }
}
