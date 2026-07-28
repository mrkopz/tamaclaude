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
