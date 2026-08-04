import Foundation

/// กติกาของ "ไฟล์ที่เก็บความลับหนึ่งบรรทัด" — เขียนอย่างไร และอันไหนใช้ไม่ได้
///
/// มีความลับสองใบในเครื่องนี้ที่กติกาเดียวกันทุกข้อ: `sessionKey` ของ claude.ai และ
/// key ของ Finnhub ทั้งคู่เป็นไฟล์โหมด 600 ตั้งแต่เกิด อ่านใหม่ทุกรอบ ไม่เคยผ่าน argv
/// ไม่เคยผ่าน env และไม่เคยลง log — ต่างกันแค่ *ประโยค* ที่บอกผู้ใช้ว่าต้องทำอะไรต่อ
///
/// รวมไว้ที่เดียวเพราะกติกาความปลอดภัยที่มีสองสำเนาคือกติกาที่วันหนึ่งจะเหลือสำเนาเดียว
/// ที่ยังถูกต้อง ประโยคจึงเป็นพารามิเตอร์ ส่วนกฎไม่ใช่
public enum SecretFile {
    /// ไฟล์นี้ใช้ไม่ได้ พร้อมประโยคที่บอกวิธีแก้ — ผู้เรียกเป็นคนแปลงเป็น error ของตัวเอง
    ///
    /// ข้อความไม่เคยพาความลับติดออกมาด้วย แม้แต่ตอนที่มันอ่านค่าได้แล้วแต่ปฏิเสธ
    public struct Problem: Error, Equatable {
        public let message: String
        public init(message: String) { self.message = message }
    }

    /// ประโยคที่ต่างกันของความลับแต่ละใบ — ที่เหลือเหมือนกันหมด
    public struct Wording: Sendable {
        /// ชื่อที่ใช้เรียกความลับใบนี้ในประโยค เช่น "session key"
        public let noun: String
        /// ยังไม่มีไฟล์เลย — ทำอย่างไรถึงจะมี
        public let missing: String
        /// มีไฟล์แต่ว่าง — ต้องเอาอะไรใส่ลงไป
        public let empty: String

        public init(noun: String, missing: String, empty: String) {
            self.noun = noun
            self.missing = missing
            self.empty = empty
        }
    }

    /// เขียนความลับทับของเดิมแบบ mode 600 ตั้งแต่วินาทีแรกที่ไฟล์มีตัวตน
    ///
    /// สร้างไฟล์ชั่วคราวด้วยสิทธิ์ 600 แล้วค่อย rename ทับ ไม่ใช่เขียนก่อนแล้ว `chmod`
    /// ทีหลัง — ช่วงระหว่างสองคำสั่งนั้นคือช่วงที่ credential เปิดให้คนอื่นอ่าน
    public static func write(_ raw: String, to url: URL, wording: Wording) throws {
        let secret = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else {
            throw Problem(message: "the \(wording.noun) is empty — \(wording.empty)")
        }
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).tamaclaude.tmp")
        try? FileManager.default.removeItem(at: tmp)
        guard FileManager.default.createFile(
            atPath: tmp.path, contents: Data(secret.utf8),
            attributes: [.posixPermissions: 0o600])
        else {
            throw Problem(message: "could not write \(url.path)")
        }
        // `replaceItemAt` คัดลอกสิทธิ์ของไฟล์เดิมกลับมาได้ — ไฟล์ 644 ที่ผู้ใช้เคยสร้างเอง
        // จะยังเป็น 644 ต่อไปทั้งที่เพิ่งเขียนใหม่ จึงลบทิ้งแล้ว rename ตรงๆ แทน
        try? FileManager.default.removeItem(at: url)
        do {
            try FileManager.default.moveItem(at: tmp, to: url)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw Problem(message: "could not write \(url.path)")
        }
    }

    /// อ่านความลับกลับมา — ปฏิเสธไฟล์ที่คนอื่นบนเครื่องเปิดได้
    ///
    /// อ่านใหม่ทุกรอบ ไม่เก็บไว้ในหน่วยความจำ: key หมดอายุได้ และวิธีแก้ต้องเป็นแค่
    /// การ paste ทับไฟล์ ไม่ใช่การไล่หาโปรเซสมารีสตาร์ท
    public static func read(at url: URL, wording: Wording) throws -> String {
        // ตรวจสิทธิ์ของไฟล์ปลายทาง ไม่ใช่ของ symlink — `attributesOfItem` ไม่ตาม link
        // และ symlink มีสิทธิ์ 0o755 เสมอ ผู้ใช้ที่ link ไฟล์ 600 มาไว้ตรงนี้จะโดนปฏิเสธ
        // พร้อมคำแนะนำ `chmod` ที่แก้อะไรไม่ได้เลย
        let target = url.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw Problem(message: "no \(wording.noun) at \(url.path) — \(wording.missing)")
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: target.path),
            let mode = (attrs[.posixPermissions] as? NSNumber)?.uint16Value
        else {
            throw Problem(message: "cannot read the permissions of \(url.path)")
        }
        // 0o077 = สิทธิ์ของ group และ other ทั้งหมด — บิตใดติดก็แปลว่าความลับนี้ไม่ได้
        // เป็นของเจ้าของไฟล์คนเดียวแล้ว
        guard mode & 0o077 == 0 else {
            throw Problem(
                message: "\(url.path) is readable by other users; run `chmod 600 \(url.path)`")
        }
        // อ่านไม่ออกกับว่างเปล่าเป็นคนละอาการ วิธีแก้จึงคนละอย่าง — ข้อความต้องแยกกัน
        guard let text = try? String(contentsOf: target, encoding: .utf8) else {
            throw Problem(message: "\(url.path) is not readable text")
        }
        let secret = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else {
            throw Problem(message: "\(url.path) is empty — \(wording.empty)")
        }
        return secret
    }
}
