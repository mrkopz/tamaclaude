import Foundation

/// ข้อความท้าย popover — สถานะบอร์ดกับรายการ session
///
/// อยู่ใน TamaCore ไม่ใช่ใน MenuBarApp เพราะเป็นตรรกะล้วนที่เทสต์ได้ ส่วนที่เหลือของ
/// popover เป็น AppKit ที่เทสต์ไม่ได้บนเครื่องที่ไม่มีหน้าจอ แยกออกมาแล้วเส้นแบ่ง
/// ระหว่าง "สิ่งที่พูด" กับ "วิธีวาด" ก็ชัดขึ้นด้วย
public enum PanelText {
    /// ไม่มีคำว่า disconnected: บอร์ดที่ยังหาไม่เจอกับบอร์ดที่หลุดไปเป็นสภาพเดียวกัน
    /// สำหรับผู้ใช้ — แอปกำลังสแกนอยู่และจะกลับมาต่อเอง
    public static func board(connected: Bool) -> String {
        connected ? "Board connected" : "Looking for the board…"
    }

    /// บรรทัด "ท่อพัง" — มีก็ต่อเมื่อผู้ใช้ต้องลงมือ ไม่ใช่ตอนเน็ตสะดุด
    ///
    /// แยกจาก `figures` โดยตั้งใจ: อันนี้บอกว่าค่าใหม่จะไม่มีวันมาจนกว่าจะแปะ key
    /// อีกอันบอกว่าค่าที่เห็นอยู่เก่าแค่ไหน ยุบสองเรื่องนี้เป็นบรรทัดเดียวเมื่อไร
    /// ผู้ใช้จะแยกไม่ออกว่า "เก่า" แปลว่าต้องทำอะไรหรือไม่ต้องทำอะไร
    public static func keyProblem(_ blocked: PollBlock?) -> String? {
        switch blocked {
        case .expiredKey: return "Session key expired — click to paste a new one"
        case .unusableKeyFile: return "Session key file unusable — click to paste a new one"
        case nil: return nil
        }
    }

    /// บรรทัด "ค่านี้อายุเท่าไร" — ความเก่าของตัวเลขที่เห็นอยู่ ไม่ใช่สถานะของท่อ
    ///
    /// มีวินาทีจริงๆ ต่างจากที่อื่นในแอปนี้: ทั้งฟีเจอร์เกิดจากคำถาม "เลขนี้ค้างหรือเปล่า"
    /// และคำตอบที่หยาบระดับนาทีก็แค่ย้ายความสงสัยจากบอร์ดมาไว้บนเมนูบาร์ แผงที่เปิดค้าง
    /// วาดใหม่ทุกวินาทีอยู่แล้ว ตัวเลขที่เดินจึงเป็นหลักฐานว่าแผงยังมีชีวิต
    public static func updated(stamp: Date?, now: Date = Date()) -> String {
        guard let stamp else { return "No quota figures yet" }
        // นาฬิกาเครื่องเดินถอยหลังได้ (sleep, NTP) — อายุติดลบต้องไม่กลายเป็นข้อความประหลาด
        let age = Int(max(0, now.timeIntervalSince(stamp)))
        if age < 60 { return "Updated \(age)s ago" }
        let minutes = age / 60
        if minutes < 60 { return "Updated \(minutes)m ago" }
        let hours = minutes / 60
        if hours < 48 { return "Updated \(hours)h ago" }
        return "Updated \(hours / 24)d ago"
    }

    /// หนึ่งแถวต่อหนึ่ง session แล้วปิดท้ายด้วยจำนวนที่ล้นออกจาก slot ของบอร์ด
    ///
    /// `+N more` เป็นแถวสุดท้ายเสมอ ถ้าอยู่ข้างบนมันจะอ่านเหมือนหัวข้อของแถวที่ตามมา
    public static func sessions(_ snapshot: Snapshot) -> [String] {
        guard !snapshot.sessions.isEmpty else { return ["No sessions"] }
        var rows = snapshot.sessions.map { "\($0.project) · \($0.state.rawValue)" }
        if snapshot.overflow > 0 { rows.append("+\(snapshot.overflow) more") }
        return rows
    }
}
