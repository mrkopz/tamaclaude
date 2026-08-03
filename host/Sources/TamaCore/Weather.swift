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
/// {"a":420,"g":1,"h":34,"l":26,"p":"Bangkok","t":31,"u":"C","w":61}
/// ```
public struct WeatherFrame: PageFrame, Equatable, Codable, Sendable {
    public var kind: PageKind { .weather }

    public var place: String
    public var reading: WeatherReading
    public var age: Int

    /// ชื่อสถานที่ยาวเกินความกว้างจอไม่มีประโยชน์ — วัดจากพื้นที่จริงใน
    /// `tools/layout.toml` (`[weather] place_x` ถึง `icon_x`) ผ่าน `tools/gen/weather.py`
    public static let placeLimit = 18

    public init(place: String, reading: WeatherReading, age: Int = 0) {
        self.place = place
        self.reading = reading
        self.age = age
    }

    enum CodingKeys: String, CodingKey {
        case kindID = "g"
        case age = "a"
        case place = "p"
        case temp = "t"
        case high = "h"
        case low = "l"
        case code = "w"
        case unit = "u"
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
    }

    /// เฟรมนี้มีข้อความชิ้นเดียวให้บีบ คือชื่อสถานที่ — ตัวเลขไม่มีทางทำให้ล้น
    ///
    /// ถึงอย่างนั้นก็ยังต้องมีทางบีบ: ชื่อเมืองมาจากบริการภายนอกและเป็นภาษาอะไรก็ได้
    /// (ไทยกิน 3 ไบต์ต่อตัว) เฟรมที่ล้นแล้วถูกทิ้งเงียบๆ คือหน้าที่ไม่มีวันอัปเดต
    public func encoded(maxBytes: Int = Wire.maxPayload) throws -> Data {
        let encoder = Wire.encoder()
        var copy = self
        copy.place = Text.fit(place, to: Self.placeLimit)
        var data = try encoder.encode(copy)
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
    /// รอบดึงของหน้าอากาศ — 15 นาที (docs/multi-page-screens.md)
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
}
