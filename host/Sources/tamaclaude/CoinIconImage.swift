import AppKit

/// logo เหรียญในหน้าตั้งค่า — รูปชุดเดียวกับที่บอร์ดวาด
///
/// อ่าน PNG ที่ `tools/export_coins.py` คายออกมา ไม่ใช่ SVG ต้นฉบับ ทั้งที่ SVG อยู่ในรีโป
/// และคมกว่ามาก: PNG พวกนั้นถูกบีบสีเป็น RGB565 และ raster ที่ 32px มาแล้ว ซึ่งคือสิ่งที่
/// จอจริงทำได้ · ถ้าหน้านี้ใช้ SVG มันจะสวยกว่าจอ แล้วผู้ใช้เลือกของที่เห็นตรงนี้แต่ได้ของ
/// อีกแบบตรงนั้น — หน้าตั้งค่าที่โกหกเรื่องผลลัพธ์แย่กว่าหน้าตั้งค่าที่ดูหยาบ
enum CoinIconImage {
    /// ขนาดที่วาดบนจอ = ขนาดของไฟล์ ไม่ขยาย — 32px ที่ถูกยืดบนจอ Retina จะเบลอ ซึ่ง
    /// อ่านเป็น "รูปคุณภาพต่ำ" ไม่ใช่ "รูปที่หยาบเท่าของจริง"
    static let px = 32

    /// ชื่อที่ผู้ใช้พิมพ์ -> รูป · ไม่รู้จักก็ได้ `_default` เหมือนที่บอร์ดทำ
    ///
    /// **จับคู่กับสิ่งที่ผู้ใช้พิมพ์ ไม่ใช่สัญลักษณ์ที่ CoinGecko คืนมา** — ช่องนี้รับ "btc"
    /// หรือ "bitcoin" ก็ได้ ตัวหลังจึงไม่มีวันตรงกับชื่อไฟล์ `BTC.png` แล้วรายการนี้จะโชว์
    /// จานเปล่าทั้งที่บนบอร์ดขึ้น logo bitcoin จริง · ที่รับไว้เพราะการแก้แปลว่าต้องเดิน
    /// สัญลักษณ์ที่ resolve แล้วจาก `CryptoService` ข้ามมาถึงหน้าต่างนี้ ซึ่งเป็นท่อใหม่
    /// ทั้งเส้นเพื่อรูปหนึ่งใบในหน้าที่เปิดปีละครั้ง
    static func image(for typed: String) -> NSImage? {
        load(typed.uppercased()) ?? load("_default")
    }

    private static var cache: [String: NSImage?] = [:]

    private static func load(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        let url = Bundle.main.resourceURL?
            .appendingPathComponent("coins")
            .appendingPathComponent("\(name)-\(px).png")
        // ไม่มีโฟลเดอร์ = รันจาก `swift run` ไม่ใช่จาก .app ที่ make-app.sh ประกอบ
        // รายการยังใช้ได้ทุกอย่าง แค่ไม่มีรูป — ไม่ใช่เหตุให้ล้ม
        let img = url.flatMap { NSImage(contentsOf: $0) }
        img?.size = NSSize(width: px, height: px)
        cache[name] = img
        return img
    }
}
