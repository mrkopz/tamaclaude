import AppKit
import TamaCore

/// logo ในหน้าตั้งค่า — รูปชุดเดียวกับที่บอร์ดวาด ทั้งหน้าคริปโตและหน้าหุ้น
///
/// อ่าน PNG ที่ `tools/export_logos.py` คายออกมา ไม่ใช่ SVG ต้นฉบับ ทั้งที่ SVG อยู่ในรีโป
/// และคมกว่ามาก: PNG พวกนั้นถูกบีบสีเป็น RGB565 และ raster ที่ 32px มาแล้ว ซึ่งคือสิ่งที่
/// จอจริงทำได้ · ถ้าหน้านี้ใช้ SVG มันจะสวยกว่าจอ แล้วผู้ใช้เลือกของที่เห็นตรงนี้แต่ได้ของ
/// อีกแบบตรงนั้น — หน้าตั้งค่าที่โกหกเรื่องผลลัพธ์แย่กว่าหน้าตั้งค่าที่ดูหยาบ
enum LogoIconImage {
    /// ขนาดที่วาดบนจอ = ขนาดของไฟล์ ไม่ขยาย — 32px ที่ถูกยืดบนจอ Retina จะเบลอ ซึ่ง
    /// อ่านเป็น "รูปคุณภาพต่ำ" ไม่ใช่ "รูปที่หยาบเท่าของจริง"
    static let px = 32

    /// ขนาดในเมนู "Add from list" — ย่อจากไฟล์ 32px ไม่ใช่หยิบไฟล์ 16px ของบอร์ดมาใช้
    /// (`make-app.sh` ก๊อปมาแต่ 32 อยู่แล้ว) การ *ย่อ* บนจอ Retina ยังคม ต่างจากการ
    /// *ขยาย* ซึ่งเป็นสิ่งที่บรรทัดบนห้ามไว้ · แถวเมนูของ AppKit สูงกว่า 16pt
    static let menuPx = 18

    /// ชื่อที่ผู้ใช้พิมพ์ -> รูป · ไม่รู้จักก็ได้ `_default` เหมือนที่บอร์ดทำ
    ///
    /// **จับคู่กับสิ่งที่ผู้ใช้พิมพ์ ไม่ใช่สัญลักษณ์ที่บริการคืนมา** — ช่องคริปโตรับ "btc"
    /// หรือ "bitcoin" ก็ได้ ตัวหลังไม่ตรงกับชื่อไฟล์ `BTC.png` `LogoCatalog` จึงถูกถาม
    /// เป็นด่านที่สอง: ชื่อเต็มที่เรารู้จักแปลงกลับเป็นสัญลักษณ์ได้ในเครื่อง ไม่ต้องเดิน
    /// สัญลักษณ์ที่ resolve แล้วจาก `CryptoService` ข้ามมาถึงหน้าต่างนี้ ซึ่งเคยเป็นราคา
    /// ที่แพงเกินไปตอนยังไม่มีทะเบียน · ยังเหลือชื่อเล่นที่มีแต่ CoinGecko รู้ ("xbt")
    /// ที่ได้จานเปล่าตรงนี้แต่ได้รูปจริงบนจอ — นั่นเป็นของนอกเครื่องเหมือนเดิม
    ///
    /// หน้าหุ้นไม่มีปัญหานี้เลย: Finnhub รับ ticker ตรงๆ สิ่งที่ผู้ใช้พิมพ์ *คือ* สัญลักษณ์
    static func image(for typed: String) -> NSImage? {
        if let hit = load(typed.uppercased()) { return hit }
        if let symbol = LogoCatalog.symbol(forName: typed), let hit = load(symbol) { return hit }
        return load("_default")
    }

    /// รูปเดียวกันขนาดเมนู · **copy ก่อนตั้งขนาด** — `image(for:)` คืนตัวที่แคชไว้ ซึ่งแถว
    /// ของ watchlist ถืออยู่ด้วย การตั้ง `size` ทับจะย่อรูปในแถวนั้นไปพร้อมกัน
    static func menuImage(for typed: String) -> NSImage? {
        guard let copy = image(for: typed)?.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: menuPx, height: menuPx)
        return copy
    }

    private static var cache: [String: NSImage?] = [:]

    private static func load(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        let url = Bundle.main.resourceURL?
            .appendingPathComponent("logos")
            .appendingPathComponent("\(name)-\(px).png")
        // ไม่มีโฟลเดอร์ = รันจาก `swift run` ไม่ใช่จาก .app ที่ make-app.sh ประกอบ
        // รายการยังใช้ได้ทุกอย่าง แค่ไม่มีรูป — ไม่ใช่เหตุให้ล้ม
        let img = url.flatMap { NSImage(contentsOf: $0) }
        img?.size = NSSize(width: px, height: px)
        cache[name] = img
        return img
    }
}
