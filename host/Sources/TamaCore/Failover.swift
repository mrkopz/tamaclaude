import Foundation

/// ทางที่ snapshot กำลังเดินอยู่จริง
public enum LanRoute: String, Equatable, Sendable {
    case ble, lan, none
}

/// เมื่อไรถึงจะเปิดทาง LAN — ตรรกะล้วน ไม่มีซ็อกเก็ต ไม่มีนาฬิกาของตัวเอง
///
/// รอ 10 วินาทีก่อนเสมอ ไม่ใช่สลับทันทีที่ BLE หลุด: การหลุดสั้นๆ เกิดเป็นปกติ (เดินผ่าน
/// ตัวเครื่อง ไมโครเวฟ Mac หลับครึ่งหนึ่ง) และ CoreBluetooth ต่อกลับได้เองในไม่กี่วินาที
/// การกระโดดไป LAN ทุกครั้งแปลว่าเปิด/ปิดซ็อกเก็ตทั้งวันเพื่อสิ่งที่หายเองอยู่แล้ว
///
/// นาฬิกาถูกป้อนเข้ามา (`now`) ไม่ได้อ่านเอง — สถานะที่ขึ้นกับเวลาต้องทดสอบได้โดยไม่ต้องรอ
public struct FailoverPolicy: Equatable, Sendable {
    public let grace: TimeInterval
    private var bleLostAt: Date?
    /// ทาง LAN ควรเปิดอยู่ไหม — คนละคำถามกับ "ต่อติดหรือยัง"
    public private(set) var wantsLan = false
    public private(set) var route: LanRoute = .none

    /// `since` คือจุดที่เริ่มนับว่า BLE ยังไม่มา — ตอนแอปเพิ่งเปิดคือ "เดี๋ยวนี้" ไม่ใช่ nil
    /// ไม่งั้น Mac ที่ตื่นมาไกลจากบอร์ดจะรอ BLE ที่ไม่มีวันมาโดยไม่เคยลองทาง LAN เลย
    public init(grace: TimeInterval = 10, since: Date) {
        self.grace = grace
        self.bleLostAt = since
    }

    public mutating func update(ble: Bool, lan: Bool, now: Date) {
        if ble {
            bleLostAt = nil
            wantsLan = false
            route = .ble
            return
        }
        if bleLostAt == nil { bleLostAt = now }
        wantsLan = now.timeIntervalSince(bleLostAt ?? now) >= grace
        route = lan ? .lan : .none
    }
}

/// BLE เป็นทางหลัก LAN เป็นทางสำรอง — daemon เห็นเป็นทางออกเดียว
///
/// `Daemon` ส่ง snapshot ให้ transport ที่ `isConnected` เท่านั้น และเทียบกับก้อนที่ส่งไป
/// ล่าสุดเพื่อไม่ให้ยิงซ้ำ การสลับทางจึงต้องปลุก `onConnect` ด้วย ไม่งั้นบอร์ดที่เพิ่งรับสาย
/// ใหม่จะรอ snapshot ก้อนถัดไปที่ *เนื้อหาเปลี่ยน* ซึ่งอาจเป็นอีกหลายนาที
public final class FailoverTransport: Transport {
    public let name = "failover"
    public var onConnect: (() -> Void)?
    /// ทางเปลี่ยน — เมนูบาร์กับหน้าตั้งค่าเอาไปบอกผู้ใช้ว่าตอนนี้คุยกันทางไหน
    public var onRouteChanged: ((LanRoute) -> Void)?

    public var isConnected: Bool { ble.isConnected || lan.isConnected }
    public private(set) var route: LanRoute = .none

    private let ble: Transport
    private let lan: LanTransport
    private var policy: FailoverPolicy

    public init(ble: Transport, lan: LanTransport, grace: TimeInterval = 10,
                now: Date = Date()) {
        self.ble = ble
        self.lan = lan
        self.policy = FailoverPolicy(grace: grace, since: now)
    }

    public func start() {
        // ลูกทั้งสองแจ้งการต่อติดของตัวเองขึ้นมาตรงๆ ไม่ผ่านการเทียบ route: การต่อกลับ
        // ที่เกิดและจบภายในหนึ่ง tick จะไม่ปรากฏใน route เลย แต่บอร์ดปลายทางลืมทุกอย่าง
        // ไปแล้วจริงๆ
        ble.onConnect = { [weak self] in self?.onConnect?() }
        lan.onConnect = { [weak self] in self?.onConnect?() }
        ble.start()
    }

    public func tick(now: Date) {
        policy.update(ble: ble.isConnected, lan: lan.isConnected, now: now)
        if policy.wantsLan { lan.start() } else { lan.stop() }
        guard policy.route != route else { return }
        route = policy.route
        Log.info("snapshot route is now \(route.rawValue)")
        onRouteChanged?(route)
        onConnect?()
    }

    /// BLE ชนะเสมอเมื่อทั้งคู่ต่ออยู่ — มันคือทางที่บอร์ดตอบกลับได้ด้วย
    public func send(_ payload: Data) {
        if ble.isConnected {
            ble.send(payload)
        } else if lan.isConnected {
            lan.send(payload)
        }
    }
}
