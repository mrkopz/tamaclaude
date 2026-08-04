import Foundation

/// key ของ Finnhub — ไฟล์โหมด 600 ใต้ `~/.tamaclaude` เหมือน `sessionKey`
///
/// ผู้ใช้ไปสมัครแผนฟรีเอง แล้ววาง key ลงช่องกรอกในแอป ตัวแอปเป็นคนเขียนไฟล์ ด้วยเหตุผล
/// เดียวกับ `SessionKeyFile`: สิทธิ์ของไฟล์เป็นส่วนหนึ่งของความปลอดภัย และคนที่
/// `echo … > file` แล้วลืม `chmod 600` จะได้ไฟล์ที่ทุกคนบนเครื่องอ่านได้
///
/// key นี้ไม่ได้เปิดบัญชี claude.ai แต่มันคือโควตาของผู้ใช้ และเป็นของที่ขโมยไปใช้ต่อได้
/// ทันที กติกาจึงเป็นชุดเดียวกัน ไม่ใช่ชุดที่ผ่อนลง (`SecretFile` เป็นเจ้าของกติกานั้น)
public enum FinnhubKeyFile {
    static let wording = SecretFile.Wording(
        noun: "Finnhub key",
        missing: "get a free key at finnhub.io and paste it into the Stocks tab",
        empty: "paste the key from finnhub.io into it")

    public static func write(_ raw: String, to url: URL = Paths.finnhubKey) throws {
        try SecretFile.write(raw, to: url, wording: wording)
    }

    /// อ่านใหม่ทุกรอบ ไม่เก็บไว้ในหน่วยความจำ — key ที่ถูกเปลี่ยนต้องมีผลทันที
    public static func read(at url: URL = Paths.finnhubKey) throws -> String {
        try SecretFile.read(at: url, wording: wording)
    }

    /// มี key ที่ยิงได้จริงไหม — ไม่ใช่แค่ "ไฟล์มีอยู่"
    public static func isUsable(at url: URL = Paths.finnhubKey) -> Bool {
        (try? read(at: url)) != nil
    }
}

/// watchlist ของหน้าหุ้น — อยู่ใน `UserDefaults` เท่านั้น และแอปเป็นบรรณาธิการเดียว
///
/// รูปเดียวกับ `CryptoSettings` ทุกข้อ ต่างกันแค่ *เหตุผล* ของเพดานห้าตัว: ที่นี่มันคือ
/// จำนวนคำขอต่อรอบ เพราะ `/quote` ของ Finnhub คืนทีละสัญลักษณ์
public struct StockSettings: Equatable, Sendable {
    /// สัญลักษณ์อย่างที่ผู้ใช้พิมพ์ — เก็บเป็นตัวใหญ่เสมอ ตลาดเรียกมันแบบนั้น และการมี
    /// "aapl" กับ "AAPL" เป็นคนละตัวในลิสต์เดียวคือ watchlist ที่กินโควตาสองครั้ง
    public private(set) var symbols: [String]

    /// เพดานห้าตัว — บังคับที่นี่ ไม่ใช่ที่หน้าต่าง เพราะประตูเข้าออกของค่านี้มีหลายบาน
    /// (หน้าตั้งค่า · ค่าที่โหลดจาก `UserDefaults` ของแอปรุ่นก่อน) แต่กติกามีข้อเดียว
    ///
    /// ตัวเลขนี้คืองบ: ห้าคำขอต่อรอบ หนึ่งรอบต่อนาที เฉพาะตอนตลาดเปิด คือราว 1,950
    /// คำขอต่อวันทำการ ซึ่งอยู่ใต้เพดานของแผนฟรีอย่างสบาย
    public static let maxSymbols = 5

    public init(symbols: [String] = []) {
        var seen: Set<String> = []
        var out: [String] = []
        for raw in symbols {
            let name = Self.normalize(raw)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            out.append(name)
            if out.count == Self.maxSymbols { break }
        }
        self.symbols = out
    }

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// ยังไม่ได้ใส่สัญลักษณ์เลย = ยังไม่มีอะไรให้ดึง (หน้านี้เปิดอยู่ไหมเป็นคำถามคนละข้อ)
    public var isUsable: Bool { !symbols.isEmpty }

    /// ย้ายขึ้นหรือลงหนึ่งขั้น — นอกขอบคือไม่มีอะไรเกิดขึ้น ไม่ใช่วนไปอีกฝั่ง
    public mutating func move(_ index: Int, by step: Int) {
        let to = index + step
        guard symbols.indices.contains(index), symbols.indices.contains(to) else { return }
        symbols.swapAt(index, to)
    }

    public mutating func remove(_ index: Int) {
        guard symbols.indices.contains(index) else { return }
        symbols.remove(at: index)
    }

    /// คืน `false` เมื่อเต็มเพดานแล้วหรือมีตัวนี้อยู่แล้ว — ผู้เรียกเอาไปบอกผู้ใช้ได้ว่าทำไม
    /// การกดปุ่มถึงไม่เกิดอะไรขึ้น
    @discardableResult
    public mutating func add(_ raw: String) -> Bool {
        let name = Self.normalize(raw)
        guard !name.isEmpty, symbols.count < Self.maxSymbols else { return false }
        guard !symbols.contains(name) else { return false }
        symbols.append(name)
        return true
    }

    public enum Key {
        public static let symbols = "stockSymbols"
    }

    public static func load(_ defaults: UserDefaults = .standard) -> StockSettings {
        StockSettings(symbols: defaults.array(forKey: Key.symbols) as? [String] ?? [])
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(symbols, forKey: Key.symbols)
    }
}

/// หน้าหุ้นฝั่ง Mac: ดึง Finnhub ทุก 60 วินาที *เฉพาะตอนตลาดเปิด* แล้ววาง page frame
/// ไว้ให้ `PageHub`
///
/// ยืมรูปของ `CryptoService` มาทั้งใบ — ตัวจัดตารางที่ถูกป้อนเวลา (`FetchSchedule`)
/// การยิงจริงที่เข้ามาทาง closure และการแปลงที่เป็นฟังก์ชันบริสุทธิ์ ต่างกันสามข้อ:
/// key ของผู้ใช้ · หนึ่งคำขอต่อหนึ่งสัญลักษณ์ · และหน้าต่างเวลาทำการที่ปิดท่อไปเลย
public final class StocksService {
    public typealias Fetcher = (URL, @escaping (Result<Data, Error>) -> Void) -> Void
    /// ที่มาของ key — ฟังก์ชัน ไม่ใช่สตริงที่ถือไว้ เพื่อให้ key ถูกอ่านใหม่ทุกรอบและ
    /// ไม่เคยค้างอยู่ในหน่วยความจำของ service ข้ามรอบ
    public typealias KeySource = () throws -> String

    /// มีเฟรมใหม่ — `observedAt` คือตอนที่ค่านี้ถูกอ่านมาจริง ซึ่งเป็นจุดตั้งต้นของ data age
    public var onFrame: ((StocksFrame, Date) -> Void)?
    /// ประโยคล่าสุดที่หน้านี้พูดถึงตัวเอง — หน้าตั้งค่าเอาไปบอกผู้ใช้ว่าทำไมยังไม่มีตัวเลข
    public private(set) var status: String?
    /// key ถูกปลายทางปฏิเสธไปแล้วไหม — หน้าตั้งค่าใช้แยก "รอสักครู่" ออกจาก "ต้องไปเอา
    /// key ใหม่มา" โดยไม่ต้องอ่านข้อความ
    public private(set) var keyRejected = false

    public private(set) var settings: StockSettings
    private var schedule: FetchSchedule
    private let fetch: Fetcher
    private let key: KeySource

    /// สัญลักษณ์ที่ถามไปแล้วและไม่มีอยู่จริง — ถามซ้ำทุกนาทีคือการเผาโควตาหนึ่งคำขอ
    /// ต่อรอบเพื่อคำตอบที่ไม่มีทางเปลี่ยนจนกว่าผู้ใช้จะแก้คำนั้น
    private var unknown: Set<String> = []
    /// ราคาชุดล่าสุดที่ได้มา — ใช้ตอนตลาดปิดเพื่อส่งเฟรมที่บอกว่า "ค้างเพราะตลาดปิด"
    private var last: [StockQuote] = []
    /// บอกบอร์ดไปแล้วว่าตลาดปิด — บอกครั้งเดียวต่อหนึ่งช่วงปิด ไม่ใช่ทุกวินาที
    private var toldClosed = false

    public init(
        settings: StockSettings = StockSettings(),
        interval: TimeInterval = StocksSource.interval,
        key: @escaping KeySource = { try FinnhubKeyFile.read() },
        fetch: @escaping Fetcher
    ) {
        self.settings = settings
        self.schedule = FetchSchedule(interval: interval)
        self.key = key
        self.fetch = fetch
    }

    /// ผู้ใช้แก้ watchlist — ของที่ถืออยู่ตอบคำถามคนละข้อทันที
    public func update(_ next: StockSettings) {
        guard next != settings else { return }
        settings = next
        status = nil
        // สัญลักษณ์ที่เคยหาไม่เจอถูกลืมทิ้ง: ผู้ใช้ที่เพิ่งแก้คำที่พิมพ์ผิดต้องได้คำตอบใหม่
        // ไม่ใช่ถูกจำว่าผิดไปตลอดกาลเพราะคำเก่าเคยผิด
        unknown.removeAll()
        schedule.invalidate()
    }

    public var isRunning: Bool { schedule.running }

    /// ผู้ใช้เพิ่งวาง key ใหม่ — รอบถัดไปต้องเกิดเดี๋ยวนี้ ไม่ใช่เมื่อครบนาที
    public func keyWasSet() {
        keyRejected = false
        status = nil
        schedule.invalidate()
    }

    /// หน้านี้เพิ่งถูกเปิดกลับมา — เฟรมที่เคยมีถูกบอร์ดลืมไปตอนปิด (ADR-0002)
    public func restart() {
        status = nil
        toldClosed = false
        schedule.invalidate()
    }

    public func tick(now: Date = Date()) {
        guard settings.isUsable else { return }
        // key ที่ปลายทางปฏิเสธไปแล้วจะถูกปฏิเสธเหมือนเดิมทุกรอบ — ยิงต่อคือการเผาโควตา
        // ของผู้ใช้เพื่อรับคำตอบที่รู้อยู่แล้ว จนกว่าเขาจะวาง key ใหม่ (`keyWasSet`)
        guard !keyRejected else { return }

        // ตลาดปิด = ไม่มีอะไรให้ถาม ท่อปิดสนิท ไม่ใช่ถามแล้วทิ้ง
        guard MarketHours.isOpen(now) else {
            closed(now: now)
            return
        }
        toldClosed = false
        guard schedule.start(now: now) else { return }
        round(now: now)
    }

    /// หนึ่งรอบ: อ่าน key ใหม่แล้วไล่ถามทีละสัญลักษณ์
    ///
    /// key ถูกอ่านที่นี่ ไม่ใช่ตอน `init` — ผู้ใช้ที่วาง key ใหม่ต้องมีผลตั้งแต่รอบถัดไป
    /// โดยไม่ต้องปิดเปิดแอป และ credential ไม่ค้างอยู่ในหน่วยความจำข้ามรอบ
    private func round(now: Date) {
        let token: String
        do {
            token = try key()
        } catch let problem as SecretFile.Problem {
            // ไม่มี key ไม่ใช่ความล้มเหลวชั่วคราว — บอกให้รู้แล้วอย่ายิง
            finish(nil, problem.message, now: now)
            return
        } catch {
            finish(nil, "\(error)", now: now)
            return
        }
        ask(settings.symbols.filter { !unknown.contains($0) }, token: token, collected: [:],
            now: now)
    }

    /// ตลาดปิดอยู่ — บอกบอร์ดครั้งเดียวว่าตัวเลขที่ค้างอยู่ค้างเพราะอะไร
    ///
    /// ไม่ส่งเฟรมซ้ำทุกวินาที: `PageHub` เทียบเนื้อหาอยู่แล้ว แต่ *เวลาที่อ่านค่ามา* จะขยับ
    /// ทุกครั้งที่เราส่ง ซึ่งจะทำให้อายุข้อมูลบนจอกระโดดกลับเป็นศูนย์ทั้งที่ราคาเป็นของ
    /// เมื่อวาน — อายุที่โกหกคือสิ่งเดียวที่หน้านี้ห้ามทำ
    private func closed(now: Date) {
        // ยังไม่เคยมีตัวเลขเลย (แอปเพิ่งเปิดคืนวันเสาร์ หรือผู้ใช้เพิ่งเปิดหน้านี้) — ยิง
        // *หนึ่ง* รอบ แล้วเงียบจนตลาดเปิด `/quote` คืนราคาปิดครั้งล่าสุดอยู่แล้ว หน้าที่
        // เขียนว่า "ยังไม่มีหุ้น" ทั้งที่ผู้ใช้ใส่ไว้ห้าตัวคือหน้าที่บอกเหตุผลผิด
        if last.isEmpty {
            guard schedule.start(now: now) else { return }
            round(now: now)
            return
        }
        guard !toldClosed else { return }
        toldClosed = true
        status = Self.closedMessage
        // อายุนับต่อจากตอนที่ราคาถูกอ่านมาจริง ไม่ใช่จากตอนนี้ — `observedAt` จึงเป็น
        // เวลาเดิม ไม่ใช่ `now`
        onFrame?(StocksFrame(quotes: last, marketClosed: true), observedAt)
    }

    static let closedMessage = "The market is closed; these figures are the last of the session."

    /// เวลาที่ราคาชุดที่ถืออยู่ถูกอ่านมา — จุดตั้งต้นของ data age
    private var observedAt = Date.distantPast

    /// ถามทีละสัญลักษณ์จนครบ แล้วค่อยประกอบเฟรม
    ///
    /// เรียงตามลำดับที่ผู้ใช้จัดไว้ และยิงทีละคำขอ ไม่ใช่พร้อมกันห้าคำขอ — แผนฟรีมีเพดาน
    /// ต่อวินาที และหน้าที่อัปเดตช้าไปสองวินาทีดีกว่าหน้าที่โดนปฏิเสธทั้งชุด
    private func ask(
        _ pending: [String], token: String, collected: [String: StockQuote], now: Date
    ) {
        guard let symbol = pending.first else {
            deliver(collected, now: now)
            return
        }
        let rest = Array(pending.dropFirst())
        guard let url = StocksSource.quoteURL(symbol: symbol, token: token) else {
            finish(nil, "could not ask about \(symbol)", now: now)
            return
        }
        fetch(url) { [weak self] result in
            guard let self else { return }
            switch result.flatMap({ data in
                Result { try StocksSource.quote(symbol: symbol, from: data) }
            }) {
            case .success(let quote):
                var next = collected
                next[symbol] = quote
                self.ask(rest, token: token, collected: next, now: now)
            case .failure(let error):
                // URL ก้อนนี้พก key อยู่ใน query — `describe` คือประตูเดียวที่มันเขียนลง
                // log ได้ และเป็นเหตุผลเดียวที่ฟังก์ชันนั้นมีอยู่
                Log.debug("stocks: \(StocksSource.describe(url)) failed: \(error)")
                switch error as? StocksError {
                case .noSuchSymbol:
                    // คำตอบที่จบแล้ว ไม่ใช่ความล้มเหลวชั่วคราว — จำไว้แล้วเดินต่อ ไม่งั้น
                    // สัญลักษณ์ที่พิมพ์ผิดหนึ่งตัวจะกันทั้ง watchlist ไว้ตลอดกาล
                    self.unknown.insert(symbol)
                    self.ask(rest, token: token, collected: collected, now: now)
                case .keyRejected:
                    // key ที่ถูกปฏิเสธจะถูกปฏิเสธเหมือนกันทั้งห้าคำขอ — หยุดทั้งรอบ
                    self.keyRejected = true
                    self.finish(nil, StocksError.keyRejected.message, now: now)
                default:
                    self.finish(nil, Self.explain(error), now: now)
                }
            }
        }
    }

    /// สัญลักษณ์ที่ผู้ใช้ใส่ไว้แล้วจะไม่ได้เห็น กับเหตุผลของแต่ละตัว
    ///
    /// คำนวณใหม่ทุกรอบจากสิ่งที่รู้อยู่ ไม่ใช่สะสมข้อความไว้ — ข้อความที่ตั้งทิ้งไว้ตอนเจอ
    /// ปัญหาจะค้างอยู่ตลอดไปแม้เหตุจะหมดแล้ว
    private func unlisted(_ shown: Set<String>) -> String? {
        let lost = settings.symbols.filter { !shown.contains($0) }
        guard !lost.isEmpty else { return nil }
        return "not showing: \(lost.joined(separator: ", "))"
    }

    private func deliver(_ quotes: [String: StockQuote], now: Date) {
        // เรียงตาม watchlist ของผู้ใช้ ไม่ใช่ตามลำดับที่คำตอบกลับมา — ลำดับที่เขาจัดไว้
        // คือลำดับที่เขาจะกวาดตาหา
        let rows = settings.symbols.compactMap { quotes[$0] }
        guard !rows.isEmpty else {
            finish(nil, unlisted([]) ?? "the quote service knows none of these symbols", now: now)
            return
        }
        last = rows
        // เวลาที่ *ถูกป้อนเข้ามา* ไม่ใช่ `Date()` — จุดตั้งต้นของ data age ต้องอยู่ใน
        // รอยต่อเดียวกับตัวจัดตาราง ไม่งั้นอายุบนจอมาจากนาฬิกาที่เทสต์ควบคุมไม่ได้
        observedAt = now
        schedule.finished(ok: true)
        let closed = !MarketHours.isOpen(now)
        // รอบที่ยิงตอนตลาดปิดคือรอบเปิดเครื่อง — บอกไปในเฟรมเดียวกันเลยว่าทำไมมันจะไม่ขยับ
        toldClosed = closed
        status = unlisted(Set(rows.map(\.symbol))) ?? (closed ? Self.closedMessage : nil)
        onFrame?(StocksFrame(quotes: rows, marketClosed: closed), observedAt)
    }

    private func finish(_ frame: StocksFrame?, _ problem: String?, now: Date) {
        schedule.finished(ok: frame != nil)
        // เขียนทับเสมอ รวมทั้งด้วย `nil` — รอบที่สำเร็จต้องลบคำบ่นของรอบก่อนทิ้ง ไม่งั้น
        // เน็ตที่สะดุดหนึ่งครั้งจะทำให้หน้าตั้งค่าบอกว่าหน้านี้พังไปตลอดกาล
        status = problem
        guard let frame else { return }
        observedAt = now
        onFrame?(frame, observedAt)
    }

    private static func explain(_ error: Error) -> String {
        if let problem = error as? SecretFile.Problem { return problem.message }
        return (error as? StocksError)?.message ?? error.localizedDescription
    }
}

/// ตัวยิงจริงของหน้าหุ้น — บางจนไม่มีตรรกะให้เทสต์ เหมือน `CryptoFetch` บวกข้อเดียว:
/// มันแปลรหัสสถานะที่บอกว่า *key* ผิด ให้ต่างจากรหัสที่บอกว่า *คำขอ* ผิด
///
/// URL ก้อนนี้พก key อยู่ใน query — ห้าม log ทั้งก้อน ใช้ `StocksSource.describe` แทน
public enum StocksFetch {
    public static func urlSession(
        _ session: URLSession = .shared, timeout: TimeInterval = 15
    ) -> StocksService.Fetcher {
        { url, done in
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            session.dataTask(with: request) { data, response, error in
                if let error {
                    done(.failure(error))
                    return
                }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                switch code {
                case 200..<300:
                    guard let data else {
                        done(.failure(StocksError.badPayload))
                        return
                    }
                    done(.success(data))
                case 401, 403:
                    done(.failure(StocksError.keyRejected))
                case 429:
                    done(.failure(StocksError.rateLimited))
                default:
                    done(.failure(StocksError.badPayload))
                }
            }.resume()
        }
    }
}
