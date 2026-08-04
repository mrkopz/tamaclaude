import Foundation

/// การเตรียมข้อความก่อนส่งบน BLE
///
/// ฟอนต์บนบอร์ดมี ASCII พิมพ์ได้ (0x20..0x7E) กับอักขระไทยตาม `ThaiTable.blockRanges`
/// ตัวอักษรนอกสองชุดนี้จะกลายเป็นกล่องสี่เหลี่ยมบนจอ (เจอจริงตอนทำ preview กับ em dash)
/// daemon จึงต้องกรองเอง ไม่ใช่ปล่อยให้ firmware ไปเดา
public enum Text {
    /// ตัวที่แทนได้ด้วย ASCII แบบไม่เสียความหมาย
    private static let substitutions: [Unicode.Scalar: String] = [
        "\u{2014}": "-",  // em dash
        "\u{2013}": "-",  // en dash
        "\u{2212}": "-",  // minus
        "\u{2018}": "'", "\u{2019}": "'",
        "\u{201C}": "\"", "\u{201D}": "\"",
        "\u{2026}": "...",
        "\u{00A0}": " ", "\u{2009}": " ", "\u{202F}": " ",
        "\u{2192}": "->", "\u{2190}": "<-",
        "\u{2022}": "*", "\u{00B7}": "*",
        "\u{2713}": "ok", "\u{2717}": "x",
    ]

    /// เหลือเฉพาะอักขระที่ฟอนต์บนบอร์ดมีจริง และยุบช่องว่างซ้อนให้เหลือช่องเดียว
    ///
    /// เดินทีละ unicode scalar ไม่ใช่ทีละ `Character` เพราะสระบนกับวรรณยุกต์ไทยรวมอยู่ใน
    /// grapheme เดียวกับพยัญชนะ การเดินทีละ `Character` จะตัดสินทั้งคลัสเตอร์ด้วยตัวแรก
    public static func sanitize(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var lastWasSpace = false
        for ch in s.unicodeScalars {
            let piece: String
            if let sub = substitutions[ch] {
                piece = sub
            } else if (0x20...0x7E).contains(ch.value) {
                piece = String(ch)
            } else if Thai.inBlock(ch.value) {
                piece = String(ch)
            } else if ch.properties.isWhitespace {
                piece = " "
            } else {
                continue  // ทิ้ง ไม่แทนด้วย '?' เพราะจะกลายเป็นขยะเต็มบรรทัด
            }
            for p in piece {
                if p == " " {
                    if lastWasSpace { continue }
                    lastWasSpace = true
                } else {
                    lastWasSpace = false
                }
                out.append(p)
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// ตัดให้ยาวไม่เกิน `limit` ช่องบนจอ โดยเติม "..." เมื่อถูกตัดจริง
    ///
    /// นับเป็น "ช่อง" ไม่ใช่ตัวอักษร เพราะสระบนและวรรณยุกต์ไทยกว้างศูนย์ การนับ scalar
    /// ตรงๆ จะตัดข้อความไทยสั้นเกินจริงราว 40% คือทิ้งคำที่ใส่ได้โดยไม่มีใครรู้
    /// ผลพลอยได้: ข้อความที่ผ่านทางนี้ถูกประกอบร่างเรียบร้อยแล้วเสมอ
    public static func clip(_ s: String, to limit: Int) -> String {
        if limit <= 0 { return "" }
        let cells = Thai.clusters(s)
        if cells.count <= limit { return cells.joined() }
        if limit <= 3 { return cells.prefix(limit).joined() }
        return cells.prefix(limit - 3).joined() + "..."
    }

    /// sanitize + ประกอบร่าง + clip ในขั้นตอนเดียว — ทุกข้อความที่ออกจาก daemon ต้องผ่านทางนี้
    ///
    /// การประกอบร่างไม่มีประตูของตัวเอง มันอยู่ใน `clip` ซึ่งอยู่ในนี้ ข้อความจึงออกทางเดิม
    /// ทางเดียวเหมือนก่อนมีภาษาไทย
    public static func fit(_ s: String, to limit: Int) -> String {
        clip(sanitize(s), to: limit)
    }

    /// เหมือนกัน แต่เลือกเพดานตามภาษาที่อยู่ในบรรทัดนั้นจริงๆ
    ///
    /// บรรทัดที่มีอักขระไทยแม้ตัวเดียวใช้เพดานของไทยทั้งบรรทัด: ช่องไทยกว้างคงที่และกว้าง
    /// กว่าตัวอักษรอังกฤษเฉลี่ย การเดาว่าอีกกี่ช่องจะเป็นไทยแปลว่าเพดานเปลี่ยนตามเนื้อหา
    /// ซึ่งไม่ใช่เพดาน
    public static func fit(_ s: String, to limit: Limit.Cells) -> String {
        let clean = sanitize(s)
        let thai = clean.unicodeScalars.contains { Thai.inBlock($0.value) }
        return clip(clean, to: thai ? limit.thai : limit.ascii)
    }

    /// เหมือนกัน แต่กันที่ไว้ให้ส่วนท้ายที่ผู้เรียกจะต่อเองทีหลัง
    ///
    /// มีไว้เพราะสิ่งที่ต้องพอดีเพดานคือ *ป้ายทั้งป้าย* ไม่ใช่ชื่อโปรเจกต์อย่างเดียว
    /// การ fit ชื่อจนเต็มเพดานแล้วค่อยต่อ " x2" คือการล้นเพดานเงียบๆ แล้วไปขาดอีกที
    /// บนบอร์ด ซึ่งเป็นคนละจุดกับ "..." ที่ daemon เติม · ห้าม fit ซ้ำบนข้อความที่
    /// ผ่านทางนี้แล้ว: ร่างไทยที่ประกอบแล้วอยู่ใน PUA ซึ่ง `sanitize` ทิ้งทั้งหมด
    ///
    /// `suffix` ต้องวาดได้อยู่แล้ว (ผู้เรียกเป็นคนเขียนมันเอง ไม่ได้มาจากดิสก์หรือ hook)
    /// จึงวัดดิบๆ ไม่ผ่าน `sanitize` ซึ่งจะกินช่องว่างนำหน้าทิ้งแล้วกันที่ขาดไปหนึ่งช่อง
    public static func fit(_ s: String, to limit: Limit.Cells, reserving suffix: String) -> String {
        let clean = sanitize(s)
        let thai = clean.unicodeScalars.contains { Thai.inBlock($0.value) }
        let ceiling = thai ? limit.thai : limit.ascii
        return clip(clean, to: ceiling - displayWidth(suffix))
    }

    /// ส่วนหน้าของชื่อเท่าที่ใส่ได้ — **ไม่มี "..." ต่อท้าย** ต่างจาก `fit`
    ///
    /// มีไว้ทางเดียว: ชื่อโปรเจกต์ที่ไปนั่งเป็นคำนำหน้าบนบรรทัดของการ์ด ซึ่งไม่ใช่ *เนื้อหา*
    /// แต่เป็นตัวชี้ไปที่ป้ายใต้มาสคอตที่อยู่เหนือมันขึ้นไปไม่ถึงร้อยพิกเซล · ผู้อ่านไม่ได้
    /// ต้องการรู้ว่าชื่อถูกตัด เขารู้อยู่แล้วว่าชื่อเต็มอยู่บนป้าย เขาต้องการตัวอักษรมากพอ
    /// จะจับคู่กับป้ายนั้น · "..." กิน 3 ช่องไปบอกสิ่งที่รู้อยู่แล้ว แล้วเอาช่องที่ควรเป็น
    /// ตัวอักษรจริงไปทิ้ง — `an-extrem...` ชี้เป้าได้แย่กว่า `an-extremely` ล้วนๆ
    ///
    /// ห้ามใช้กับ *ประโยค*: ที่นั่นการตัดคือการหายไปของข้อมูล ซึ่งต้องเห็น
    public static func head(_ s: String, to limit: Limit.Cells) -> String {
        let clean = sanitize(s)
        let thai = clean.unicodeScalars.contains { Thai.inBlock($0.value) }
        let ceiling = thai ? limit.thai : limit.ascii
        return Thai.clusters(clean).prefix(max(0, ceiling)).joined()
    }

    /// ความยาวที่ตาเห็น หน่วยเป็นช่อง — ตัวเดียวกับที่ `clip` ใช้ตัดสิน
    public static func displayWidth(_ s: String) -> Int {
        Thai.displayWidth(s)
    }

    /// ความยาวสูงสุดตามพื้นที่จริงบนจอ — วัดด้วย `python3 tools/preview.py --limits`
    public enum Limit {
        /// เพดานของป้ายหนึ่ง แยกตามภาษา เพราะช่องไทยกว้างกว่าตัวอักษรอังกฤษเฉลี่ยเสมอ
        ///
        /// เลขเดียวที่ใช้ได้ทั้งสองภาษาต้องเป็นเลขของไทย ซึ่งแปลว่าบรรทัดอังกฤษถูกตัดสั้น
        /// กว่าที่จอรับได้จริงราวหนึ่งในสี่ ทั้งที่ไม่มีเหตุผล · ฝั่งไทยวัดได้เป๊ะเพราะฟอนต์
        /// บิตแมปที่แฟลชลงบอร์ดคือไฟล์ที่ `--limits` อ่าน ส่วนฝั่งอังกฤษเป็นค่าที่ตั้งต่ำกว่า
        /// ที่วัดได้อยู่แล้ว (Montserrat บนบอร์ดไม่มีตัวจริงให้ preview วัด)
        public struct Cells: Sendable {
            public let ascii: Int
            public let thai: Int

            public init(ascii: Int, thai: Int) {
                self.ascii = ascii
                self.thai = thai
            }
        }

        /// ป้ายชื่อโปรเจกต์ใต้มาสคอต — กว้าง 102px ฟอนต์บอร์ด 12
        public static let project = Cells(ascii: 14, thai: 12)
        /// หัวการ์ด — กว้าง 278px ฟอนต์บอร์ด 14 (แคบลงจาก 290 ตอนกันที่ให้เครื่องหมายชนิดการ์ด)
        public static let cardTitle = Cells(ascii: 32, thai: 30)
        /// เนื้อการ์ด — กว้างเท่ากัน ฟอนต์บอร์ด 12
        public static let cardBody = Cells(ascii: 44, thai: 34)
        /// ชื่อโปรเจกต์ตอนมันต้องแชร์บรรทัดเดียวกับประโยค (การ์ดบรรทัดเดียวหลายโปรเจกต์)
        ///
        /// ไม่ใช่เพดานของชื่อ แต่เป็น *ส่วนแบ่ง* ของมัน — ชื่อยาวต้องยอมโดนตัด ไม่ใช่กิน
        /// บรรทัดจนประโยคไม่เหลือ · ชื่อสั้น (ซึ่งเป็นส่วนใหญ่) ไม่เสียอะไรเพราะที่ที่ไม่ใช้
        /// ตกไปเป็นของประโยคทั้งหมด · เลขนี้เท่าป้ายใต้มาสคอตลบสอง: ชื่อที่แยกกันไม่ออก
        /// ที่ 12 ช่องก็แยกกันไม่ออกที่ 14 อยู่ดี
        public static let cardName = Cells(ascii: 12, thai: 10)
    }
}
