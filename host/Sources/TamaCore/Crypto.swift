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
    /// รูป 24 ชั่วโมงเป็นระดับ 0..15 · ว่าง = ไม่มีประวัติ ซึ่งบอร์ดวาดเป็นเส้นฐานเปล่า
    ///
    /// เป็น *ระดับ* ไม่ใช่ราคา เพราะบอร์ดไม่เคยต้องรู้ราคาในอดีต มันวาดแต่รูป และระดับ
    /// 0..15 ลงได้พอดี nibble เดียวบนสาย (`CryptoFrame.sparkText`)
    public var spark: [Int]

    public init(symbol: String, price: Double, change: Double, spark: [Int] = []) {
        self.symbol = symbol
        self.price = price
        self.change = change
        self.spark = spark
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
    /// จำนวนจุดของรูป 24 ชั่วโมงที่เดินทางบนสาย
    ///
    /// **ต้องเท่ากับ `[crypto] spark_cols` ใน layout.toml** ซึ่งกำหนดขนาดอาร์เรย์ฝั่ง C
    /// จุดที่เกินมาคือไบต์ที่บอร์ดทิ้ง `tamatest` อ่าน layout.h มาตรวจ เหมือนที่ทำกับ
    /// จำนวนคอลัมน์ของแถบพยากรณ์อากาศ
    public static let sparkPoints = 16

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
        /// ระดับ 0..15 ตัวละ hex nibble · `nil` = แถวนี้ไม่มีรูป (ไม่มีประวัติ หรือถูกบีบทิ้ง)
        /// สองกรณีนั้นหน้าตาบนจอเหมือนกัน บอร์ดจึงไม่ต้องแยก
        public var spark: String?

        enum CodingKeys: String, CodingKey {
            case symbol = "s"
            case price = "p"
            case change = "d"
            case spark = "k"
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
                change: Double($0.change) / 10,
                spark: Self.sparkLevels($0.spark))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(PageKind.crypto.rawValue, forKey: .kindID)
        try c.encode(age, forKey: .age)
        try c.encode(rows(trim: 0, count: quotes.count, spark: true), forKey: .rows)
    }

    /// จำนวนทศนิยมที่ราคาขนาดนี้ควรมี
    ///
    /// **ราคาตั้งแต่ 1 ขึ้นไปได้สองตำแหน่งเสมอ** ไม่มีขั้นที่ปัดสตางค์ทิ้งอีกแล้ว — BTC ที่
    /// อ่านว่า `64230` เป็นราคาคนละตัวกับที่ผู้ใช้เห็นในกระดาน และความยาวที่เพิ่มมาสามตัว
    /// เป็นเรื่องของเลย์เอาต์ ซึ่งการ์ดแก้ด้วยการหั่นฟอนต์สองขนาดไปแล้ว (`int_font`/`frac_font`)
    ///
    /// ต่ำกว่า 1 ยังได้ความจริงเต็ม: เหรียญที่ราคา 0.000008 ถ้าถูกตรึงไว้ที่สองตำแหน่งจะ
    /// อ่านว่า `0.00` ตลอดกาล ทั้งที่เปอร์เซ็นต์ข้างมันบอกว่าขยับ 14% — ตัวเลขที่ไม่บอกอะไร
    /// เลยแย่กว่าตัวเลขที่ยาว
    public static func decimals(for price: Double) -> Int {
        let v = abs(price)
        if v >= 1 { return 2 }
        if v >= 0.01 { return 4 }
        return 6
    }

    /// `trim` ลดได้เฉพาะราคาที่ **ต่ำกว่า 1** — สองตำแหน่งของราคาที่เหลือเป็นสัญญากับผู้ใช้
    /// ไม่ใช่ที่ว่างให้ตัดตอนบีบเฟรม · ขั้นบีบนี้จึงคมกว่าเดิมมาก และเป็นเหตุผลที่ `encoded`
    /// ต้องมีขั้น "ทิ้ง sparkline" มาคั่นก่อนถึงจะไปถึงขั้นตัดแถวทิ้ง
    /// ตัวคั่นหลักพันเติมที่นี่ ไม่ใช่บนบอร์ด — บอร์ดได้สตริงที่พร้อมวาดแล้วเสมอ
    /// ซึ่งเป็นกติกาเดิมของหน้านี้ (ดูหมายเหตุที่ `CryptoQuote.price`)
    public static func priceText(_ price: Double, trim: Int = 0) -> String {
        let full = decimals(for: price)
        let places = abs(price) >= 1 ? full : max(2, full - trim)
        return Text.grouped(String(format: "%.\(places)f", price))
    }

    private func rows(trim: Int, count: Int, spark: Bool) -> [Row] {
        quotes.prefix(count).map {
            Row(
                symbol: Text.fit($0.symbol, to: Self.symbolLimit),
                price: Self.priceText($0.price, trim: trim),
                // ปัดครึ่งขึ้นเสมอ ไม่ใช่ตัดทิ้ง — 0.04% ที่กลายเป็น 0 ยังอ่านว่านิ่ง
                // ซึ่งถูก ส่วน -0.04% ที่กลายเป็น 0 ต้องไม่กลายเป็น +0
                change: Int(($0.change * 10).rounded()),
                spark: spark ? Self.sparkText($0.spark) : nil)
        }
    }

    /// ระดับ 0..15 -> hex nibble ต่อจุด · ว่างเปล่าคืน `nil` ไม่ใช่ `""` — คีย์ที่ไม่มี
    /// ประหยัดกว่าคีย์ที่มีค่าว่าง และบอร์ดอ่านทั้งสองแบบเป็น "ไม่มีรูป" เหมือนกันอยู่แล้ว
    static func sparkText(_ levels: [Int]) -> String? {
        guard !levels.isEmpty else { return nil }
        return String(levels.map { Character(String(min(max($0, 0), 15), radix: 16)) })
    }

    static func sparkLevels(_ text: String?) -> [Int] {
        guard let text else { return [] }
        var out: [Int] = []
        for c in text {
            guard let v = c.hexDigitValue else { return [] }
            out.append(v)
        }
        return out
    }

    /// เฟรมนี้พอดีหนึ่ง MTU ด้วยลำดับการบีบที่ *ไม่* แตะสัญลักษณ์
    ///
    /// สัญลักษณ์คือสิ่งเดียวบนแถวที่บอกว่าตัวเลขข้างๆ เป็นของอะไร แถวที่เหลือแต่ราคา
    /// จึงไม่ใช่แถวที่บีบแล้ว แต่เป็นแถวที่โกหก ลำดับจึงเป็น:
    /// 1. ลดทศนิยมของราคาที่ **ต่ำกว่า 1** ลงทีละขั้น (หยาบขึ้นแต่ยังเป็นเรื่องจริง) —
    ///    ราคาตั้งแต่ 1 ขึ้นไปถูกตรึงไว้ที่สองตำแหน่ง ขั้นนี้จึงคมกว่าที่เคยเป็นมาก
    /// 2. ทิ้ง sparkline ของทุกแถว (หน้ายังตอบครบ แค่ไม่มีรูปให้ดู)
    /// 3. ตัดแถวท้ายทิ้งทั้งแถว (หายไปทั้งใบดีกว่าค้างอยู่ครึ่งใบ)
    ///
    /// รูปถูกทิ้งก่อนแถวเสมอ: แถวที่หายคือเหรียญที่หายไปทั้งใบ ส่วนรูปที่หายคือคำถามหนึ่งข้อ
    /// ("ขยับยังไง") ที่ตอบไม่ได้ ขณะที่อีกสองข้อ ("ราคาเท่าไร" "ขึ้นหรือลง") ยังตอบได้ครบ
    /// ทุกขั้นไม่เคยตัดตัวอักษรของสัญลักษณ์ออกแม้ตัวเดียว
    public func encoded(maxBytes: Int = Wire.maxPayload) throws -> Data {
        let encoder = Wire.encoder()
        var count = quotes.count
        while true {
            for spark in [true, false] {
                for trim in 0...4 {
                    let data = try encoder.encode(
                        Payload(frame: self, trim: trim, count: count, spark: spark))
                    if data.count <= maxBytes { return data }
                }
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
        let spark: Bool

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(PageKind.crypto.rawValue, forKey: .kindID)
            try c.encode(frame.age, forKey: .age)
            try c.encode(frame.rows(trim: trim, count: count, spark: spark), forKey: .rows)
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
    /// รอบดึงของหน้าคริปโต — 60 วินาที ตลอดเวลา
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
            // ขอรูปมาด้วย: มันมาในคำขอเดิม ไม่ใช่คำขอที่สอง ซึ่งสำคัญกับโควตาของแผนฟรี
            // (`/coins/{id}/market_chart` ให้ 24 ชม. ตรงๆ แต่ยิงทีละเหรียญ = ห้าคำขอต่อนาที)
            URLQueryItem(name: "sparkline", value: "true"),
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
            let series = (item["sparkline_in_7d"] as? [String: Any])?["price"] as? [Any]
            out[id] = CryptoQuote(
                symbol: symbol.uppercased(), price: price, change: change,
                spark: spark(from: series, now: price))
        }
        guard !out.isEmpty else { throw CryptoError.badPayload }
        return out
    }

    /// อนุกรมรายชั่วโมง 7 วันของ CoinGecko -> ระดับ 0..15 สิบหกจุดของ *24 ชั่วโมงหลัง*
    ///
    /// CoinGecko ไม่มีอนุกรม 24 ชั่วโมงในคำขอเดียวกับราคา มีแต่ 7 วันรายชั่วโมง การตัด
    /// 24 ตัวท้ายจึงเป็นวิธีเดียวที่ได้หน้าต่างที่ถูกโดยไม่ต้องยิงคำขอที่สองต่อเหรียญ
    ///
    /// จุดสุดท้ายถูกแทนด้วย `now` เสมอ: อนุกรมอัปเดตช้ากว่า `current_price` และถ้าปล่อย
    /// ไว้ แท่งสุดท้ายจะไม่ตรงกับเปอร์เซ็นต์ที่พิมพ์อยู่ข้างมันเป็นบางครั้ง ซึ่งทำลายสิ่งเดียว
    /// ที่ทำให้รูปกับตัวเลขอ่านเป็นประโยคเดียวกันได้ (ดู `ct_trend_spark`)
    ///
    /// quantize หลัง fold ไม่ใช่ก่อน — ระดับ 0 กับ 15 ต้องปรากฏใน *จุดที่ถูกวาดจริง*
    /// ไม่งั้นรูปจะไม่เคยเต็มกล่องเลยเมื่อจุดสูงสุดตกอยู่ระหว่างจุดที่เลือกมา
    /// ระดับสูงสุดที่ nibble หนึ่งตัวเก็บได้ — ตรงกับ CT_TREND_SPARK_MAX ฝั่งบอร์ด
    public static let sparkMax = 15

    public static func spark(from series: [Any]?, now: Double) -> [Int] {
        guard let series, series.count >= CryptoFrame.sparkPoints else { return [] }
        var day = series.suffix(24).map { ($0 as? NSNumber)?.doubleValue ?? 0 }
        guard !day.contains(where: { !$0.isFinite || $0 <= 0 }) else { return [] }
        day[day.count - 1] = now

        let cols = CryptoFrame.sparkPoints
        let n = day.count
        // ปัดครึ่งขึ้นด้วยเลขจำนวนเต็ม ต้องได้ดัชนีชุดเดียวกับ `ct_trend_fold` และ
        // `gen/trend.py:fold` เป๊ะ — ปลายทั้งสองต้องถูกเก็บไว้เสมอ
        let picked: [Double] = n <= cols
            ? day
            : (0..<cols).map { day[(($0 * (n - 1) * 2) + (cols - 1)) / (2 * (cols - 1))] }

        guard let lo = picked.min(), let hi = picked.max() else { return [] }
        // ราคานิ่งสนิททั้งวัน: ทุกจุดอยู่กลางกล่อง ซึ่งแปลว่าไม่มีแท่งไหนถูกวาดเลย เหลือ
        // แต่เส้นฐาน — เป็นภาพที่ถูก ไม่ใช่ภาพที่พัง
        guard hi > lo else { return picked.map { _ in Self.sparkMax / 2 } }
        return picked.map { Int((($0 - lo) / (hi - lo) * Double(Self.sparkMax)).rounded()) }
    }
}
