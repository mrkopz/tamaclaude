import Foundation

/// ราคาหนึ่งเหรียญที่ Mac อ่านมาได้จริงหนึ่งครั้ง
///
/// ราคาเป็น `Double` ไม่ใช่สตริงที่จัดรูปแล้ว เพราะจำนวนทศนิยมที่เหมาะสมขึ้นกับ *ขนาด*
/// ของราคา (BTC หกหลัก · DOGE ทศนิยมสี่ตำแหน่ง) และยังเป็นสิ่งที่ถูกลดลงตอนบีบเฟรม
/// การจัดรูปจึงต้องเกิดตอนเข้ารหัส ไม่ใช่ตอนอ่านค่ามา
public struct CryptoQuote: Equatable, Sendable {
    /// สัญลักษณ์ที่บริการเป็นคนบอก ไม่ใช่ที่ผู้ใช้พิมพ์ — คนที่พิมพ์ "bitcoin" ต้องเห็น BTC
    public var symbol: String
    public var price: Double
    /// เปอร์เซ็นต์เปลี่ยนแปลง 24 ชั่วโมง — บวกคือขึ้น
    public var change: Double

    public init(symbol: String, price: Double, change: Double) {
        self.symbol = symbol
        self.price = price
        self.change = change
    }
}

/// page frame ของหน้าคริปโต
///
/// ```
/// {"a":42,"c":[{"d":-21,"p":"64230","s":"BTC"}],"g":2}
/// ```
///
/// เปอร์เซ็นต์เดินทางเป็นจำนวนเต็มหน่วยสิบเท่า (-2.1% -> -21) ไม่ใช่ทศนิยม: บอร์ดไม่ต้อง
/// จัดรูปเลขทศนิยมเอง และเลขจำนวนเต็มมีความยาวที่คาดเดาได้ตอนวัดว่าเฟรมพอดีหรือยัง
public struct CryptoFrame: PageFrame, Equatable, Codable, Sendable {
    public var kind: PageKind { .crypto }

    public var quotes: [CryptoQuote]
    public var age: Int

    /// เพดานเดียวกับที่หน้าตั้งค่าบังคับ — ที่นี่เป็นด่านสุดท้าย ไม่ใช่ด่านเดียว
    public static let maxRows = 5
    /// สัญลักษณ์ยาวกว่านี้ไม่มีในตลาดจริง และคอลัมน์บนจอกว้างเท่านี้
    public static let symbolLimit = 5

    public init(quotes: [CryptoQuote], age: Int = 0) {
        self.quotes = Array(quotes.prefix(Self.maxRows))
        self.age = age
    }

    /// หนึ่งแถวอย่างที่มันอยู่บนสาย — ราคาเป็นสตริงที่จัดรูปแล้ว
    public struct Row: Equatable, Codable, Sendable {
        public var symbol: String
        public var price: String
        /// เปอร์เซ็นต์คูณสิบ ปัดเป็นจำนวนเต็ม
        public var change: Int

        enum CodingKeys: String, CodingKey {
            case symbol = "s"
            case price = "p"
            case change = "d"
        }
    }

    enum CodingKeys: String, CodingKey {
        case kindID = "g"
        case age = "a"
        case rows = "c"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(Int.self, forKey: .kindID)
        guard id == PageKind.crypto.rawValue else {
            throw DecodingError.dataCorruptedError(
                forKey: .kindID, in: c, debugDescription: "not a crypto frame")
        }
        age = try c.decode(Int.self, forKey: .age)
        quotes = try c.decode([Row].self, forKey: .rows).map {
            CryptoQuote(
                symbol: $0.symbol, price: Double($0.price) ?? 0,
                change: Double($0.change) / 10)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(PageKind.crypto.rawValue, forKey: .kindID)
        try c.encode(age, forKey: .age)
        try c.encode(rows(trim: 0, count: quotes.count), forKey: .rows)
    }

    /// จำนวนทศนิยมที่ราคาขนาดนี้ควรมี — เหรียญที่ราคาต่ำกว่าหนึ่งดอลลาร์เคลื่อนไหวใน
    /// ตำแหน่งที่เลขสองตำแหน่งมองไม่เห็น ส่วน BTC ที่มีทศนิยมสองตำแหน่งคือตัวเลขที่ยาว
    /// เกินคอลัมน์โดยไม่ได้บอกอะไรเพิ่ม
    public static func decimals(for price: Double) -> Int {
        let v = abs(price)
        if v >= 1000 { return 0 }
        if v >= 1 { return 2 }
        if v >= 0.01 { return 4 }
        return 6
    }

    public static func priceText(_ price: Double, trim: Int = 0) -> String {
        let places = max(0, decimals(for: price) - trim)
        return String(format: "%.\(places)f", price)
    }

    private func rows(trim: Int, count: Int) -> [Row] {
        quotes.prefix(count).map {
            Row(
                symbol: Text.fit($0.symbol, to: Self.symbolLimit),
                price: Self.priceText($0.price, trim: trim),
                // ปัดครึ่งขึ้นเสมอ ไม่ใช่ตัดทิ้ง — 0.04% ที่กลายเป็น 0 ยังอ่านว่านิ่ง
                // ซึ่งถูก ส่วน -0.04% ที่กลายเป็น 0 ต้องไม่กลายเป็น +0
                change: Int(($0.change * 10).rounded()))
        }
    }

    /// เฟรมนี้พอดีหนึ่ง MTU ด้วยลำดับการบีบที่ *ไม่* แตะสัญลักษณ์
    ///
    /// สัญลักษณ์คือสิ่งเดียวบนแถวที่บอกว่าตัวเลขข้างๆ เป็นของอะไร แถวที่เหลือแต่ราคา
    /// จึงไม่ใช่แถวที่บีบแล้ว แต่เป็นแถวที่โกหก ลำดับจึงเป็น:
    /// 1. ลดทศนิยมของราคาทุกแถวลงทีละขั้น (ตัวเลขหยาบขึ้นแต่ยังเป็นเรื่องจริง)
    /// 2. ตัดแถวท้ายทิ้งทั้งแถว (หายไปทั้งใบดีกว่าค้างอยู่ครึ่งใบ)
    /// ทั้งสองขั้นไม่เคยตัดตัวอักษรของสัญลักษณ์ออกแม้ตัวเดียว
    public func encoded(maxBytes: Int = Wire.maxPayload) throws -> Data {
        let encoder = Wire.encoder()
        var count = quotes.count
        while true {
            for trim in 0...6 {
                let data = try encoder.encode(Payload(frame: self, trim: trim, count: count))
                if data.count <= maxBytes { return data }
            }
            guard count > 0 else { throw CryptoError.frameTooLong }
            count -= 1
        }
    }

    /// ก้อนที่ถูกเข้ารหัสจริง — แยกจาก `encode(to:)` เพราะจำนวนทศนิยมกับจำนวนแถว
    /// เป็นผลของการวัดความยาว ซึ่ง `Encodable` ไม่มีที่ให้ส่งค่าพวกนี้เข้าไป
    private struct Payload: Encodable {
        let frame: CryptoFrame
        let trim: Int
        let count: Int

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(PageKind.crypto.rawValue, forKey: .kindID)
            try c.encode(frame.age, forKey: .age)
            try c.encode(frame.rows(trim: trim, count: count), forKey: .rows)
        }
    }
}

/// สิ่งที่อาจผิดพลาดระหว่างทางไป CoinGecko
public enum CryptoError: Error, Equatable, Sendable {
    /// ตอบกลับมาแต่ไม่ใช่รูปร่างที่เรารู้จัก — รวมทั้ง JSON พังและฟิลด์ที่หายไป
    case badPayload
    /// คำที่ผู้ใช้พิมพ์ไม่ตรงกับเหรียญไหนเลย
    case noSuchCoin
    /// บีบจนไม่เหลือแถวแล้วยังไม่พอดีหนึ่ง MTU — เพดานที่ให้มาเล็กกว่าที่เป็นไปได้
    case frameTooLong

    public var message: String {
        switch self {
        case .badPayload: return "the price service sent something we cannot read"
        case .noSuchCoin: return "no coin by that name"
        case .frameTooLong: return "the crypto page does not fit one frame"
        }
    }
}

/// CoinGecko — ที่อยู่ที่ยิงไป และการแปลงสิ่งที่ตอบกลับมา
///
/// ไม่ต้องมี API key เหมือน Open-Meteo ท่อของหน้านี้จึงเป็นท่อเดิมทั้งเส้น ต่างกันแค่
/// รอบดึงและรูปร่างของเฟรม (ADR-0001: Mac ดึง board ไม่เคยต่อเน็ตเอง)
///
/// ทุกอย่างที่นี่เป็นฟังก์ชันบริสุทธิ์ที่รับ bytes — เทสต์ป้อน fixture เข้าไปได้ตรงๆ
/// และไม่มีบรรทัดไหนใน `swift run tamatest` ที่แตะเครือข่ายจริง
public enum CryptoSource {
    /// รอบดึงของหน้าคริปโต — 60 วินาที ตลอดเวลา (docs/multi-page-screens.md)
    /// ตลาดคริปโตไม่มีเวลาปิด จึงไม่มีหน้าต่างเวลาทำการให้หยุดยิงเหมือนหน้าหุ้น
    public static let interval: TimeInterval = 60

    public static func searchURL(_ query: String) -> URL? {
        var c = URLComponents(string: "https://api.coingecko.com/api/v3/search")
        c?.queryItems = [URLQueryItem(name: "query", value: query)]
        return c?.url
    }

    /// ราคาของหลายเหรียญในคำขอเดียว — ต่างจากหน้าหุ้นที่ต้องยิงทีละสัญลักษณ์
    ///
    /// ใช้ `/coins/markets` ไม่ใช่ `/simple/price` เพราะมันคืน `symbol` มาด้วย ป้ายบนจอ
    /// จึงเป็นสัญลักษณ์ที่บริการรู้จัก ไม่ใช่คำที่ผู้ใช้พิมพ์ลงไป
    public static func marketsURL(ids: [String]) -> URL? {
        guard !ids.isEmpty else { return nil }
        var c = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")
        c?.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "ids", value: ids.joined(separator: ",")),
            URLQueryItem(name: "per_page", value: String(ids.count)),
            // หน้านี้แสดงราคากับเปอร์เซ็นต์เท่านั้น ของที่เหลือคือไบต์ที่ไม่มีใครอ่าน
            URLQueryItem(name: "sparkline", value: "false"),
        ]
        return c?.url
    }

    /// คำที่ผู้ใช้พิมพ์ -> id ของ CoinGecko
    ///
    /// เอาตัวแรกของ `coins` ตามที่บริการจัดอันดับมา ไม่ใช่ตัวที่ชื่อตรงเป๊ะ: คนที่พิมพ์
    /// "btc" ต้องได้ bitcoin ไม่ใช่เหรียญล้อเลียนที่บังเอิญชื่อ BTC เป๊ะกว่า
    public static func coinID(from data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CryptoError.badPayload }
        // ไม่มีคีย์ `coins` เลยคือ payload พัง ส่วนลิสต์ว่างคือ "หาไม่เจอ" ตามสัญญา
        // ของบริการ — สองอย่างนี้บอกผู้ใช้คนละเรื่อง (บริการล่ม vs พิมพ์ชื่อผิด)
        guard let list = object["coins"] as? [[String: Any]] else {
            throw CryptoError.badPayload
        }
        guard let id = list.first?["id"] as? String, !id.isEmpty else {
            throw CryptoError.noSuchCoin
        }
        return id
    }

    /// ราคาที่อ่านได้ เรียงตาม id — ผู้เรียกเป็นคนจัดลำดับตาม watchlist ของผู้ใช้อีกที
    ///
    /// เหรียญที่หายไปจากคำตอบไม่ใช่ payload พัง (บริการอาจเลิก list มันไปแล้ว) แต่
    /// คำตอบที่ไม่ใช่ลิสต์เลยคือพัง — ถ้ากลืนทั้งสองอย่างเป็นเงียบๆ เหมือนกัน หน้าจอ
    /// จะว่างเปล่าโดยไม่มีใครบอกได้ว่าเพราะอะไร
    public static func quotes(from data: Data) throws -> [String: CryptoQuote] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { throw CryptoError.badPayload }
        var out: [String: CryptoQuote] = [:]
        for item in list {
            guard
                let id = item["id"] as? String,
                let symbol = item["symbol"] as? String,
                let price = (item["current_price"] as? NSNumber)?.doubleValue
            else { continue }
            // เหรียญที่เพิ่งขึ้น list ยังไม่มีตัวเลข 24 ชั่วโมง — null คือศูนย์ในความหมาย
            // "ยังไม่ขยับเท่าที่รู้" ไม่ใช่ข้อมูลที่หายไป ราคายังจริงและยังต้องขึ้นจอ
            let change = (item["price_change_percentage_24h"] as? NSNumber)?.doubleValue ?? 0
            out[id] = CryptoQuote(symbol: symbol.uppercased(), price: price, change: change)
        }
        guard !out.isEmpty else { throw CryptoError.badPayload }
        return out
    }
}
