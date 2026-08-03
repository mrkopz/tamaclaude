import EventKit
import Foundation

/// ตัวอ่านปฏิทินตัวจริง — ชั้นบางที่แตะ EventKit และไม่ตัดสินใจอะไรเลย (ADR-0005)
///
/// ทุกบรรทัดที่นี่คือการคัดลอกค่าออกมาหรือส่งคำถามต่อ ตรรกะทั้งหมด (หน้าต่างเจ็ดวัน ·
/// การเรียง · เพดานสี่รายการ · คำว่า "Today") อยู่ใน `CalendarPage` ซึ่งเทสต์ป้อน
/// ข้อมูลปลอมเข้าไปได้โดยไม่ต้องมีปฏิทินจริงบนเครื่องที่รันเทสต์
///
/// **อ่านอย่างเดียว**: ไม่มี `save`, `remove` หรือ `EKEvent` ตัวใหม่ที่ไหนในไฟล์นี้ และ
/// สิทธิ์ที่ขอคือสิทธิ์อ่าน อุปกรณ์บนโต๊ะจึงไม่มีทางแก้ปฏิทินของใครได้แม้ firmware จะพัง
public final class EventKitCalendars: CalendarReading, @unchecked Sendable {
    /// `EKEventStore` ตัวเดียวตลอดอายุแอป — ตัวใหม่ทุกครั้งที่ถามแปลว่าเสียเวลาโหลด
    /// ฐานข้อมูลปฏิทินใหม่ทุก 5 นาที และ callback ของการขอสิทธิ์จะตกไปกับตัวที่ถูกปล่อย
    private let store = EKEventStore()

    public init() {}

    public var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        // `writeOnly` คือสิทธิ์เขียนที่อ่านไม่ได้ — สำหรับหน้านี้มันเท่ากับไม่ได้สิทธิ์
        // และทางแก้ก็อันเดียวกัน (ไปเปิดใน System Settings)
        default: return .denied
        }
    }

    public func requestAccess(_ done: @escaping (CalendarAccess) -> Void) {
        store.requestFullAccessToEvents { [weak self] _, _ in
            // ใช้สถานะที่ระบบบอก ไม่ใช่ค่าที่ callback คืนมา — ผู้ใช้ที่กด "ให้เฉพาะ
            // ปฏิทินบางใบ" ทำให้สองค่านี้ไม่ตรงกัน และค่าที่ถูกคือค่าที่ถามระบบ
            let now = self?.access ?? .denied
            DispatchQueue.main.async { done(now) }
        }
    }

    public func calendars() -> [CalendarInfo] {
        store.calendars(for: .event).map {
            CalendarInfo(
                id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "")
        }
    }

    public func events(from: Date, to: Date, calendarIDs: [String]) -> [CalendarEvent] {
        let picked = store.calendars(for: .event).filter {
            calendarIDs.contains($0.calendarIdentifier)
        }
        // ปฏิทินที่เลือกไว้ถูกลบไปแล้วทั้งหมด — `nil` ในพารามิเตอร์นี้แปลว่า *ทุกปฏิทิน*
        // ซึ่งตรงข้ามกับที่ผู้ใช้เลือก และเป็นสิ่งที่คนอื่นในห้องจะได้อ่านแทนเขา
        guard !picked.isEmpty else { return [] }
        let predicate = store.predicateForEvents(
            withStart: from, end: to, calendars: picked)
        return store.events(matching: predicate).map {
            CalendarEvent(
                title: $0.title ?? "", start: $0.startDate ?? from, isAllDay: $0.isAllDay)
        }
    }
}
