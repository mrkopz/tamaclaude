import Foundation

/// ตัวเขียนไฟล์ session key — แอปเป็นคนเขียน ผู้ใช้แค่วางค่าลงช่องกรอก
///
/// เหตุผลที่ไม่ปล่อยให้ผู้ใช้ไปสร้างไฟล์เอง: สิทธิ์ของไฟล์เป็นส่วนหนึ่งของความปลอดภัย
/// ของ credential เต็มบัญชี คนที่ `echo … > file` แล้วลืม `chmod 600` จะได้ไฟล์ที่
/// ทุกคนบนเครื่องอ่านได้ แล้วเจอแค่ข้อความปฏิเสธที่เขาไม่ได้ตั้งใจให้เกิด
///
/// อ่านกลับมาทาง `UsagePoll.readKey` ตัวเดิมเสมอ — กฎว่าอะไรคือไฟล์ที่ใช้ได้มีสำเนาเดียว
public enum SessionKeyFile {
    /// ประโยคของความลับใบนี้ — กติกาว่าอะไรคือไฟล์ที่ใช้ได้อยู่ที่ `SecretFile` ที่เดียว
    /// ร่วมกับ key ของ Finnhub ต่างกันแค่คำที่บอกผู้ใช้ว่าต้องไปเอาอะไรมาจากไหน
    static let wording = SecretFile.Wording(
        noun: "session key",
        missing: "set one from the TamaClaude gear menu, or paste the claude.ai sessionKey "
            + "cookie into that file and `chmod 600` it",
        empty: "paste the claude.ai sessionKey cookie into it")

    /// เขียน key ทับของเดิมแบบ mode 600 ตั้งแต่วินาทีแรกที่ไฟล์มีตัวตน
    public static func write(_ raw: String, to url: URL = Paths.sessionKey) throws {
        do {
            try SecretFile.write(raw, to: url, wording: wording)
        } catch let problem as SecretFile.Problem {
            throw UsagePoll.Failure(
                message: problem.message, code: UsagePoll.Failure.unusableKeyFile)
        }
    }

    /// มี key ที่ใช้ยิงได้จริงไหม — ไม่ใช่แค่ "ไฟล์มีอยู่"
    ///
    /// ผู้เรียกใช้ตัวนี้ตัดสินใจว่าจะ spawn ลูกไหม: ยิงทั้งที่รู้อยู่แล้วว่าไม่มี key คือ
    /// การเผาโปรเซสทุกนาทีเพื่อให้ได้ error เดิม
    public static func isUsable(at url: URL = Paths.sessionKey) -> Bool {
        (try? UsagePoll.readKey(at: url)) != nil
    }
}
