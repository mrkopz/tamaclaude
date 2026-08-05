import Foundation

/// หน่วยอุณหภูมิที่ผู้ใช้เลือก — เดินทางไปกับเฟรมเพราะบอร์ดต้องเขียนตัวอักษรต่อท้ายเลข
/// และไม่มีทางรู้เองว่าเลขที่ได้มาเป็นหน่วยไหน
public enum TempUnit: String, Codable, CaseIterable, Sendable {
    case celsius = "C"
    case fahrenheit = "F"

    public var title: String {
        switch self {
        case .celsius: return "Celsius"
        case .fahrenheit: return "Fahrenheit"
        }
    }

    /// ชื่อที่ Open-Meteo ใช้ในพารามิเตอร์ `temperature_unit`
    var apiName: String {
        switch self {
        case .celsius: return "celsius"
        case .fahrenheit: return "fahrenheit"
        }
    }
}

/// ค่าที่ Mac อ่านมาได้จริงหนึ่งครั้ง — ยังไม่มีอายุ ยังไม่มีชื่อสถานที่
///
/// อุณหภูมิถูกปัดเป็นจำนวนเต็มตั้งแต่ตรงนี้ ไม่ใช่ตอนวาด: จอกว้าง 320px อ่านทศนิยม
/// ไม่ออกอยู่แล้ว และเลขที่ปัดแล้วกินไบต์น้อยกว่าในงบ 500 ที่เฟรมมี
public struct WeatherReading: Equatable, Sendable {
    public var temp: Int
    public var high: Int
    public var low: Int
    /// รหัสสภาพอากาศ WMO ที่ Open-Meteo คืนมาดิบๆ — board แปลเป็นสัญลักษณ์เอง
    /// (Mac ส่งข้อมูล ไม่ส่งภาพ — ADR-0004)
    public var code: Int
    public var unit: TempUnit

    public init(temp: Int, high: Int, low: Int, code: Int, unit: TempUnit) {
        self.temp = temp
        self.high = high
        self.low = low
        self.code = code
        self.unit = unit
    }
}

/// หนึ่งช่องของแถบพยากรณ์ — ชั่วโมงข้างหน้าหนึ่งชั่วโมง
///
/// ไม่มีเวลาอยู่ในตัวมันเอง: ทั้งแถบเดินทีละหนึ่งชั่วโมงจาก `WeatherFrame.hourStart`
/// การใส่ชั่วโมงลงทุกช่องคือการจ่ายไบต์ให้ข้อมูลที่คำนวณได้ ในเฟรมที่มีงบ 500
public struct HourlyPoint: Equatable, Sendable {
    public var temp: Int
    /// รหัส WMO เหมือน `WeatherReading.code` — บอร์ดแปลเป็นสัญลักษณ์เอง (ADR-0004)
    public var code: Int

    public init(temp: Int, code: Int) {
        self.temp = temp
        self.code = code
    }
}

/// จุดบนแผนที่ที่ได้จากชื่อเมือง — ผู้ใช้พิมพ์ชื่อ ไม่ได้พิมพ์พิกัด
public struct GeoPlace: Equatable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double

    public init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// page frame ของหน้าอากาศ
///
/// ```
/// {"a":420,"c":[0,1,3,61,61],"g":1,"h":34,"l":26,"n":15,
///  "o":[32,33,33,31,30],"p":"Bangkok","t":31,"u":"C","w":61}
/// ```
public struct WeatherFrame: PageFrame, Equatable, Codable, Sendable {
    public var kind: PageKind { .weather }

    public var place: String
    public var reading: WeatherReading
    public var age: Int
    /// ชั่วโมงของช่องแรกในแถบพยากรณ์ (0..23) — `-1` คือเฟรมนี้ไม่มีพยากรณ์มาด้วย
    ///
    /// ชั่วโมง **สัมบูรณ์** ไม่ใช่ offset จากตอนนี้ ทั้งที่ทุกอย่างอื่นบนหน้านี้เป็นอายุ:
    /// อายุใช้ได้เพราะบอร์ดนับต่อเองได้ แต่ป้าย "17:00" ที่นับต่อไม่ได้จะกลายเป็นคำโกหก
    /// ทันทีที่เฟรมค้าง — ส่วนชั่วโมงสัมบูรณ์ที่ค้างอยู่ยังเป็นชั่วโมงนั้นจริงๆ แค่ผ่านไปแล้ว
    /// และบรรทัดอายุก็บอกอยู่แล้วว่าผ่านไปนานเท่าไร
    public var hourStart: Int
    public var hours: [HourlyPoint]

    /// ชื่อสถานที่ยาวเกินความกว้างจอไม่มีประโยชน์ — วัดจากพื้นที่จริงใน
    /// `tools/layout.toml` (`[weather] place_x` ถึง `icon_x`) ผ่าน `tools/gen/weather.py`
    public static let placeLimit = 18
    /// จำนวนคอลัมน์ของแถบพยากรณ์ — ต้องตรงกับ `[weather] fc_cols` ใน `tools/layout.toml`
    /// (`tamatest` อ่าน `layout.h` มาเทียบ เหมือนที่ทำกับ `PageKind`)
    public static let hourLimit = 5

    public init(place: String, reading: WeatherReading, age: Int = 0,
                hourStart: Int = -1, hours: [HourlyPoint] = []) {
        self.place = place
        self.reading = reading
        self.age = age
        self.hourStart = hourStart
        self.hours = Array(hours.prefix(Self.hourLimit))
    }

    /// มีพยากรณ์ที่วาดได้จริงไหม — สองฟิลด์ต้องพร้อมกัน ไม่ใช่อย่างใดอย่างหนึ่ง
    public var hasHours: Bool { (0..<24).contains(hourStart) && !hours.isEmpty }

    enum CodingKeys: String, CodingKey {
        case kindID = "g"
        case age = "a"
        case place = "p"
        case temp = "t"
        case high = "h"
        case low = "l"
        case code = "w"
        case unit = "u"
        case hourStart = "n"
        case hourTemps = "o"
        case hourCodes = "c"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(Int.self, forKey: .kindID)
        guard id == PageKind.weather.rawValue else {
            throw DecodingError.dataCorruptedError(
                forKey: .kindID, in: c, debugDescription: "not a weather frame")
        }
        place = try c.decode(String.self, forKey: .place)
        age = try c.decode(Int.self, forKey: .age)
        reading = WeatherReading(
            temp: try c.decode(Int.self, forKey: .temp),
            high: try c.decode(Int.self, forKey: .high),
            low: try c.decode(Int.self, forKey: .low),
            code: try c.decode(Int.self, forKey: .code),
            unit: try c.decode(TempUnit.self, forKey: .unit))
        // พยากรณ์เป็นส่วนเสริม เฟรมที่ไม่มีมันยังเป็นเฟรมที่ใช้ได้ — และสองแถวที่ยาวไม่เท่ากัน
        // ก็ไม่ใช่พยากรณ์ครึ่งเดียว มันคือพยากรณ์ที่อ่านไม่ได้ ทิ้งทั้งชุดดีกว่าเดาช่องที่หาย
        let start = try c.decodeIfPresent(Int.self, forKey: .hourStart) ?? -1
        let temps = try c.decodeIfPresent([Int].self, forKey: .hourTemps) ?? []
        let codes = try c.decodeIfPresent([Int].self, forKey: .hourCodes) ?? []
        if (0..<24).contains(start), !temps.isEmpty, temps.count == codes.count {
            hourStart = start
            hours = Array(zip(temps, codes).map(HourlyPoint.init(temp:code:))
                .prefix(Self.hourLimit))
        } else {
            hourStart = -1
            hours = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(PageKind.weather.rawValue, forKey: .kindID)
        try c.encode(age, forKey: .age)
        try c.encode(place, forKey: .place)
        try c.encode(reading.temp, forKey: .temp)
        try c.encode(reading.high, forKey: .high)
        try c.encode(reading.low, forKey: .low)
        try c.encode(reading.code, forKey: .code)
        try c.encode(reading.unit, forKey: .unit)
        guard hasHours else { return }
        try c.encode(hourStart, forKey: .hourStart)
        try c.encode(hours.map(\.temp), forKey: .hourTemps)
        try c.encode(hours.map(\.code), forKey: .hourCodes)
    }

    /// สองสิ่งที่บีบได้: แถบพยากรณ์ทั้งชุด แล้วจึงค่อยเป็นชื่อสถานที่
    ///
    /// ลำดับนี้ไม่ใช่เรื่องบังเอิญ — ชื่อเมืองบอกว่าตัวเลขทั้งหน้าพูดถึง *ที่ไหน* หน้าที่มี
    /// พยากรณ์ครบห้าช่องแต่ไม่มีชื่อเมืองคือหน้าที่ตอบไม่ได้ว่าเป็นอากาศของใคร
    /// และการทิ้งพยากรณ์ทีละคอลัมน์ก็ไม่ช่วย: สามคอลัมน์อ่านเป็นข้อมูลหาย ไม่ใช่ข้อมูลย่อ
    ///
    /// ชื่อเมืองมาจากบริการภายนอกและเป็นภาษาอะไรก็ได้ (ไทยกิน 3 ไบต์ต่อตัว)
    /// เฟรมที่ล้นแล้วถูกทิ้งเงียบๆ คือหน้าที่ไม่มีวันอัปเดต
    public func encoded(maxBytes: Int = Wire.maxPayload) throws -> Data {
        let encoder = Wire.encoder()
        var copy = self
        copy.place = Text.fit(place, to: Self.placeLimit)
        var data = try encoder.encode(copy)
        if data.count <= maxBytes { return data }

        copy.hourStart = -1
        copy.hours = []
        data = try encoder.encode(copy)
        if data.count <= maxBytes { return data }

        var limit = Text.displayWidth(copy.place)
        while limit > 0, data.count > maxBytes {
            limit -= 1
            copy.place = Text.clip(copy.place, to: limit)
            data = try encoder.encode(copy)
        }
        // ตัวเลขล้วนๆ ยังไม่พอ = เพดานที่ผู้เรียกให้มาเล็กกว่าเฟรมที่เล็กที่สุดที่เป็นไปได้
        // เฟรมที่ยาวเกินถูกบอร์ดทิ้งอยู่แล้ว การคืนมันเงียบๆ แค่ย้ายความล้มเหลวไปให้ไกลตา
        guard data.count <= maxBytes else { throw WeatherError.frameTooLong }
        return data
    }
}

/// สิ่งที่อาจผิดพลาดระหว่างทางไป Open-Meteo
public enum WeatherError: Error, Equatable, Sendable {
    /// ตอบกลับมาแต่ไม่ใช่รูปร่างที่เรารู้จัก — รวมทั้ง JSON พังและฟิลด์ที่หายไป
    case badPayload
    /// ชื่อเมืองที่ผู้ใช้พิมพ์ไม่ตรงกับที่ไหนเลย
    case noSuchPlace
    /// บีบจนไม่เหลือชื่อแล้วยังไม่พอดีหนึ่ง MTU — เพดานที่ให้มาเล็กกว่าที่เป็นไปได้
    case frameTooLong

    public var message: String {
        switch self {
        case .badPayload: return "the weather service sent something we cannot read"
        case .noSuchPlace: return "no place by that name"
        case .frameTooLong: return "the weather page does not fit one frame"
        }
    }
}

/// Open-Meteo — ที่อยู่ที่ยิงไป และการแปลงสิ่งที่ตอบกลับมา
///
/// เลือกบริการนี้เป็นหน้าแรกของรอบ multi-page เพราะไม่ต้องมี API key และไม่ต้องขอ
/// สิทธิ์ TCC ใดๆ ท่อทั้งเส้นจึงถูกพิสูจน์โดยไม่มีตัวแปรอื่นปน
///
/// ทุกอย่างที่นี่เป็นฟังก์ชันบริสุทธิ์ที่รับ bytes — เทสต์ป้อน fixture เข้าไปได้ตรงๆ
/// และไม่มีบรรทัดไหนใน `swift run tamatest` ที่แตะเครือข่ายจริง
public enum WeatherSource {
    /// รอบดึงของหน้าอากาศ — 15 นาที
    /// อากาศเปลี่ยนช้ากว่านั้นมาก และบริการนี้ให้ใช้ฟรีบนพื้นฐานว่าไม่ยิงถี่
    public static let interval: TimeInterval = 15 * 60

    public static func geocodeURL(_ name: String) -> URL? {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        c?.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return c?.url
    }

    public static func forecastURL(_ place: GeoPlace, unit: TempUnit) -> URL? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        var items = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", place.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            // แถวรายชั่วโมงเริ่มที่ *ชั่วโมงปัจจุบัน* เสมอ ดัชนี 0 จึงเป็นชั่วโมงที่ผ่านไปแล้ว
            // บางส่วน ซึ่งเลข `current` ด้านบนตอบไปแล้ว — ขอมา 6 เพื่อใช้ 1..5
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "forecast_hours", value: "\(WeatherFrame.hourLimit + 1)"),
            // สูงสุด/ต่ำสุด "ของวันนี้" ต้องเป็นวันของสถานที่นั้น ไม่ใช่ของ Mac
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        if unit != .celsius {
            items.append(URLQueryItem(name: "temperature_unit", value: unit.apiName))
        }
        c?.queryItems = items
        return c?.url
    }

    public static func place(from data: Data) throws -> GeoPlace {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw WeatherError.badPayload }
        // ไม่มีคีย์ `results` เลยคือ "หาไม่เจอ" ตามสัญญาของบริการ ไม่ใช่ payload พัง
        guard let list = object["results"] as? [[String: Any]], let first = list.first else {
            throw WeatherError.noSuchPlace
        }
        guard
            let lat = (first["latitude"] as? NSNumber)?.doubleValue,
            let lon = (first["longitude"] as? NSNumber)?.doubleValue
        else { throw WeatherError.badPayload }
        let name = (first["name"] as? String) ?? ""
        return GeoPlace(name: name, latitude: lat, longitude: lon)
    }

    public static func reading(from data: Data, unit: TempUnit) throws -> WeatherReading {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let current = object["current"] as? [String: Any],
            let daily = object["daily"] as? [String: Any],
            let temp = (current["temperature_2m"] as? NSNumber)?.doubleValue,
            let code = (current["weather_code"] as? NSNumber)?.intValue,
            let highs = daily["temperature_2m_max"] as? [Any],
            let lows = daily["temperature_2m_min"] as? [Any],
            let high = (highs.first as? NSNumber)?.doubleValue,
            let low = (lows.first as? NSNumber)?.doubleValue
        else { throw WeatherError.badPayload }
        return WeatherReading(
            temp: Int(temp.rounded()),
            high: Int(high.rounded()),
            low: Int(low.rounded()),
            code: code,
            unit: unit)
    }

    /// ห้าชั่วโมงข้างหน้าจากคำตอบก้อนเดียวกับ `reading` — คืน `(-1, [])` เมื่อใช้ไม่ได้
    ///
    /// **ไม่ throw** ต่างจากทุกอย่างอื่นในไฟล์นี้ และตั้งใจ: แถบพยากรณ์เป็นส่วนเสริมของหน้า
    /// ที่ตอบคำถามหลักได้อยู่แล้วด้วยเลขใหญ่ · ถ้าบล็อก `hourly` หายไปหรือเปลี่ยนรูป
    /// สิ่งที่ควรเกิดคือแถบล่างว่าง ไม่ใช่หน้าอากาศทั้งหน้าหยุดอัปเดต
    ///
    /// ชั่วโมงมาจากสตริงเวลาของบริการ ไม่ใช่จากนาฬิกาของ Mac — `timezone=auto` ทำให้
    /// มันเป็นเวลาของ *สถานที่นั้น* ซึ่งเป็นสิ่งเดียวที่ป้ายบนจอควรพูดถึง
    public static func hourly(from data: Data) -> (hourStart: Int, hours: [HourlyPoint]) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let block = object["hourly"] as? [String: Any],
            let times = block["time"] as? [Any],
            let temps = block["temperature_2m"] as? [Any],
            let codes = block["weather_code"] as? [Any]
        else { return (-1, []) }
        // ข้ามดัชนี 0 — ชั่วโมงปัจจุบันคือสิ่งที่เลขใหญ่บอกอยู่แล้ว
        let n = min(times.count, temps.count, codes.count)
        guard n > 1, let start = hour(from: times[1]) else { return (-1, []) }
        var out: [HourlyPoint] = []
        for i in 1..<min(n, WeatherFrame.hourLimit + 1) {
            guard
                let t = (temps[i] as? NSNumber)?.doubleValue,
                let c = (codes[i] as? NSNumber)?.intValue
            else { return (-1, []) }  // ช่องที่หายกลางแถบทำให้ทั้งแถบอ่านผิด ไม่ใช่แค่สั้นลง
            out.append(HourlyPoint(temp: Int(t.rounded()), code: c))
        }
        return out.isEmpty ? (-1, []) : (start, out)
    }

    /// "2026-08-03T13:00" -> 13 · nil เมื่อไม่ใช่รูปนั้น
    private static func hour(from value: Any) -> Int? {
        guard let s = value as? String, s.count >= 13 else { return nil }
        let chars = Array(s)
        guard chars[10] == "T" else { return nil }
        guard let h = Int(String(chars[11...12])), (0..<24).contains(h) else { return nil }
        return h
    }
}
