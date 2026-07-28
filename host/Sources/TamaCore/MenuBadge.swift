import Foundation

/// สิ่งเดียวที่ไอคอนบนแถบเมนูต้องรู้: เลขของหน้าต่าง 5 ชม. กับ "ต้องแดงไหม"
///
/// แยกจากโค้ดวาดเพราะกฎว่าเมื่อไรควรเตือนเป็นตรรกะล้วน ทดสอบได้โดยไม่ต้องมีหน้าจอ
/// ส่วนโค้ดวาดเหลือแค่ "เอาสองค่านี้ไปทำภาพ"
///
/// เลือกหน้าต่าง 5 ชม. ตัวเดียว (ไม่ใช่ weekly) ด้วยเหตุผลเดียวกับแถบย่อบนจอ:
/// มันขยับเร็วพอจะเปลี่ยนการตัดสินใจภายในวันเดียว ส่วน weekly รอดูตอนกดเปิดแผงได้
public struct MenuBadge: Equatable, Sendable {
    public var percent: Int
    /// แดง — ไม่มีเหลือง ไม่มีเขียว บนแถบเมนู
    ///
    /// จอบนโต๊ะไล่สีสามขั้นได้เพราะมีที่ให้ไล่ แต่ไอคอน 16 px ที่ผู้ใช้เหลือบครึ่งวินาที
    /// มีคำถามเดียวคือ "ต้องช้าลงไหม" สีที่แปลว่า "ยังไหว" กับ "สบายมาก"
    /// กินความสนใจเท่ากับสีที่แปลว่า "มีปัญหา" ทั้งที่บอกน้อยกว่า
    public var isAlarming: Bool

    public init(percent: Int, isAlarming: Bool) {
        self.percent = percent
        self.isAlarming = isAlarming
    }

    /// เกณฑ์คงที่ — ตรงกับสีแดงของแผงโควตาบนบอร์ด
    public static let redAbove = 85

    /// `nil` แปลว่าไม่มีอะไรจะบอก ให้กลับไปเป็นไอคอนเดิม
    ///
    /// "ไม่รู้" กับ "ศูนย์" คนละเรื่อง (ADR-0001) — `0%` ที่เดาเอาบนแถบเมนูคือคำโกหก
    /// ที่ผู้ใช้เชื่อทันที เพราะมันดูเหมือนค่าที่วัดมา ส่วนแถบเปล่าดูเหมือนแอปพัง
    public static func from(_ usage: [UsageSnap]?) -> MenuBadge? {
        guard let session = usage?.first, session.percent != UsageSnap.unknown else { return nil }
        // countdown ถึงศูนย์ = หน้าต่างหมุนไปแล้ว เปอร์เซ็นต์ที่ยังถืออยู่เป็นของหน้าต่างที่ตายแล้ว
        // `UsageReader` ล้างให้ตั้งแต่ต้นทางอยู่แล้ว แต่สัญญาของแบดจ์คือค่าบนสาย ไม่ใช่ผู้อ่าน
        guard session.remaining != 0 else { return nil }
        return MenuBadge(percent: session.percent, isAlarming: alarming(session))
    }

    /// แซง pace = แดงก่อนถึงเกณฑ์ — "60% ตอนเหลือเวลาอีกครึ่ง" เป็นปัญหาคนละแบบ
    /// กับ "60% ตอนหมดเวลาพอดี" คิดด้วยจำนวนเต็มล้วนเพื่อไม่ให้เกณฑ์ขึ้นกับการปัดทศนิยม
    private static func alarming(_ snap: UsageSnap) -> Bool {
        if snap.percent > redAbove { return true }
        guard snap.remaining != UsageSnap.unknown else { return false }
        let window = UsageReader.sessionWindow
        // countdown ที่ยาวกว่าหน้าต่างแปลว่านาฬิกาสองฝั่งไม่ตรงกัน ไม่ใช่ว่าเวลาเดินถอยหลัง
        let elapsed = min(window, max(0, window - snap.remaining))
        return snap.percent * window > elapsed * 100
    }
}
