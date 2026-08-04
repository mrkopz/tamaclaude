import Foundation

/// watchlist ของหน้าคริปโต — อยู่ใน `UserDefaults` เท่านั้น และแอปเป็นบรรณาธิการเดียว
///
/// เหตุผลเดียวกับ `WeatherSettings`: ค่าพวกนี้มี GUI เต็มรูปแบบ การมีไฟล์ให้แก้มืออีกทาง
/// จะทำให้หน้าต่างโชว์เหรียญชุดหนึ่งขณะที่จอแสดงอีกชุดหนึ่ง
///
/// "เปิด/ปิดหน้านี้" ไม่ได้อยู่ที่นี่ — เป็นข้อเดียวกับที่ถามทุกหน้า จึงอยู่ใน `PageSettings`
public struct CryptoSettings: Equatable, Sendable {
    /// คำที่ผู้ใช้พิมพ์ เช่น "btc" หรือ "bitcoin" — ยังไม่ใช่ id ของบริการ
    /// การแปลงเป็น id เกิดครั้งเดียวใน `CryptoService` แล้วถูกจำไว้
    public private(set) var coins: [String]

    /// เพดานห้าตัว — บังคับที่นี่ ไม่ใช่ที่หน้าต่าง เพราะประตูเข้าออกของค่านี้มีหลายบาน
    /// (หน้าตั้งค่า · ค่าที่โหลดจาก `UserDefaults` ของแอปรุ่นก่อน) แต่กติกามีข้อเดียว
    ///
    /// ตัวเลขนี้ไม่ใช่ความชอบ: มันคือสิ่งที่ทำให้เฟรมพอดี 500 ไบต์แน่นอน และทำให้
    /// จำนวนคำขอต่อรอบเป็นค่าคงที่ที่คำนวณล่วงหน้าได้ (DESIGN.md "หลายหน้าบนจอเดียว")
    public static let maxCoins = 5

    public init(coins: [String] = []) {
        var seen: Set<String> = []
        var out: [String] = []
        for raw in coins {
            let name = raw.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            out.append(name)
            if out.count == Self.maxCoins { break }
        }
        self.coins = out
    }

    /// ยังไม่ได้ใส่เหรียญเลย = ยังไม่มีอะไรให้ดึง (หน้านี้เปิดอยู่ไหมเป็นคำถามคนละข้อ)
    public var isUsable: Bool { !coins.isEmpty }

    /// ย้ายเหรียญขึ้นหรือลงหนึ่งขั้น — นอกขอบคือไม่มีอะไรเกิดขึ้น ไม่ใช่วนไปอีกฝั่ง
    /// (กติกาเดียวกับการจัดลำดับหน้าใน `PageSettings`)
    public mutating func move(_ index: Int, by step: Int) {
        let to = index + step
        guard coins.indices.contains(index), coins.indices.contains(to) else { return }
        coins.swapAt(index, to)
    }

    public mutating func remove(_ index: Int) {
        guard coins.indices.contains(index) else { return }
        coins.remove(at: index)
    }

    /// คืน `false` เมื่อเต็มเพดานแล้วหรือมีตัวนี้อยู่แล้ว — ผู้เรียกเอาไปบอกผู้ใช้ได้ว่าทำไม
    /// การกดปุ่มถึงไม่เกิดอะไรขึ้น
    @discardableResult
    public mutating func add(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, coins.count < Self.maxCoins else { return false }
        guard !coins.contains(where: { $0.lowercased() == name.lowercased() }) else {
            return false
        }
        coins.append(name)
        return true
    }

    public enum Key {
        public static let coins = "cryptoCoins"
    }

    public static func load(_ defaults: UserDefaults = .standard) -> CryptoSettings {
        CryptoSettings(coins: defaults.array(forKey: Key.coins) as? [String] ?? [])
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(coins, forKey: Key.coins)
    }
}

/// หน้าคริปโตฝั่ง Mac: ดึง CoinGecko ทุก 60 วินาที แล้ววาง page frame ไว้ให้ `PageHub`
///
/// รูปร่างเดียวกับ `WeatherService` ทุกส่วน — ตัวจัดตารางที่ถูกป้อนเวลา (`FetchSchedule`)
/// การยิงจริงที่เข้ามาทาง closure และการแปลงที่เป็นฟังก์ชันบริสุทธิ์ ใบนี้เป็นตัวตั้งรูปของ
/// "หน้าที่มี watchlist" ซึ่งหน้าหุ้นจะยืมไปใช้ต่อ
public final class CryptoService {
    public typealias Fetcher = (URL, @escaping (Result<Data, Error>) -> Void) -> Void

    /// มีเฟรมใหม่ — `observedAt` คือตอนที่ค่านี้ถูกอ่านมาจริง ซึ่งเป็นจุดตั้งต้นของ data age
    public var onFrame: ((CryptoFrame, Date) -> Void)?
    /// ประโยคล่าสุดที่หน้านี้พูดถึงตัวเอง — หน้าตั้งค่าเอาไปบอกผู้ใช้ว่าทำไมยังไม่มีตัวเลข
    public private(set) var status: String?

    public private(set) var settings: CryptoSettings
    private var schedule: FetchSchedule
    private let fetch: Fetcher

    /// คำที่ผู้ใช้พิมพ์ -> id ของบริการ · สตริงว่างคือ "ถามแล้ว ไม่มีเหรียญนี้"
    ///
    /// การจำผลลบไว้ด้วยเป็นเรื่องสำคัญ: ถ้าจำแต่ผลบวก คำที่พิมพ์ผิดจะถูกยิงถามใหม่
    /// ทุก 60 วินาทีตลอดไป ทั้งที่คำตอบไม่มีทางเปลี่ยนจนกว่าผู้ใช้จะแก้คำนั้น
    private var resolved: [String: String] = [:]

    public init(
        settings: CryptoSettings = CryptoSettings(),
        interval: TimeInterval = CryptoSource.interval,
        fetch: @escaping Fetcher
    ) {
        self.settings = settings
        self.schedule = FetchSchedule(interval: interval)
        self.fetch = fetch
    }

    /// ผู้ใช้แก้ watchlist — ของที่ถืออยู่ตอบคำถามคนละข้อทันที
    ///
    /// ผลการแปลงชื่อที่จำไว้ไม่ถูกล้าง: "btc" ยังเป็น bitcoin เหมือนเดิม การล้างทิ้งคือ
    /// การยิงถามซ้ำเรื่องที่รู้คำตอบอยู่แล้วทุกครั้งที่ผู้ใช้สลับลำดับสองแถว
    public func update(_ next: CryptoSettings) {
        guard next != settings else { return }
        settings = next
        status = nil
        schedule.invalidate()
    }

    public var isRunning: Bool { schedule.running }

    /// หน้านี้เพิ่งถูกเปิดกลับมา — เฟรมที่เคยมีถูกบอร์ดลืมไปตอนปิด (ADR-0002)
    public func restart() {
        status = nil
        schedule.invalidate()
    }

    public func tick(now: Date = Date()) {
        guard settings.isUsable else { return }
        guard schedule.start(now: now) else { return }
        step()
    }

    /// ยังมีคำไหนที่ยังไม่รู้ id ไหม — แปลทีละคำจนครบ แล้วค่อยถามราคาทีเดียว
    ///
    /// การถามราคาเป็นคำขอเดียวสำหรับทั้ง watchlist ต่างจากหน้าหุ้นที่ต้องยิงทีละสัญลักษณ์
    private func step() {
        guard let pending = settings.coins.first(where: { resolved[key($0)] == nil }) else {
            prices()
            return
        }
        guard let url = CryptoSource.searchURL(pending) else {
            finish(nil, "could not look up \(pending)")
            return
        }
        fetch(url) { [weak self] result in
            guard let self else { return }
            switch result.flatMap({ data in Result { try CryptoSource.coinID(from: data) } }) {
            case .success(let id):
                self.resolved[self.key(pending)] = id
                self.step()
            case .failure(let error):
                // "ไม่มีเหรียญนี้" คือคำตอบที่จบแล้ว ไม่ใช่ความล้มเหลวชั่วคราว — จำไว้
                // แล้วเดินต่อ ไม่งั้นคำที่พิมพ์ผิดหนึ่งคำจะกันทั้ง watchlist ไว้ตลอดกาล
                if (error as? CryptoError) == .noSuchCoin {
                    self.resolved[self.key(pending)] = ""
                    self.step()
                } else {
                    self.finish(nil, Self.explain(error))
                }
            }
        }
    }

    /// เหรียญที่ผู้ใช้ใส่ไว้แล้วจะไม่ได้เห็น กับเหตุผลของแต่ละตัว
    ///
    /// คำนวณใหม่ทุกรอบจากสิ่งที่รู้อยู่ ไม่ใช่สะสมข้อความไว้ — ข้อความที่ตั้งทิ้งไว้ตอน
    /// เจอปัญหาจะค้างอยู่ตลอดไปแม้เหตุจะหมดแล้ว แล้วหน้าตั้งค่าจะบอกว่าหน้านี้พังทั้งที่
    /// จอกำลังแสดงราคาสดอยู่
    private func unlisted(_ shown: Set<String>) -> String? {
        let unknown = settings.coins.filter { resolved[key($0)] == "" }
        let missing = settings.coins.filter { name in
            guard let id = resolved[key(name)], !id.isEmpty else { return false }
            return !shown.contains(id)
        }
        let lost = unknown + missing
        guard !lost.isEmpty else { return nil }
        // เหรียญที่หายไปเงียบๆ คือ watchlist ห้าตัวที่ขึ้นจอสี่ตัวโดยไม่มีใครบอกว่าตัวไหน
        return "not showing: \(lost.joined(separator: ", "))"
    }

    private func prices() {
        let ids = settings.coins.compactMap { resolved[key($0)] }.filter { !$0.isEmpty }
        guard let url = CryptoSource.marketsURL(ids: ids) else {
            // ทุกคำที่พิมพ์มาหาไม่เจอเลย — ไม่ใช่ความล้มเหลวของการดึง และไม่มีอะไรให้ยิง
            schedule.finished(ok: true)
            status = unlisted([])
            return
        }
        fetch(url) { [weak self] result in
            guard let self else { return }
            switch result.flatMap({ data in Result { try CryptoSource.quotes(from: data) } }) {
            case .success(let byID):
                // เรียงตาม watchlist ของผู้ใช้ ไม่ใช่ตามที่บริการคืนมา — ลำดับที่เขาจัดไว้
                // คือลำดับที่เขาจะกวาดตาหา
                let quotes = self.settings.coins.compactMap { name -> CryptoQuote? in
                    guard let id = self.resolved[self.key(name)] else { return nil }
                    return byID[id]
                }
                guard !quotes.isEmpty else {
                    self.finish(nil, "the price service knows none of these coins")
                    return
                }
                self.finish(CryptoFrame(quotes: quotes), self.unlisted(Set(byID.keys)))
            case .failure(let error):
                self.finish(nil, Self.explain(error))
            }
        }
    }

    private func key(_ name: String) -> String { name.lowercased() }

    private func finish(_ frame: CryptoFrame?, _ problem: String?) {
        schedule.finished(ok: frame != nil)
        // เขียนทับเสมอ รวมทั้งด้วย `nil` — รอบที่สำเร็จต้องลบคำบ่นของรอบก่อนทิ้ง ไม่งั้น
        // เน็ตที่สะดุดหนึ่งครั้งจะทำให้หน้าตั้งค่าบอกว่าหน้านี้พังไปตลอดกาล
        status = problem
        guard let frame else { return }
        onFrame?(frame, Date())
    }

    private static func explain(_ error: Error) -> String {
        (error as? CryptoError)?.message ?? error.localizedDescription
    }
}

/// ตัวยิงจริงของหน้าคริปโต — บางจนไม่มีตรรกะให้เทสต์ เหมือน `WeatherFetch`
public enum CryptoFetch {
    public static func urlSession(
        _ session: URLSession = .shared, timeout: TimeInterval = 15
    ) -> CryptoService.Fetcher {
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
                    done(.failure(CryptoError.badPayload))
                    return
                }
                done(.success(data))
            }.resume()
        }
    }
}
