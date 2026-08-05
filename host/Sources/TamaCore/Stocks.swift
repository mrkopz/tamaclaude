import Foundation

/// ราคาหุ้นหนึ่งตัวที่ Mac อ่านมาได้จริงหนึ่งครั้ง
///
/// รูปเดียวกับ `CryptoQuote` โดยตั้งใจ — ราคาเป็น `Double` ไม่ใช่สตริงที่จัดรูปแล้ว
/// เพราะจำนวนทศนิยมเป็นสิ่งที่ถูกลดลงตอนบีบเฟรม การจัดรูปจึงเกิดตอนเข้ารหัส
public struct StockQuote: Equatable, Sendable {
    /// สัญลักษณ์อย่างที่ตลาดเรียก — ผู้ใช้พิมพ์ "aapl" ก็ต้องเห็น AAPL
    public var symbol: String
    public var price: Double
    /// เปอร์เซ็นต์เปลี่ยนแปลงจากราคาปิดครั้งก่อน — บวกคือขึ้น
    public var change: Double

    public init(symbol: String, price: Double, change: Double) {
        self.symbol = symbol
        self.price = price
        self.change = change
    }
}

/// page frame ของหน้าหุ้น
///
/// ```
/// {"a":42,"c":[{"d":-21,"p":"189.44","s":"AAPL"}],"g":4,"k":1}
/// ```
///
/// เหมือนหน้าคริปโตทุกอย่าง บวกคีย์เดียว: `k` คือ "ตลาดปิดอยู่" ซึ่งเป็นเหตุผลที่ตัวเลข
/// ชุดนี้จะไม่ขยับอีกจนกว่าตลาดจะเปิด — อายุข้อมูลที่โตขึ้นเรื่อยๆ ตอนตลาดปิดไม่ได้แปลว่า
/// ท่อพัง และหน้าจอต้องแยกสองอย่างนี้ให้ผู้ใช้เห็น ไม่ใช่ให้เขาไปเปิดปฏิทินตลาดเอง
public struct StocksFrame: PageFrame, Equatable, Codable, Sendable {
    public var kind: PageKind { .stocks }

    public var quotes: [StockQuote]
    public var age: Int
    /// ตลาดปิดอยู่ตอนที่ Mac อ่านค่านี้มา — ตัวเลขค้างเพราะไม่มีอะไรให้ขยับ
    public var marketClosed: Bool

    /// เพดานเดียวกับที่หน้าตั้งค่าบังคับ — ที่นี่เป็นด่านสุดท้าย ไม่ใช่ด่านเดียว
    public static let maxRows = 5
    /// สัญลักษณ์ของตลาดสหรัฐยาวสุดห้าตัว ("BRK.B") และคอลัมน์บนจอกว้างเท่านั้นพอดี
    ///
    /// ตัวที่ยาวกว่านี้ถูกตัดตอน *ประกอบแถว* ครั้งเดียว ไม่ใช่ตอนบีบเฟรม — การบีบไม่เคย
    /// ทำให้ป้ายสั้นลงกว่าที่หน้าจอแสดงได้อยู่แล้ว
    public static let symbolLimit = 5

    public init(quotes: [StockQuote], age: Int = 0, marketClosed: Bool = false) {
        self.quotes = Array(quotes.prefix(Self.maxRows))
        self.age = age
        self.marketClosed = marketClosed
    }

    /// หนึ่งแถวอย่างที่มันอยู่บนสาย — ราคาเป็นสตริงที่จัดรูปแล้ว
    ///
    /// `change` เป็น optional เพราะเปอร์เซ็นต์คือสิ่งแรกที่ถูกทิ้งตอนบีบเฟรม แถวที่ไม่มี
    /// มันยังเป็นแถวที่จริง (สัญลักษณ์ + ราคา) ต่างจากแถวที่เสียสัญลักษณ์ไปซึ่งเป็นแถวที่โกหก
    public struct Row: Equatable, Codable, Sendable {
        public var symbol: String
        public var price: String
        /// เปอร์เซ็นต์คูณสิบ ปัดเป็นจำนวนเต็ม
        public var change: Int?

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
        case closed = "k"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(Int.self, forKey: .kindID)
        guard id == PageKind.stocks.rawValue else {
            throw DecodingError.dataCorruptedError(
                forKey: .kindID, in: c, debugDescription: "not a stocks frame")
        }
        age = try c.decode(Int.self, forKey: .age)
        // ไม่มีคีย์ `k` คือตลาดเปิด — เฟรมส่วนใหญ่ของวันทำการจึงไม่ต้องแบกไบต์นี้ไปด้วย
        marketClosed = (try c.decodeIfPresent(Int.self, forKey: .closed) ?? 0) != 0
        quotes = try c.decode([Row].self, forKey: .rows).map {
            StockQuote(
                symbol: $0.symbol, price: Double($0.price) ?? 0,
                change: Double($0.change ?? 0) / 10)
        }
    }

    public func encode(to encoder: Encoder) throws {
        try Payload(frame: self, trim: 0, percent: true, count: quotes.count).encode(to: encoder)
    }

    /// จำนวนทศนิยมของราคาหุ้น — **สองตำแหน่งเสมอ** ซึ่งคือหน่วยที่ตลาดซื้อขายกันจริง
    ///
    /// ไม่มีขั้นทศนิยมหกตำแหน่งแบบคริปโต: หุ้นสหรัฐที่ราคาต่ำกว่าหนึ่งเซนต์ไม่ได้อยู่ใน
    /// รายการที่แผนฟรีของ Finnhub ครอบคลุม · และไม่มีขั้นศูนย์ตำแหน่งอีกแล้ว — หุ้นห้าหลัก
    /// ที่ปัดสตางค์ทิ้งอ่านเป็นราคาคนละตัวกับที่ผู้ใช้เห็นในโบรกเกอร์ ส่วนความยาวที่เพิ่มมา
    /// สามตัวเป็นเรื่องของเลย์เอาต์ ซึ่งการ์ดแก้ด้วยการหั่นฟอนต์สองขนาดไปแล้ว
    public static func decimals(for price: Double) -> Int { 2 }

    /// `trim` ไม่มีผลกับหุ้น — ทศนิยมถูกตรึงไว้ที่สองตำแหน่ง
    ///
    /// พารามิเตอร์ยังอยู่เพราะลำดับการบีบเฟรมเรียกมันเป็นขั้นแรกอยู่ (`encoded`) การลบทิ้ง
    /// แปลว่าต้องแยกลูปบีบของสองหน้าออกจากกัน ทั้งที่ขั้นที่เหลือยังเหมือนกันทุกขั้น
    public static func priceText(_ price: Double, trim: Int = 0) -> String {
        // ตัวคั่นหลักพันเหมือนหน้าคริปโต — สองหน้านี้ผู้ใช้ปัดสลับไปมา ตัวเลขต้องอ่านเหมือนกัน
        Text.grouped(String(format: "%.\(decimals(for: price))f", price))
    }

    private func rows(trim: Int, percent: Bool, count: Int) -> [Row] {
        quotes.prefix(count).map {
            Row(
                symbol: Text.fit($0.symbol, to: Self.symbolLimit),
                price: Self.priceText($0.price, trim: trim),
                // ปัดครึ่งขึ้นเสมอ ไม่ใช่ตัดทิ้ง — 0.04% ที่กลายเป็น 0 ยังอ่านว่านิ่ง
                // ซึ่งถูก ส่วน -0.04% ที่กลายเป็น 0 ต้องไม่กลายเป็น +0
                change: percent ? Int(($0.change * 10).rounded()) : nil)
        }
    }

    /// เฟรมนี้พอดีหนึ่ง MTU ด้วยลำดับการบีบที่ *ไม่* แตะสัญลักษณ์
    ///
    /// ลำดับต่างจากหน้าคริปโตหนึ่งขั้น เพราะของที่ทิ้งได้ต่างกัน:
    /// 1. ลดทศนิยมของราคาทุกแถว (189.44 -> 189 ยังเป็นราคาที่ใช้ตัดสินใจได้)
    /// 2. ทิ้งเปอร์เซ็นต์ทั้งคอลัมน์ (ราคายังอยู่ครบ ส่วนทิศทางหายไปทั้งหน้า ไม่ใช่บางแถว
    ///    ซึ่งจะอ่านว่าแถวนั้นนิ่ง)
    /// 3. ตัดแถวท้ายทิ้งทั้งแถว (หายไปทั้งใบดีกว่าค้างอยู่ครึ่งใบ)
    /// ทั้งสามขั้นไม่เคยตัดตัวอักษรของสัญลักษณ์ออกแม้ตัวเดียว
    public func encoded(maxBytes: Int = Wire.maxPayload) throws -> Data {
        let encoder = Wire.encoder()
        var count = quotes.count
        while true {
            for percent in [true, false] {
                for trim in 0...2 {
                    let payload = Payload(
                        frame: self, trim: trim, percent: percent, count: count)
                    let data = try encoder.encode(payload)
                    if data.count <= maxBytes { return data }
                }
            }
            guard count > 0 else { throw StocksError.frameTooLong }
            count -= 1
        }
    }

    /// ก้อนที่ถูกเข้ารหัสจริง — แยกจาก `encode(to:)` เพราะจำนวนทศนิยม การมีเปอร์เซ็นต์
    /// และจำนวนแถวเป็นผลของการวัดความยาว ซึ่ง `Encodable` ไม่มีที่ให้ส่งค่าพวกนี้เข้าไป
    private struct Payload: Encodable {
        let frame: StocksFrame
        let trim: Int
        let percent: Bool
        let count: Int

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(PageKind.stocks.rawValue, forKey: .kindID)
            try c.encode(frame.age, forKey: .age)
            try c.encode(frame.rows(trim: trim, percent: percent, count: count), forKey: .rows)
            // ตลาดเปิดคือสภาพปกติ จึงเป็น "ไม่มีคีย์" ไม่ใช่ `"k":0`
            if frame.marketClosed { try c.encode(1, forKey: .closed) }
        }
    }
}

/// สิ่งที่อาจผิดพลาดระหว่างทางไป Finnhub
public enum StocksError: Error, Equatable, Sendable {
    /// ตอบกลับมาแต่ไม่ใช่รูปร่างที่เรารู้จัก — รวมทั้ง JSON พังและฟิลด์ที่หายไป
    case badPayload
    /// สัญลักษณ์นี้ไม่มีราคา — พิมพ์ผิด หรืออยู่นอกตลาดที่แผนฟรีครอบคลุม
    case noSuchSymbol
    /// ปลายทางปฏิเสธ key — หมดอายุ พิมพ์ผิด หรือถูกเพิกถอน
    ///
    /// ต้องแยกจาก `badPayload` ให้ได้โดยไม่ต้องอ่านข้อความ: อันหนึ่งผู้ใช้ต้องไปทำอะไร
    /// สักอย่าง อีกอันรอสักครู่ก็หายเอง
    case keyRejected
    /// ยิงถี่เกินโควตาของแผนฟรี — รอบหน้าค่อยว่ากัน
    case rateLimited
    /// บีบจนไม่เหลือแถวแล้วยังไม่พอดีหนึ่ง MTU — เพดานที่ให้มาเล็กกว่าที่เป็นไปได้
    case frameTooLong

    public var message: String {
        switch self {
        case .badPayload: return "the quote service sent something we cannot read"
        case .noSuchSymbol: return "no symbol by that name"
        case .keyRejected:
            return "Finnhub refused the key — set a new one in the Stocks tab"
        case .rateLimited: return "Finnhub is rate limiting us; the next round will try again"
        case .frameTooLong: return "the stocks page does not fit one frame"
        }
    }
}

/// เวลาทำการของตลาดหุ้นสหรัฐ — ตรรกะล้วน ถูกป้อนเวลาเข้าไป ไม่มีนาฬิกาของตัวเอง
///
/// นี่คือเหตุผลที่หน้าหุ้นต่างจากหน้าคริปโต: `/quote` ของ Finnhub คืนทีละสัญลักษณ์ รอบ
/// หนึ่งจึงเป็นห้าคำขอ การยิงตอนตลาดปิดคือการเผาโควตาของผู้ใช้เพื่อรับตัวเลขชุดเดิม
///
/// **วันหยุดของตลาดไม่ได้ถูกจำลองไว้** โดยรู้ตัว: ตารางวันหยุดต้องอัปเดตทุกปีและมีวันที่
/// คำนวณจากอีสเตอร์ (Good Friday) ราคาที่ค้างอยู่แล้วในวันหยุดยังถูกป้ายว่าเก่าตามปกติ
/// ส่วนต้นทุนคือโควตาของวันที่ไม่มีใครใช้อยู่แล้ว ประมาณสิบวันต่อปี
public enum MarketHours {
    /// เขตเวลาของตลาด ไม่ใช่ของผู้ใช้ — คนที่นั่งอยู่กรุงเทพต้องได้เวลาเปิดปิดชุดเดียวกับ
    /// คนที่นั่งอยู่นิวยอร์ก และ DST ของสหรัฐเลื่อนไม่พร้อมกับที่ไหนเลย
    public static let exchange = TimeZone(identifier: "America/New_York")!

    /// นาทีนับจากเที่ยงคืนตามเวลาตลาด — 09:30 ถึง 16:00 คือรอบซื้อขายปกติ
    ///
    /// ไม่รวม pre-market และ after-hours: แผนฟรีของ Finnhub ไม่ได้ให้ราคาช่วงนั้นอยู่แล้ว
    static let open = 9 * 60 + 30
    static let close = 16 * 60

    public static func isOpen(_ date: Date) -> Bool {
        // ปฏิทิน Gregorian ตรงๆ ไม่ใช่ `Calendar.current` — เครื่องที่ตั้งเป็นปฏิทินไทย
        // อ่านวันในสัปดาห์ไม่ตรงกับที่ตลาดใช้
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = exchange
        let parts = cal.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute
        else { return false }
        // 1 = อาทิตย์, 7 = เสาร์ ตามปฏิทิน Gregorian ของ Foundation
        guard weekday != 1, weekday != 7 else { return false }
        let at = hour * 60 + minute
        return at >= open && at < close
    }
}

/// Finnhub — ที่อยู่ที่ยิงไป และการแปลงสิ่งที่ตอบกลับมา
///
/// ต่างจาก CoinGecko สองข้อ: ต้องมี key ของผู้ใช้ และ `/quote` คืนทีละสัญลักษณ์ ข้อหลัง
/// คือเหตุผลของเพดานห้าตัว — มันคืองบต่อรอบ ไม่ใช่ความสวยงามของหน้าจอ
///
/// ทุกอย่างที่นี่เป็นฟังก์ชันบริสุทธิ์ที่รับ bytes — เทสต์ป้อน fixture เข้าไปได้ตรงๆ
/// และไม่มีบรรทัดไหนใน `swift run tamatest` ที่แตะเครือข่ายจริง
public enum StocksSource {
    /// รอบดึงของหน้าหุ้น — 60 วินาที *เฉพาะตอนตลาดเปิด*
    public static let interval: TimeInterval = 60

    /// key เดินทางเป็น query parameter เพราะนั่นคือสิ่งที่ Finnhub รับ — URL ก้อนนี้จึง
    /// เป็นความลับ ห้ามลง log ผู้เรียกทุกคนต้องถือมันเหมือนถือตัว key เอง
    public static func quoteURL(symbol: String, token: String) -> URL? {
        let name = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !name.isEmpty, !token.isEmpty else { return nil }
        var c = URLComponents(string: "https://finnhub.io/api/v1/quote")
        c?.queryItems = [
            URLQueryItem(name: "symbol", value: name),
            URLQueryItem(name: "token", value: token),
        ]
        return c?.url
    }

    /// ที่อยู่ก้อนเดียวกันโดยไม่มี key — สิ่งเดียวที่เอาไปเขียน log ได้
    public static func describe(_ url: URL) -> String {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.path
        }
        let kept = c.queryItems?.filter { $0.name != "token" }
        c.queryItems = kept
        return c.url?.absoluteString ?? url.path
    }

    /// คำตอบของ `/quote` หนึ่งก้อน -> ราคาหนึ่งตัว
    ///
    /// สัญลักษณ์ที่ Finnhub ไม่รู้จักไม่ได้ตอบ 404 แต่ตอบเลขศูนย์ทั้งก้อน — ราคาศูนย์
    /// พร้อมราคาปิดครั้งก่อนศูนย์ไม่ใช่หุ้นที่ราคาตก แต่คือหุ้นที่ไม่มีอยู่
    public static func quote(symbol: String, from data: Data) throws -> StockQuote {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw StocksError.badPayload }
        guard let price = (object["c"] as? NSNumber)?.doubleValue else {
            throw StocksError.badPayload
        }
        let previous = (object["pc"] as? NSNumber)?.doubleValue ?? 0
        guard price > 0 || previous > 0 else { throw StocksError.noSuchSymbol }
        // `dp` เป็น null ได้ตอนที่ยังไม่มีราคาปิดครั้งก่อนให้เทียบ (หุ้นที่เพิ่ง IPO วันนี้) —
        // ศูนย์ในความหมาย "ยังไม่ขยับเท่าที่รู้" ราคายังจริงและยังต้องขึ้นจอ
        let change = (object["dp"] as? NSNumber)?.doubleValue ?? 0
        return StockQuote(
            symbol: symbol.trimmingCharacters(in: .whitespaces).uppercased(), price: price,
            change: change)
    }
}
