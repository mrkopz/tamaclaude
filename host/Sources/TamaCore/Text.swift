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

    /// ความยาวที่ตาเห็น หน่วยเป็นช่อง — ตัวเดียวกับที่ `clip` ใช้ตัดสิน
    public static func displayWidth(_ s: String) -> Int {
        Thai.displayWidth(s)
    }

    /// ความยาวสูงสุดตามพื้นที่จริงบนจอ (วัดจาก tools/gen/screen.py)
    public enum Limit {
        /// ป้ายชื่อโปรเจกต์ใต้มาสคอต — slot กว้าง 80px ฟอนต์ 9
        public static let project = 14
        /// หัวการ์ด — กว้าง ~293px ฟอนต์ 12
        public static let cardTitle = 34
        /// เนื้อการ์ด — กว้างเท่ากัน ฟอนต์ 10
        public static let cardBody = 46
    }
}
