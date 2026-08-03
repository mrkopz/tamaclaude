import Foundation

/// เดินคลัสเตอร์ไทยแล้วเลือกร่างของ glyph — คู่แฝดของ tools/gen/thai.py
///
/// LVGL วาดทีละ codepoint ไปทางขวา ไม่มี GPOS จึงซ้อนสระและวรรณยุกต์เองไม่ได้
/// (ADR-0008) daemon จึงเลือกร่างที่ถูกต้องให้เสร็จก่อนส่งขึ้นสาย บอร์ดไม่ต้องรู้ว่า
/// ภาษาไทยคืออะไร ตารางทั้งหมดมาจาก thai.toml ผ่าน ThaiTable.swift — ไฟล์นี้มีแต่อัลกอริทึม
public enum Thai {
    /// อยู่ในช่วงอักขระไทยที่ฟอนต์บนบอร์ดมีจริงหรือไม่
    public static func inBlock(_ cp: UInt32) -> Bool {
        ThaiTable.blockRanges.contains { $0.contains(cp) }
    }

    static func markClass(_ cp: UInt32) -> ThaiTable.MarkClass? {
        ThaiTable.markClasses[cp]
    }

    /// ร่างที่เลือกไว้ ถ้าตารางไม่มีก็ใช้ร่างปกติ — ตัวอักษรหายไปแย่กว่าวางเพี้ยน
    private static func variant(_ cp: UInt32, _ name: String) -> UInt32 {
        ThaiTable.variants[name]?[ThaiTable.canonical[cp] ?? cp] ?? cp
    }

    /// แตกข้อความเป็นคลัสเตอร์ที่ประกอบร่างแล้ว หนึ่งคลัสเตอร์ = หนึ่งช่องบนจอ
    ///
    /// ตัวอักษรที่ไม่ใช่ไทยกลายเป็นคลัสเตอร์ละตัว ความยาวที่ตาเห็นจึงเท่ากับจำนวน
    /// คลัสเตอร์เสมอ ไม่ว่าข้อความจะเป็นภาษาอะไร
    public static func clusters(_ s: String) -> [String] {
        let cps = Array(s.unicodeScalars)
        var out: [String] = []
        var i = 0
        while i < cps.count {
            let base = cps[i].value
            i += 1
            if markClass(base) != nil { continue }  // mark ที่ไม่มีฐาน — ไม่มีที่ให้เกาะ
            var above: UInt32?
            var tone: UInt32?
            var below: UInt32?
            while i < cps.count, let k = markClass(cps[i].value) {
                // ย้อนกลับเป็นร่างปกติก่อนเสมอ ข้อความที่ประกอบร่างแล้วจึงประกอบซ้ำได้ผลเดิม
                let cp = ThaiTable.canonical[cps[i].value] ?? cps[i].value
                switch k {
                case .above: if above == nil { above = cp }
                case .tone: if tone == nil { tone = cp }
                case .below: if below == nil { below = cp }
                }
                i += 1  // ตัวซ้ำในชั้นเดียวกันถูกทิ้ง ไม่วาดซ้อนกันเอง
            }
            let tall = ThaiTable.tallBases.contains(base)
            let desc = ThaiTable.descenderBases.contains(base)
            var piece: [UInt32] = [base]
            if let below {
                piece.append(desc ? variant(below, "below_descender") : below)
            }
            if let above {
                piece.append(tall ? variant(above, "above_tall") : above)
            }
            if let tone {
                if above != nil {
                    piece.append(variant(tone, tall ? "tone_tall_high" : "tone_high"))
                } else if tall {
                    piece.append(variant(tone, "tone_tall"))
                } else {
                    piece.append(tone)
                }
            }
            out.append(String(String.UnicodeScalarView(piece.compactMap(Unicode.Scalar.init))))
        }
        return out
    }

    /// ข้อความที่ประกอบร่างแล้ว — สิ่งที่ส่งขึ้นสายและสิ่งที่ preview วาด
    public static func shape(_ s: String) -> String {
        clusters(s).joined()
    }

    /// ความกว้างที่ตาเห็น หน่วยเป็นช่อง — สระบนและวรรณยุกต์กว้างศูนย์ จึงไม่ถูกนับ
    public static func displayWidth(_ s: String) -> Int {
        clusters(s).count
    }
}
