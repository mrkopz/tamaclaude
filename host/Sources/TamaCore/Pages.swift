import Foundation

/// ชนิดของ page ที่บอร์ดรู้จักตั้งแต่ตอนแฟลช (ADR-0004)
///
/// ตัวเลขคือสิ่งที่เดินทางบนสาย จึงเป็นสัญญากับ firmware แบบเดียวกับ `VisualState`
/// การเพิ่มค่าที่นี่แปลว่าต้องแก้ `ct_page_kind_t` (firmware/main/ct_pages.h) และ
/// `PAGES` (tools/gen/pages.py) พร้อมกันแล้วแฟลชบอร์ด — `tamatest` เฝ้าคู่แรกไว้
public enum PageKind: Int, Codable, CaseIterable, Sendable {
    case mascot = 0
    case weather = 1
}

/// ข้อมูลของหนึ่ง page ที่เดินทางเป็นก้อนของตัวเอง (ADR-0003)
///
/// `Snapshot` ของหน้ามาสคอตไม่ได้ทำตาม protocol นี้โดยตั้งใจ — มันมีอยู่ก่อนและต้อง
/// เหมือนเดิมทุกไบต์ ตัวแยกบนสายจึงเป็น *การมีคีย์ `g`* ไม่ใช่ค่าของมัน: เฟรมที่ไม่มี
/// คีย์นี้คือหน้ามาสคอต ซึ่งทำให้ firmware เก่ายังอ่าน snapshot ได้เหมือนไม่มีอะไรเกิดขึ้น
public protocol PageFrame: Sendable {
    var kind: PageKind { get }
    /// วินาทีนับจากตอนที่ Mac ได้ข้อมูลก้อนนี้มาจริง — board นับต่อเองหลังจากนั้น
    /// (กลไกเดียวกับ `UsageSnap.remaining` ที่ส่งเวลาคงเหลือแทนเวลาสัมบูรณ์)
    var age: Int { get set }
    /// เฟรมต้องพอดี `maxBytes` **โดยลำพัง** ไม่มี chunking บนสายทั้งสองทาง
    func encoded(maxBytes: Int) throws -> Data
}

/// "ลืมหน้านี้ทิ้ง" — ผู้ใช้ปิดมันบน Mac
///
/// จำเป็นเพราะบอร์ดเก็บทุกหน้าไว้ใน RAM (ADR-0002): ถ้าไม่บอก หน้าที่ถูกปิดจะยังหมุน
/// มาให้เห็นพร้อมตัวเลขของเมื่อวานตลอดไป ซึ่งแย่กว่าไม่มีหน้านั้นตั้งแต่แรก
public struct PageRetire: PageFrame, Equatable, Sendable {
    public let kind: PageKind
    /// เฟรมนี้ไม่มีข้อมูล จึงไม่มีอายุ — มีไว้ให้ครบตามสัญญาของ `PageFrame` เท่านั้น
    public var age: Int = 0

    public init(kind: PageKind) {
        self.kind = kind
    }

    public func encoded(maxBytes: Int = Wire.maxPayload) throws -> Data {
        // สั้นจนไม่มีอะไรให้บีบ — ประกอบตรงๆ แทนที่จะให้ Codable ทำ
        Data(#"{"g":\#(kind.rawValue),"x":1}"#.utf8)
    }
}

/// เฟรมของทุกหน้าที่ยังไม่ใช่หน้ามาสคอต: ใครส่งได้บ้าง อันไหนควรส่งซ้ำ
///
/// เก็บ *ค่าที่อ่านได้* กับ *เวลาที่อ่านมา* แยกกัน แล้วประกอบเฟรมตอนจะส่งจริง เพราะ
/// data age เปลี่ยนทุกวินาที ถ้าเทียบ "เปลี่ยนไหม" จากไบต์ที่มี age อยู่ด้วย บอร์ดจะโดน
/// เขียนทุกวินาทีตลอดไป ซึ่งเป็นกฎเดิมที่มีอยู่แล้วว่าห้ามทำ
public final class PageHub {
    /// หน้าที่บอร์ดตัวนี้ประกาศว่ารู้จัก (ADR-0006) — ว่างคือ firmware เก่าที่ยังไม่รู้จัก
    /// การประกาศเลย ซึ่งแปลว่ามีแต่หน้ามาสคอต ไม่ใช่ "ยังไม่รู้ ลองส่งไปก่อน"
    public private(set) var capability: Set<PageKind> = []

    private var frames: [PageKind: any PageFrame] = [:]
    private var observed: [PageKind: Date] = [:]
    /// ก้อนที่ส่งไปแล้ว โดยตั้ง age เป็นศูนย์ — ตัวเทียบว่าเนื้อหาเปลี่ยนจริงไหม
    private var sentBody: [PageKind: Data] = [:]
    /// เวลาที่อ่านค่าของก้อนที่ส่งไปแล้ว — ตัวเลขเดิมที่อ่านมาใหม่ *ไม่ใช่* ของเดิม
    /// อายุที่มันพกไปคือทั้งหมดที่ต่างกัน และเป็นสิ่งที่บอร์ดนับต่อจากนั้น
    private var sentObserved: [PageKind: Date] = [:]

    public init() {}

    /// บอร์ดประกาศความสามารถของมัน — รายการใหม่ทับของเดิมทั้งชุด
    public func announce(_ kinds: [PageKind]) {
        capability = Set(kinds)
        // บอร์ดคนละตัว (หรือตัวเดิมที่เพิ่งถูกแฟลช) ไม่ได้ถือเฟรมเก่าของเราไว้
        sentBody.removeAll()
        sentObserved.removeAll()
    }

    /// หน้านี้ส่งได้ไหม — หน้ามาสคอตส่งได้เสมอ มันไม่เคยเป็นของใหม่สำหรับบอร์ดตัวไหน
    public func allows(_ kind: PageKind) -> Bool {
        kind == .mascot || capability.contains(kind)
    }

    /// มีข้อมูลใหม่ของหน้าหนึ่ง — `observedAt` คือตอนที่ Mac ได้ค่านี้มา ไม่ใช่ตอนนี้
    public func submit(_ frame: any PageFrame, observedAt: Date) {
        frames[frame.kind] = frame
        observed[frame.kind] = observedAt
    }

    /// หน้าที่ผู้ใช้เพิ่งปิด — บอกบอร์ดให้ลืม ไม่ใช่แค่เลิกส่งของใหม่
    ///
    /// การเลิกส่งเฉยๆ ทำให้บอร์ดหมุนมาเจอหน้าที่ปิดไปแล้วพร้อมตัวเลขของเมื่อวาน
    /// ตลอดไป (ADR-0002: บอร์ดเก็บทุกหน้าไว้ใน RAM)
    public func drop(_ kind: PageKind) {
        guard kind != .mascot else { return }  // หน้ามาสคอตปิดไม่ได้
        frames[kind] = PageRetire(kind: kind)
        observed[kind] = nil
    }

    /// บอร์ดกลับมา — มันไม่จำอะไรเลย ทุกหน้าที่มีอยู่ในมือต้องถูกส่งใหม่
    public func forgetSent() {
        sentBody.removeAll()
        sentObserved.removeAll()
    }

    /// เฟรมที่ควรส่งเดี๋ยวนี้ เรียงตาม `PageKind` เพื่อให้ผลซ้ำได้ในเทสต์
    public func drain(now: Date, maxBytes: Int = Wire.maxPayload) -> [Data] {
        var out: [Data] = []
        for kind in PageKind.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard var frame = frames[kind], allows(kind) else { continue }
            frame.age = 0
            guard let body = try? frame.encoded(maxBytes: maxBytes) else { continue }
            let readAt = observed[kind]
            guard body != sentBody[kind] || readAt != sentObserved[kind] else { continue }
            sentBody[kind] = body
            sentObserved[kind] = readAt
            let since = readAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
            frame.age = since
            guard let data = try? frame.encoded(maxBytes: maxBytes) else { continue }
            out.append(data)
        }
        return out
    }
}
