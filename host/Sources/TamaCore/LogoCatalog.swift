// สร้างอัตโนมัติจาก tools/logos.toml — ห้ามแก้ไฟล์นี้ด้วยมือ
// แก้ที่ TOML แล้วรัน: python3 tools/export_logos.py

import Foundation

/// สิ่งที่หน้าตั้งค่าบน Mac กางให้เลือก — สัญลักษณ์ที่ *มี logo จริง*
///
/// เหตุผลที่ลิสต์นี้มีอยู่: ผู้ใช้พิมพ์อะไรก็ได้ลง watchlist แต่มีแค่ชุดนี้ที่ได้รูป
/// ตัวอื่นได้จานของ `_default` ทั้งบนบอร์ดและในหน้าต่าง · เมนูจึงเป็นคำตอบตรงๆ
/// ของ "อันไหนมี icon" โดยไม่ต้องมีคำเตือนมาบอกซ้ำ ส่วนช่องพิมพ์ยังอยู่ครบ
/// สำหรับตัวนอกชุด — ลิสต์นี้ไม่ใช่เพดาน มันคือทางลัดที่ถูกเสมอ
///
/// ที่นี่ไม่รู้จัก id ของ CoinGecko เลย และไม่ควรรู้: สิ่งที่ลงไปใน `CryptoSettings`
/// คือสัญลักษณ์อย่างที่มนุษย์เรียก เหมือนกับที่คนพิมพ์เองได้ — `CryptoService`
/// เป็นคนแปลงเป็น id ครั้งเดียวแล้วจำไว้ เหมือนเดิมทุกประการ
public enum LogoCatalog {
    public struct Entry: Equatable, Sendable {
        /// สิ่งที่ลงไปใน watchlist จริง และสิ่งที่ขึ้นบนจอ
        public let symbol: String
        /// ชื่อสั้นที่คนเรียก — มีไว้ยืนยันว่าเลือกไม่ผิดตัว (COIN คือ Coinbase)
        public let name: String
    }

    public static let crypto: [Entry] = [
        Entry(symbol: "ADA", name: "Cardano"),
        Entry(symbol: "AVAX", name: "Avalanche"),
        Entry(symbol: "BNB", name: "BNB"),
        Entry(symbol: "BTC", name: "Bitcoin"),
        Entry(symbol: "DOGE", name: "Dogecoin"),
        Entry(symbol: "DOT", name: "Polkadot"),
        Entry(symbol: "ETH", name: "Ethereum"),
        Entry(symbol: "LINK", name: "Chainlink"),
        Entry(symbol: "LTC", name: "Litecoin"),
        Entry(symbol: "SOL", name: "Solana"),
        Entry(symbol: "TRX", name: "TRON"),
        Entry(symbol: "XRP", name: "XRP"),
    ]

    public static let stocks: [Entry] = [
        Entry(symbol: "AAPL", name: "Apple"),
        Entry(symbol: "AMD", name: "AMD"),
        Entry(symbol: "AMZN", name: "Amazon"),
        Entry(symbol: "COIN", name: "Coinbase"),
        Entry(symbol: "GOOG", name: "Google"),
        Entry(symbol: "INTC", name: "Intel"),
        Entry(symbol: "META", name: "Meta"),
        Entry(symbol: "MSFT", name: "Microsoft"),
        Entry(symbol: "NFLX", name: "Netflix"),
        Entry(symbol: "NVDA", name: "Nvidia"),
        Entry(symbol: "PYPL", name: "PayPal"),
        Entry(symbol: "TSLA", name: "Tesla"),
    ]

    /// ชื่อเต็มที่ผู้ใช้พิมพ์ -> สัญลักษณ์ · ไม่รู้จักคืน `nil`
    ///
    /// ช่องคริปโตรับ "bitcoin" ได้เท่ากับ "btc" เพราะ CoinGecko รับทั้งคู่ แต่รูป
    /// ถูกตั้งชื่อตามสัญลักษณ์ ใบนี้จึงเป็นสะพานที่ทำให้หน้าตั้งค่าไม่โชว์จานเปล่า
    /// ทั้งที่บอร์ดโชว์ logo จริง · ยังไม่ครอบคลุมชื่อเล่นที่มีแต่บริการรู้ (`xbt`)
    /// ซึ่งอยู่นอกเครื่องเหมือนเดิม
    public static func symbol(forName typed: String) -> String? {
        let key = typed.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        return all.first { $0.name.lowercased() == key }?.symbol
    }

    public static var all: [Entry] { crypto + stocks }
}
