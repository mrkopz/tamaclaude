import Foundation

/// นัดหนึ่งรายการอย่างที่อ่านมาได้จาก EventKit — ยังไม่ถูกจัดรูป ยังไม่ถูกตัด
///
/// เก็บ `start` เป็นเวลาสัมบูรณ์ ไม่ใช่ข้อความ เพราะทั้งการเรียง การคัดหน้าต่างเจ็ดวัน
/// และการเลือกคำว่า "Today" ล้วนเป็นการเทียบเวลา ชั้นที่แตะ EventKit จึงไม่ต้องรู้
/// อะไรเลยนอกจากคัดลอกค่าออกมา (ADR-0005: ตรรกะอยู่ในตัวแปลง ไม่ใช่ในชั้นที่แตะระบบ)
public struct CalendarEvent: Equatable, Sendable {
    public var title: String
    public var start: Date
    /// นัดทั้งวันไม่มีเวลาให้แสดง — `start` ของมันคือเที่ยงคืนของวันนั้นตามที่ EventKit ให้มา
    public var isAllDay: Bool

    public init(title: String, start: Date, isAllDay: Bool = false) {
        self.title = title
        self.start = start
        self.isAllDay = isAllDay
    }
}

/// ปฏิทินหนึ่งใบที่ผู้ใช้เลือกได้ในแอป — id เป็นของ EventKit ส่วนชื่อมีไว้ให้คนอ่าน
public struct CalendarInfo: Equatable, Sendable {
    public var id: String
    public var title: String
    /// ชื่อบัญชีที่ปฏิทินใบนี้อยู่ (Google, iCloud) — ผู้ใช้ที่มีปฏิทินชื่อ "Calendar"
    /// สองใบแยกมันออกจากกันไม่ได้ถ้าไม่บอกว่ามาจากไหน
    public var source: String

    public init(id: String, title: String, source: String) {
        self.id = id
        self.title = title
        self.source = source
    }
}

/// สิทธิ์ที่ระบบให้มา — สามค่า ไม่ใช่ boolean
///
/// "ยังไม่เคยถาม" กับ "ถามแล้วโดนปฏิเสธ" บอกผู้ใช้คนละเรื่อง: อันแรกแก้ได้ด้วยการกดปุ่ม
/// ในแอป อันหลังต้องไปเปิดใน System Settings เอง เพราะ macOS จะไม่ถามซ้ำอีกแล้ว
public enum CalendarAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case granted
}

/// สิ่งที่หน้านี้กำลังพูดถึงตัวเอง — เดินทางไปกับเฟรมเพราะจอเปล่าไม่ใช่คำตอบ
///
/// ตัวเลขเดินทางบนสาย จึงเป็นสัญญากับ firmware แบบเดียวกับ `PageKind`
/// (`ct_calendar_state_t` ใน firmware/main/ct_calendar.h)
public enum CalendarState: Int, Codable, Sendable {
    /// มีนัดให้แสดง — แถวข้างล่างคือของจริง
    case ok = 0
    /// เชื่อมต่อได้ อ่านได้ แต่เจ็ดวันข้างหน้าว่างจริงๆ
    case empty = 1
    /// ถูกปฏิเสธสิทธิ์ไปแล้ว — macOS จะไม่ถามซ้ำ ทางแก้เหลือทางเดียวคือ System Settings
    case needsAccess = 2
    /// ได้สิทธิ์แล้วแต่ผู้ใช้ยังไม่ได้เลือกปฏิทินสักใบ — จอนี้วางให้คนอื่นเห็นได้
    /// การเปิดทุกปฏิทินให้เองจึงไม่ใช่ค่าตั้งต้นที่ปลอดภัย
    case noCalendars = 3
    /// ยังไม่เคยถูกถามเลย — ก้าวถัดไปคือปุ่มในแอป ไม่ใช่ System Settings ซึ่งยังไม่มี
    /// แถวของ TamaClaude ให้กดด้วยซ้ำ สองสภาพนี้จึงแยกกันบนสาย ไม่ใช่ยุบเป็นอันเดียว
    case notAsked = 4
}

/// page frame ของหน้าปฏิทิน
///
/// ```
/// {"a":42,"e":[{"d":"Today","n":"ประชุมทีม","t":"09:30"}],"g":3,"m":42,"p":0}
/// ```
///
/// วันกับเวลามาเป็น *ข้อความที่จัดรูปแล้ว* ด้วยเหตุผลเดียวกับราคาคริปโต: บอร์ดไม่มี
/// timezone ไม่มีปฏิทิน และไม่มีนาฬิกาที่ตั้งตรง การส่งเวลาสัมบูรณ์ไปให้มันจัดรูปเอง
/// คือการขอให้มันเดาสามอย่างที่ Mac รู้อยู่แล้ว
public struct CalendarFrame: PageFrame, Equatable, Codable, Sendable {
    public var kind: PageKind { .calendar }

    public var events: [CalendarSlot]
    public var state: CalendarState
    public var age: Int
    /// นาทีจนถึงนัดแรก ตอนที่เฟรมนี้ถูกสร้าง — `nil` เมื่อนัดแรกเป็นนัดทั้งวัน
    ///
    /// บอร์ดนับถอยหลังต่อเองโดยหักอายุของเฟรมออก ไม่ได้รับเวลาสัมบูรณ์: มันไม่มี
    /// timezone และไม่มีนาฬิกาที่ตั้งตรง (เหตุผลเดียวกับที่วันและเวลามาเป็นข้อความ)
    public var minutesUntilFirst: Int?

    /// สามรายการ — นัดถัดไปกินที่ของการ์ดใบใหญ่ไป เหลือสองแถวใต้สันเวลา
    /// (`[calendar] rows` ใน tools/layout.toml)
    public static let maxRows = 3
    /// ความกว้างคอลัมน์ชื่อนัดคือ 216px ที่ฟอนต์ 12 — วัดจาก `[calendar] title_w`
    /// นับเป็น *ช่อง* ไม่ใช่ scalar (`Text.fit`) ไม่งั้นชื่อไทยจะถูกตัดสั้นเกินจริง
    /// เพราะวรรณยุกต์กับสระบนกว้างศูนย์
    ///
    /// ค่านี้เอนไปทางละติน: `preview.py --limits` วัดได้ไทย 27 ช่อง ละติน ~40 (ตัวอักษร
    /// ละตินแคบกว่าและกว้างไม่เท่ากัน) — 30 คือจุดที่ชื่ออังกฤษได้อ่านเต็มขึ้น แลกกับชื่อไทย
    /// ยาวสุดที่ล้นคอลัมน์แล้วถูก `LV_LABEL_LONG_DOT` ฝั่งบอร์ดตัดท้ายให้ · ตาข่ายนั้นต้อง
    /// มีจริงถึงจะตั้งค่าแบบนี้ได้ ก่อนหน้านี้ป้ายที่ล้นจะ *ขึ้นบรรทัดใหม่* ไปทับแถวถัดไป
    public static let titleLimit = 30
    /// ชื่อนัดบนการ์ดได้ทั้งความกว้างการ์ด (280px ที่ฟอนต์ 14) **และสองบรรทัด**
    ///
    /// เอนไปทางละตินด้วยเหตุผลเดียวกับ `titleLimit`: วัดได้ไทย 31 ช่องต่อบรรทัด (= 62)
    /// ละติน ~40 (= 80) — 65 อยู่เหนือเพดานไทยขึ้นมา เพื่อให้ชื่ออังกฤษยาวๆ ได้ใช้บรรทัด
    /// ที่สองจนเต็มจริง ส่วนชื่อไทยที่ยาวเกินก็ตกไปให้ `LV_LABEL_LONG_DOT` ตัดท้าย
    ///
    /// เพดานคนละตัวกับแถวล่างโดยตั้งใจ: นัดถัดไปคือชื่อที่ต้องอ่านออกที่สุดบนหน้า และ
    /// มันเป็นบรรทัดเดียวที่ไม่ต้องแบ่งที่กับคอลัมน์เวลา
    public static let heroTitleLimit = 65

    /// หนึ่งแถวอย่างที่มันอยู่บนสาย
    public struct CalendarSlot: Equatable, Codable, Sendable {
        /// "Today" · "Tomorrow" · "Mon" — Mac เลือกคำ บอร์ดแค่วาด
        public var day: String
        /// "09:30" หรือ "all day"
        public var time: String
        public var title: String

        public init(day: String, time: String, title: String) {
            self.day = day
            self.time = time
            self.title = title
        }

        enum CodingKeys: String, CodingKey {
            case day = "d"
            case time = "t"
            case title = "n"
        }
    }

    public init(
        events: [CalendarSlot], state: CalendarState = .ok, age: Int = 0,
        minutesUntilFirst: Int? = nil
    ) {
        self.events = Array(events.prefix(Self.maxRows))
        // แถวที่ไม่มีอยู่กับสถานะ `ok` เข้ากันไม่ได้ — บอร์ดจะได้หน้าที่ว่างโดยไม่มีคำอธิบาย
        self.state = self.events.isEmpty && state == .ok ? .empty : state
        self.age = age
        self.minutesUntilFirst = self.events.isEmpty ? nil : minutesUntilFirst
    }

    enum CodingKeys: String, CodingKey {
        case kindID = "g"
        case age = "a"
        case rows = "e"
        case state = "p"
        case minutes = "m"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(Int.self, forKey: .kindID)
        guard id == PageKind.calendar.rawValue else {
            throw DecodingError.dataCorruptedError(
                forKey: .kindID, in: c, debugDescription: "not a calendar frame")
        }
        age = try c.decode(Int.self, forKey: .age)
        events = try c.decodeIfPresent([CalendarSlot].self, forKey: .rows) ?? []
        state = try c.decode(CalendarState.self, forKey: .state)
        minutesUntilFirst = try c.decodeIfPresent(Int.self, forKey: .minutes)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(PageKind.calendar.rawValue, forKey: .kindID)
        try c.encode(age, forKey: .age)
        try c.encode(state, forKey: .state)
        try c.encodeIfPresent(minutesUntilFirst, forKey: .minutes)
        try c.encode(rows(titleLimit: Self.titleLimit, count: events.count), forKey: .rows)
    }

    /// นัดแรกได้เพดานของตัวเอง — การ์ดกว้างกว่าคอลัมน์ชื่อของแถวล่าง และได้สองบรรทัด
    ///
    /// ตอนบีบเฟรม เพดานทั้งสองยุบลง *ตามสัดส่วน* ไม่ใช่ลงเหลือเท่ากัน (การ์ดที่ถูกตัดสั้น
    /// เท่าแถวล่างคือการ์ดที่เสียเหตุผลที่มันกว้างกว่าไป) และไม่ใช่ห่างกันคงที่ — ส่วนต่าง
    /// คงที่ทำให้การ์ดมีพื้นขั้นต่ำ ~41 ช่องที่บีบต่อไม่ได้ แล้วเฟรมที่งบแคบจริงๆ ก็ล้มทั้งใบ
    private func heroLimit(_ titleLimit: Int) -> Int {
        max(4, titleLimit * Self.heroTitleLimit / Self.titleLimit)
    }

    private func rows(titleLimit: Int, count: Int) -> [CalendarSlot] {
        events.prefix(count).enumerated().map { i, e in
            CalendarSlot(
                day: e.day, time: e.time,
                title: Text.fit(e.title, to: i == 0 ? heroLimit(titleLimit) : titleLimit))
        }
    }

    /// เฟรมนี้พอดีหนึ่ง MTU ด้วยลำดับการบีบที่ *ไม่* แตะวันและเวลา
    ///
    /// เหตุผลเดียวกับที่หน้าคริปโตไม่ยอมตัดสัญลักษณ์: นัดที่เหลือแต่ชื่อโดยไม่มีเวลาคือ
    /// สิ่งที่ผู้ใช้ต้องไปเปิดปฏิทินจริงเพื่ออ่านอยู่ดี ลำดับจึงเป็น
    /// 1. ตัดชื่อนัดให้สั้นลงทีละขั้น (ยังบอกได้ว่านัดอะไร)
    /// 2. ตัดแถวท้ายทิ้งทั้งแถว (นัดที่ไกลที่สุดหายไปก่อน)
    ///
    /// แถวสุดท้ายไม่ถูกตัด: เฟรมที่มีนัดอยู่แต่ส่งไปศูนย์แถวจะขึ้นจอเป็น "ไม่มีนัด"
    /// ซึ่งไม่ใช่หน้าที่บีบแล้ว แต่เป็นหน้าที่โกหก — ไม่ส่งเลยยังจริงกว่า
    public func encoded(maxBytes: Int = Wire.maxPayload) throws -> Data {
        let encoder = Wire.encoder()
        let floor = events.isEmpty ? 0 : 1
        var count = events.count
        while true {
            var limit = Self.titleLimit
            while limit >= 4 {
                let data = try encoder.encode(
                    Payload(frame: self, titleLimit: limit, count: count))
                if data.count <= maxBytes { return data }
                limit -= 4
            }
            guard count > floor else { throw CalendarError.frameTooLong }
            count -= 1
        }
    }

    /// ก้อนที่ถูกเข้ารหัสจริง — แยกจาก `encode(to:)` ด้วยเหตุผลเดียวกับหน้าคริปโต:
    /// ความยาวชื่อกับจำนวนแถวเป็นผลของการวัด ซึ่ง `Encodable` ไม่มีที่ให้ส่งค่าเข้าไป
    private struct Payload: Encodable {
        let frame: CalendarFrame
        let titleLimit: Int
        let count: Int

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(PageKind.calendar.rawValue, forKey: .kindID)
            try c.encode(frame.age, forKey: .age)
            try c.encode(frame.state, forKey: .state)
            try c.encodeIfPresent(frame.minutesUntilFirst, forKey: .minutes)
            try c.encode(
                frame.rows(titleLimit: titleLimit, count: count), forKey: .rows)
        }
    }
}

public enum CalendarError: Error, Equatable, Sendable {
    /// บีบจนไม่เหลือแถวแล้วยังไม่พอดีหนึ่ง MTU
    case frameTooLong

    public var message: String {
        switch self {
        case .frameTooLong: return "the calendar page does not fit one frame"
        }
    }
}

/// นัดที่อ่านมาได้ -> เฟรมที่ส่งได้ — ทั้งหมดเป็นฟังก์ชันบริสุทธิ์ที่เทสต์ป้อนข้อมูลปลอมได้
///
/// อยู่แยกจากชั้นที่แตะ EventKit โดยตั้งใจ (ADR-0005): ชั้นนั้นบางจนไม่มีอะไรให้เทสต์
/// ส่วนทุกอย่างที่ตัดสินใจ — หน้าต่างเจ็ดวัน · การเรียง · เพดานสี่รายการ · คำว่า
/// "Today" — อยู่ที่นี่ และไม่มีบรรทัดไหนต้องมีปฏิทินจริงถึงจะรันได้
public enum CalendarPage {
    /// รอบดึงของหน้านี้ — 5 นาที ตามใบงาน
    ///
    /// ความสดที่แท้จริงถูกจำกัดด้วยรอบ sync ของ macOS ไม่ใช่รอบนี้ (ADR-0005) การดึง
    /// ถี่กว่านี้จึงได้คำตอบเดิมกลับมา แต่ยังต้องเดินอยู่: นัดที่ผ่านไปแล้วต้องหลุดจากจอ
    public static let interval: TimeInterval = 300
    /// มองไปข้างหน้าเจ็ดวัน — ไกลกว่านี้คือของที่ผู้ใช้ยังไม่ต้องเตรียมตัววันนี้
    public static let window: TimeInterval = 7 * 86400

    /// นัดที่ควรขึ้นจอ เรียงตามเวลา ตัดที่สี่รายการ
    ///
    /// นัดที่ *เริ่มไปแล้ว* ถูกตัดออก ไม่ใช่คงไว้จนจบ: หน้านี้ตอบคำถามว่า "อะไรรออยู่"
    /// ไม่ใช่ "ตอนนี้อยู่ในนัดอะไร" ซึ่งเป็นคำถามที่คนที่อยู่ในห้องประชุมรู้คำตอบอยู่แล้ว
    /// นัดทั้งวัน *ของวันนี้* ยังไม่ผ่านไป แม้ `start` ของมันจะเป็นเที่ยงคืนที่ผ่านมาแล้ว —
    /// เทียบมันด้วยวัน ไม่ใช่ด้วยวินาที ไม่งั้นวันหยุดกับวันเกิดจะหายจากจอตั้งแต่ 00:00:01
    /// ของวันที่มันเกิดขึ้น ซึ่งเป็นวันเดียวที่มันมีความหมาย
    public static func upcoming(
        _ events: [CalendarEvent], now: Date, limit: Int = CalendarFrame.maxRows,
        calendar: Calendar = .current
    ) -> [CalendarEvent] {
        let end = now.addingTimeInterval(window)
        let today = calendar.startOfDay(for: now)
        return
            events
            .filter {
                let from = $0.isAllDay ? calendar.startOfDay(for: $0.start) : $0.start
                return from >= ($0.isAllDay ? today : now) && $0.start <= end
            }
            .sorted { $0.start < $1.start }
            .prefix(limit)
            .map { $0 }
    }

    /// เวลาแบบ 24 ชั่วโมงเสมอ ไม่ตามค่าตั้งของเครื่อง
    ///
    /// "09:30" กว้างคงที่ทุกแถว ส่วน "9:30 AM" ไม่ใช่ และคอลัมน์ที่ยาวไม่เท่ากันบนจอ
    /// 320px แปลว่าชื่อนัดของแต่ละแถวเริ่มคนละที่
    public static func timeText(
        _ event: CalendarEvent, calendar: Calendar = .current
    ) -> String {
        guard !event.isAllDay else { return "all day" }
        let c = calendar.dateComponents([.hour, .minute], from: event.start)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// ชื่อวันสั้นที่สุดที่ยังบอกได้ว่าเมื่อไร
    ///
    /// วันนี้กับพรุ่งนี้มีคำของตัวเอง เพราะ "Mon" ที่แปลว่าวันนี้อ่านผิดได้ทั้งสัปดาห์
    /// ส่วนที่เหลือใช้ชื่อวัน — ในหน้าต่างเจ็ดวันไม่มีวันไหนซ้ำกัน จึงไม่ต้องมีวันที่
    public static func dayText(
        _ event: CalendarEvent, now: Date, calendar: Calendar = .current
    ) -> String {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: event.start)
        ).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        let weekday = calendar.component(.weekday, from: event.start)
        // ชื่อวันเป็นภาษาอังกฤษเสมอ ไม่ตาม locale — ฟอนต์บนบอร์ดมีแต่ ASCII กับไทย
        // และคอลัมน์กว้าง 74px ไม่มีที่ให้ชื่อวันแบบเต็มของภาษาไหนเลย
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return names[(weekday - 1 + names.count) % names.count]
    }

    /// เฟรมของนัดชุดหนึ่ง — `state` ที่ส่งมาคือสิ่งที่รู้ *ก่อน* อ่านนัด (สิทธิ์ · ปฏิทินที่เลือก)
    /// ส่วน "ว่างเจ็ดวัน" เป็นข้อสรุปที่เกิดตรงนี้
    public static func frame(
        events: [CalendarEvent], now: Date, state: CalendarState = .ok,
        calendar: Calendar = .current
    ) -> CalendarFrame {
        guard state == .ok else { return CalendarFrame(events: [], state: state) }
        let picked = upcoming(events, now: now, calendar: calendar)
        let rows = picked.map {
            CalendarFrame.CalendarSlot(
                day: dayText($0, now: now, calendar: calendar),
                time: timeText($0, calendar: calendar), title: $0.title)
        }
        return CalendarFrame(
            events: rows, state: rows.isEmpty ? .empty : .ok,
            minutesUntilFirst: minutesUntil(picked.first, now: now))
    }

    /// นาทีจนถึงนัดหนึ่ง — `nil` เมื่อไม่มีนัด หรือเมื่อมันเป็นนัดทั้งวัน
    ///
    /// นัดทั้งวันไม่มีเวลาเริ่ม การนับถอยหลังไปหาเที่ยงคืนของมันคือตัวเลขที่ถูกทางเลข
    /// แต่ตอบผิดคำถาม — จอจะบอกว่า "in 14h 20m" สำหรับวันเกิดที่ไม่ได้เริ่มตอนเที่ยงคืน
    ///
    /// ปัดขึ้น ไม่ใช่ปัดลง: นัดที่เหลือ 90 วินาทีต้องอ่านว่า "in 2 min" ไม่ใช่ "in 1 min"
    /// ที่กำลังจะกลายเป็น "now" ทั้งที่ยังมีเวลาเดินไปห้องประชุม
    public static func minutesUntil(_ event: CalendarEvent?, now: Date) -> Int? {
        guard let event, !event.isAllDay else { return nil }
        return Int(ceil(event.start.timeIntervalSince(now) / 60))
    }
}
