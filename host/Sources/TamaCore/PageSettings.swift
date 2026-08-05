import Foundation

/// พฤติกรรมของจอที่ผู้ใช้ตั้งเอง — หน้าไหนเปิด เรียงยังไง หมุนเร็วแค่ไหน
///
/// อยู่ใน `UserDefaults` เท่านั้น และแอปเป็นบรรณาธิการเดียว ด้วยเหตุผลเดียวกับ
/// `WeatherSettings`: ค่าพวกนี้มี GUI เต็มรูปแบบ การมีไฟล์ให้แก้มืออีกทางจะทำให้
/// หน้าต่างโชว์ลำดับหนึ่งขณะที่จอหมุนอีกลำดับหนึ่ง
///
/// เก็บ *ทุก* หน้าไว้ใน `order` แล้วบอกแยกว่าอันไหนปิด ไม่ใช่เก็บเฉพาะหน้าที่เปิด —
/// ผู้ใช้ที่ปิดหน้าหนึ่งแล้วเปิดกลับต้องได้ตำแหน่งเดิมคืน ไม่ใช่ถูกโยนไปท้ายแถว
public struct PageSettings: Equatable, Sendable {
    /// ทุก `PageKind` ครบหนึ่งครั้ง เรียงตามที่ผู้ใช้จัด — มาสคอตอยู่ในนี้ด้วยและย้ายได้
    public private(set) var order: [PageKind]
    /// หน้าที่ถูกปิด — มาสคอตไม่เคยอยู่ในชุดนี้ ปิดไม่ได้ตามนิยาม
    public private(set) var off: Set<PageKind>
    /// รอบหมุนเดินเองไหม — ปิดแล้วจอเปลี่ยนหน้าเฉพาะตอนถูกปัด (หรือตอนมีเรื่องด่วน)
    ///
    /// เป็นค่าแยกจาก `rotation` ไม่ใช่ `rotation == 0` เพราะสองอย่างนี้เป็นคนละคำถาม:
    /// ผู้ใช้ที่ปิดแล้วเปิดกลับต้องได้จังหวะเดิมคืน ไม่ใช่ต้องนึกออกว่าเคยตั้งไว้เท่าไร
    /// และ `rotation` ยังทำงานอยู่ขณะปิด — มันคือระยะที่มาสคอตอยู่บนจอหลังการเด้ง
    public var autoTurn: Bool
    /// วินาทีต่อหนึ่งหน้าในรอบหมุน · ปิดรอบหมุนแล้วยังใช้อยู่ ดู `autoTurn`
    public var rotation: Int
    /// หลังผู้ใช้ปัดไปหน้าหนึ่งเอง จะยึดหน้านั้นไว้กี่วินาทีก่อนกลับเข้ารอบ
    /// ไม่มีความหมายเมื่อ `autoTurn` ปิด — ไม่มีรอบให้กลับเข้า
    public var hold: Int
    /// มีเรื่องด่วนบนหน้ามาสคอตแล้วให้จอกระโดดไปหามันเลยไหม
    public var attentionJump: Bool

    /// ต้องตรงกับ `[rotation]` ใน `tools/layout.toml` — ค่าที่นั่นคือค่าที่บอร์ดใช้ *ก่อน*
    /// ได้ยินจาก Mac ผู้ใช้ที่ไม่เคยแตะหน้าตั้งค่าจึงต้องไม่เห็นจอเปลี่ยนจังหวะตอนแอปขึ้น
    /// (`tamatest` อ่าน `layout.h` มาเทียบให้ — สองฝั่งนี้ดริฟต์กันเงียบๆ ไม่ได้)
    public static let defaultRotation = 20
    public static let defaultHold = 300
    public static let defaultAutoTurn = true
    /// ต่ำกว่า 5 วินาทีอ่านไม่ทัน ส่วนบนคือ 10 นาที ซึ่งนานพอสำหรับคนที่ยังอยากให้มันหมุน —
    /// คนที่ไม่อยากให้หมุนเลยมี `autoTurn` ให้ปิด ไม่ใช่ต้องลากเลขนี้ไปสุดทาง
    public static let rotationRange = 5...600
    /// 0 คือไม่ยึดเลย — ปัดแล้วหน้าถัดไปมาตามรอบปกติ
    public static let holdRange = 0...3600

    public init(
        order: [PageKind] = PageKind.allCases,
        off: Set<PageKind> = [],
        autoTurn: Bool = PageSettings.defaultAutoTurn,
        rotation: Int = PageSettings.defaultRotation,
        hold: Int = PageSettings.defaultHold,
        attentionJump: Bool = true
    ) {
        self.order = Self.normalize(order)
        self.off = off.subtracting([.mascot])
        self.autoTurn = autoTurn
        self.rotation = rotation.clamped(to: Self.rotationRange)
        self.hold = hold.clamped(to: Self.holdRange)
        self.attentionJump = attentionJump
    }

    /// ลำดับที่เก็บไว้อาจมาจากแอปรุ่นก่อน (ขาดหน้าใหม่) หรือถูกแก้มือ (ซ้ำ/ไม่รู้จัก) —
    /// หน้าที่หายไปต่อท้ายตามลำดับ enum ซึ่งเป็นลำดับที่ผู้ใช้ที่ไม่เคยจัดอะไรเลยจะได้
    private static func normalize(_ raw: [PageKind]) -> [PageKind] {
        var seen: Set<PageKind> = []
        var out: [PageKind] = []
        for kind in raw where !seen.contains(kind) {
            seen.insert(kind)
            out.append(kind)
        }
        for kind in PageKind.allCases where !seen.contains(kind) { out.append(kind) }
        return out
    }

    public func isOn(_ kind: PageKind) -> Bool { !off.contains(kind) }

    public mutating func setOn(_ kind: PageKind, _ on: Bool) {
        guard kind != .mascot else { return }  // หน้ามาสคอตปิดไม่ได้
        if on { off.remove(kind) } else { off.insert(kind) }
    }

    /// ย้ายหน้าขึ้นหรือลงหนึ่งขั้น — นอกขอบคือไม่มีอะไรเกิดขึ้น ไม่ใช่วนไปอีกฝั่ง
    public mutating func move(_ kind: PageKind, by step: Int) {
        guard let from = order.firstIndex(of: kind) else { return }
        let to = from + step
        guard order.indices.contains(to) else { return }
        order.swapAt(from, to)
    }

    /// สิ่งที่บอร์ดต้องรู้ — ค่าตั้งทั้งหมดที่เหลือเป็นเรื่องของฝั่ง Mac
    public var plan: PagePlan {
        PagePlan(
            order: order.filter(isOn), autoTurn: autoTurn, rotation: rotation, hold: hold,
            attentionJump: attentionJump)
    }

    public enum Key {
        public static let order = "pageOrder"
        public static let off = "pagesOff"
        public static let autoTurn = "pageAutoTurn"
        public static let rotation = "pageRotation"
        public static let hold = "pageHold"
        public static let attentionJump = "pageAttentionJump"
    }

    public static func load(_ defaults: UserDefaults = .standard) -> PageSettings {
        let order = (defaults.array(forKey: Key.order) as? [Int] ?? [])
            .compactMap(PageKind.init(rawValue:))

        // ยังไม่เคยตั้งค่าหน้าไหนเลย = ผู้ใช้ที่มาจากรอบก่อน ซึ่งเปิดปิดหน้าอากาศจาก
        // สวิตช์ของมันเอง — เคารพสิ่งที่เขาเลือกไว้ ไม่ใช่เปิดหน้าที่เขาปิดไปแล้วกลับมา
        let off: Set<PageKind>
        if let stored = defaults.array(forKey: Key.off) as? [Int] {
            off = Set(stored.compactMap(PageKind.init(rawValue:)))
        } else {
            off = defaults.bool(forKey: WeatherSettings.Key.legacyEnabled) ? [] : [.weather]
        }

        return PageSettings(
            order: order,
            off: off,
            // `object(forKey:)` ไม่ใช่ `integer(forKey:)` — ค่าที่ไม่เคยตั้งอ่านได้ 0
            // ซึ่งจะกลายเป็นรอบหมุน 5 วินาทีหลังถูกบีบเข้าช่วง ไม่ใช่ค่าตั้งต้น
            autoTurn: defaults.object(forKey: Key.autoTurn) as? Bool ?? defaultAutoTurn,
            rotation: defaults.object(forKey: Key.rotation) as? Int ?? defaultRotation,
            hold: defaults.object(forKey: Key.hold) as? Int ?? defaultHold,
            attentionJump: defaults.object(forKey: Key.attentionJump) as? Bool ?? true)
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(order.map(\.rawValue), forKey: Key.order)
        defaults.set(off.map(\.rawValue).sorted(), forKey: Key.off)
        defaults.set(autoTurn, forKey: Key.autoTurn)
        defaults.set(rotation, forKey: Key.rotation)
        defaults.set(hold, forKey: Key.hold)
        defaults.set(attentionJump, forKey: Key.attentionJump)
    }
}

/// ค่าตั้งที่เดินทางไปบอร์ด — ตัวจับเวลายังอยู่บนบอร์ดเหมือนเดิม Mac ส่งแค่กติกา
///
/// ไม่ใช่ `PageFrame` เพราะไม่ใช่หน้า: มันไม่มีอายุข้อมูล ไม่มีหน้าตา และไม่ได้ถูกเก็บ
/// เป็นเนื้อหาของหน้าไหน ตัวแยกบนสายจึงเป็นคีย์ `pl` ไม่ใช่ `g` — เฟรมที่มี `g` คือหน้า
/// ส่วนเฟรมที่ไม่มีทั้งคู่ยังเป็น snapshot ของหน้ามาสคอตเหมือนเดิมทุกไบต์
public struct PagePlan: Equatable, Codable, Sendable {
    /// เฉพาะหน้าที่เปิดอยู่ เรียงตามที่ผู้ใช้จัด — หน้าที่ไม่อยู่ในลิสต์นี้หายจากรอบทั้งหมด
    public var order: [PageKind]
    public var autoTurn: Bool
    public var rotation: Int
    public var hold: Int
    public var attentionJump: Bool

    public init(
        order: [PageKind], autoTurn: Bool, rotation: Int, hold: Int, attentionJump: Bool
    ) {
        self.order = order
        self.autoTurn = autoTurn
        self.rotation = rotation
        self.hold = hold
        self.attentionJump = attentionJump
    }

    enum CodingKeys: String, CodingKey {
        case order = "pl"
        case rotation = "r"
        case hold = "h"
        case attentionJump = "j"
        case autoTurn = "t"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = try c.decode([PageKind].self, forKey: .order)
        rotation = try c.decode(Int.self, forKey: .rotation)
        hold = try c.decode(Int.self, forKey: .hold)
        attentionJump = try c.decode(Int.self, forKey: .attentionJump) != 0
        autoTurn = try c.decode(Int.self, forKey: .autoTurn) != 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(order, forKey: .order)
        try c.encode(rotation, forKey: .rotation)
        try c.encode(hold, forKey: .hold)
        // 0/1 ไม่ใช่ true/false — ฝั่งบอร์ดอ่านตัวเลขทุกคีย์ที่เหลืออยู่แล้ว
        try c.encode(attentionJump ? 1 : 0, forKey: .attentionJump)
        try c.encode(autoTurn ? 1 : 0, forKey: .autoTurn)
    }

    /// สั้นเสมอ (หน้าไม่กี่หน้า + สามตัวเลข) จึงไม่มีอะไรให้บีบเหมือน page frame
    public func encoded() throws -> Data {
        try Wire.encoder().encode(self)
    }
}

extension Int {
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
