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
        /// หัวการ์ด — กว้าง 290px ฟอนต์บอร์ด 14
        public static let cardTitle = Cells(ascii: 34, thai: 32)
        /// เนื้อการ์ด — กว้างเท่ากัน ฟอนต์บอร์ด 12
        public static let cardBody = Cells(ascii: 46, thai: 36)
    }
}
