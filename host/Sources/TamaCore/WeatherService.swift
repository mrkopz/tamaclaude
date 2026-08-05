import Foundation

/// ค่าตั้งของหน้าอากาศ — อยู่ใน `UserDefaults` เท่านั้น และแอปเป็นบรรณาธิการเดียว
///
/// ไม่มีไฟล์ให้แก้มือแบบ `~/.tamaclaude/tools.json` ตรงนี้ตั้งใจ: ค่าเหล่านี้มี GUI เต็ม
/// รูปแบบ การมีสองแหล่งจะทำให้หน้าต่างโชว์เมืองหนึ่งขณะที่จอแสดงอีกเมืองหนึ่ง
///
/// "เปิด/ปิดหน้านี้" **ไม่ได้อยู่ที่นี่** — มันเป็นข้อเดียวกับที่ถามทุกหน้า จึงอยู่ใน
/// `PageSettings` ที่เดียว ไม่งั้นจะมีสองที่ที่ตอบว่าหน้าอากาศเปิดอยู่ไหม
public struct WeatherSettings: Equatable, Sendable {
    /// ชื่อเมืองที่ผู้ใช้พิมพ์ — ไม่ใช้ CoreLocation เพื่อเลี่ยง TCC อีกใบ และของตั้งโต๊ะ
    /// ไม่ได้ย้ายที่
    public var place: String
    public var unit: TempUnit

    public init(place: String = "", unit: TempUnit = .celsius) {
        self.place = place
        self.unit = unit
    }

    /// ยังไม่ได้พิมพ์ชื่อเมือง = ยังไม่มีอะไรให้ดึง (หน้านี้เปิดอยู่ไหมเป็นคำถามคนละข้อ
    /// และเป็นของผู้เรียก — `PageSettings` เป็นคนตอบ)
    public var isUsable: Bool {
        !place.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public enum Key {
        /// สวิตช์เก่าของรอบก่อนหน้า — ไม่ถูกเขียนอีกแล้ว เหลือไว้ให้ `PageSettings`
        /// อ่านครั้งเดียวตอนย้ายค่าของผู้ใช้เดิมเข้ารายการหน้า
        public static let legacyEnabled = "weatherPage"
        public static let place = "weatherPlace"
        public static let unit = "weatherUnit"
    }

    public static func load(_ defaults: UserDefaults = .standard) -> WeatherSettings {
        WeatherSettings(
            place: defaults.string(forKey: Key.place) ?? "",
            unit: TempUnit(rawValue: defaults.string(forKey: Key.unit) ?? "") ?? .celsius)
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(place, forKey: Key.place)
        defaults.set(unit.rawValue, forKey: Key.unit)
    }
}

/// เมื่อไรถึงจะยิงรอบถัดไป — ตรรกะล้วน ไม่มี timer ของตัวเอง
///
/// ถูกป้อน `now` เข้ามาเหมือน `UsagePoller` และ `FailoverPolicy` ด้วยเหตุผลเดียวกัน:
/// สิ่งที่ขึ้นกับเวลาต้องทดสอบได้โดยไม่ต้องรอของจริง
///
/// รอบที่ล้มไม่ต้องรอเต็มรอบ — เน็ตที่หลุดไปสิบวินาทีไม่ควรทำให้หน้าอากาศค้างอีก
/// 15 นาที แต่ก็ไม่ยิงรัวเช่นกัน เพราะบริการนี้ให้ใช้ฟรีบนพื้นฐานว่าไม่มีใครยิงถี่
public struct FetchSchedule: Equatable, Sendable {
    public let interval: TimeInterval
    public let retry: TimeInterval

    public private(set) var running = false
    public private(set) var lastStarted: Date?
    /// รอบล่าสุดสำเร็จไหม — ตัวตัดสินว่าจะรออีกนานเท่าไร
    public private(set) var lastFailed = false

    public init(interval: TimeInterval, retry: TimeInterval = 60) {
        self.interval = interval
        self.retry = retry
    }

    /// ถึงเวลายิงหรือยัง — คืน `true` แค่ครั้งเดียวต่อหนึ่งรอบ และทำเครื่องหมายว่าเริ่มแล้ว
    public mutating func start(now: Date) -> Bool {
        guard !running else { return false }
        let wait = lastFailed ? retry : interval
        if let lastStarted, now.timeIntervalSince(lastStarted) < wait { return false }
        running = true
        lastStarted = now
        return true
    }

    public mutating func finished(ok: Bool) {
        running = false
        lastFailed = !ok
    }

    /// ค่าตั้งเปลี่ยน (เมืองใหม่ หน่วยใหม่) — ของที่ถืออยู่ตอบคำถามคนละข้อแล้ว
    /// รอบถัดไปต้องเกิดเดี๋ยวนี้ ไม่ใช่เมื่อครบ 15 นาทีนับจากรอบก่อน
    public mutating func invalidate() {
        lastStarted = nil
        lastFailed = false
    }
}

/// หน้าอากาศฝั่ง Mac: ดึง Open-Meteo ตามรอบ แล้ววาง page frame ไว้ให้ `PageHub`
///
/// การยิงจริงเข้ามาทาง closure — `tamatest` ป้อน fixture แทนได้ และไม่มีเทสต์ตัวไหน
/// แตะเครือข่าย
public final class WeatherService {
    public typealias Fetcher = (URL, @escaping (Result<Data, Error>) -> Void) -> Void

    /// มีเฟรมใหม่ — `observedAt` คือตอนที่ค่านี้ถูกอ่านมาจริง ซึ่งเป็นจุดตั้งต้นของ data age
    public var onFrame: ((WeatherFrame, Date) -> Void)?
    /// ประโยคล่าสุดที่หน้านี้พูดถึงตัวเอง — หน้าตั้งค่าเอาไปบอกผู้ใช้ว่าทำไมยังไม่มีตัวเลข
    public private(set) var status: String?

    public private(set) var settings: WeatherSettings
    private var schedule: FetchSchedule
    private let fetch: Fetcher
    /// พิกัดของชื่อเมืองที่ผู้ใช้พิมพ์ — แปลครั้งเดียวแล้วจำไว้จนกว่าชื่อจะเปลี่ยน
    /// (เมืองไม่ย้ายที่ และการยิง geocoding ทุก 15 นาทีคือคำขอที่ไม่มีใครต้องการ)
    private var located: (query: String, place: GeoPlace)?

    public init(
        settings: WeatherSettings = WeatherSettings(),
        interval: TimeInterval = WeatherSource.interval,
        fetch: @escaping Fetcher
    ) {
        self.settings = settings
        self.schedule = FetchSchedule(interval: interval)
        self.fetch = fetch
    }

    /// ผู้ใช้เปลี่ยนค่าตั้ง — เมืองหรือหน่วยที่เปลี่ยนทำให้ของที่ถืออยู่หมดความหมายทันที
    public func update(_ next: WeatherSettings) {
        let changed = next.place != settings.place || next.unit != settings.unit
        settings = next
        guard changed else { return }
        if next.place != located?.query { located = nil }
        status = nil
        schedule.invalidate()
    }

    public var isRunning: Bool { schedule.running }

    /// หน้านี้เพิ่งถูกเปิดกลับมา — เฟรมที่เคยมีถูกบอร์ดลืมไปตอนปิด (ADR-0002) การรอ
    /// รอบถัดไปตามปกติแปลว่าผู้ใช้เห็นหน้าเปล่าได้นานถึง 15 นาทีหลังกดสวิตช์
    public func restart() {
        status = nil
        schedule.invalidate()
    }

    public func tick(now: Date = Date()) {
        guard settings.isUsable else { return }
        guard schedule.start(now: now) else { return }
        step(now: now)
    }

    /// ต้องหาพิกัดก่อนไหม — ถ้าเคยหาแล้วก็ข้ามไปดึงอากาศเลย
    private func step(now: Date) {
        let query = settings.place.trimmingCharacters(in: .whitespaces)
        if let located, located.query == query {
            forecast(located.place, now: now)
            return
        }
        guard let url = WeatherSource.geocodeURL(query) else {
            finish(nil, "could not look up \(query)")
            return
        }
        fetch(url) { [weak self] result in
            guard let self else { return }
            switch result.flatMap({ data in Result { try WeatherSource.place(from: data) } }) {
            case .success(let place):
                self.located = (query, place)
                self.forecast(place, now: now)
            case .failure(let error):
                self.finish(nil, Self.explain(error))
            }
        }
    }

    private func forecast(_ place: GeoPlace, now: Date) {
        let unit = settings.unit
        guard let url = WeatherSource.forecastURL(place, unit: unit) else {
            finish(nil, "could not build the weather request")
            return
        }
        fetch(url) { [weak self] result in
            guard let self else { return }
            // แถบพยากรณ์อ่านจาก payload ก้อนเดียวกัน และอ่านไม่ได้ก็ไม่ล้มทั้งรอบ
            // (ดู `WeatherSource.hourly`) — รอบที่ "สำเร็จแต่ไม่มีแถบล่าง" ยังมีค่า
            let ahead = result.map(WeatherSource.hourly)
            switch result.flatMap({ data in
                Result { try WeatherSource.reading(from: data, unit: unit) }
            }) {
            case .success(let reading):
                // ป้ายบนจอเป็นชื่อที่ *บริการ* คืนมา ไม่ใช่ที่ผู้ใช้พิมพ์ — คนที่พิมพ์
                // "bkk" ต้องเห็นว่าจอกำลังพูดถึงเมืองไหนจริงๆ
                let label = place.name.isEmpty ? self.settings.place : place.name
                let none: (hourStart: Int, hours: [HourlyPoint]) = (-1, [])
                let hours = (try? ahead.get()) ?? none
                self.finish(WeatherFrame(place: label, reading: reading,
                                         hourStart: hours.hourStart, hours: hours.hours), nil)
            case .failure(let error):
                self.finish(nil, Self.explain(error))
            }
        }
    }

    private func finish(_ frame: WeatherFrame?, _ problem: String?) {
        schedule.finished(ok: frame != nil)
        status = problem
        guard let frame else { return }
        onFrame?(frame, Date())
    }

    private static func explain(_ error: Error) -> String {
        (error as? WeatherError)?.message ?? error.localizedDescription
    }
}

/// ตัวยิงจริง — บางจนไม่มีตรรกะให้เทสต์ ทุกอย่างที่ตัดสินใจอยู่ใน `WeatherService`
public enum WeatherFetch {
    public static func urlSession(
        _ session: URLSession = .shared, timeout: TimeInterval = 15
    ) -> WeatherService.Fetcher {
        { url, done in
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            session.dataTask(with: request) { data, response, error in
                if let error {
                    done(.failure(error))
                    return
                }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(code), let data else {
                    done(.failure(WeatherError.badPayload))
                    return
                }
                done(.success(data))
            }.resume()
        }
    }
}
