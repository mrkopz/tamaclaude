import Foundation

/// แปลง JSON ที่ Claude Code ป้อนเข้า statusline ให้เป็น cache ที่ daemon อ่านได้
///
/// เขียนคีย์ชุดเดียวกับที่ Claude Usage.app ใช้ และเวลาเป็น ISO8601 เหมือนกัน
/// เพื่อให้ statusline เดิมของผู้ใช้อ่านไฟล์นี้ต่อได้โดยไม่ต้องแก้อะไรเลย —
/// `rate_limits` ให้ epoch มา เราจึงต้องแปลงเป็น ISO ก่อนเขียน ไม่งั้นบรรทัด
/// statusline ที่ parse ด้วย `date -ju -f "%Y-%m-%dT%H:%M:%S"` จะพังทันที
public enum UsageWriter {
    /// อ่าน JSON ของ statusline แล้วเขียน cache — คืนบรรทัดสั้นไว้ใช้เป็น fallback
    /// เมื่อผู้ใช้ไม่มี statusline เดิมให้ส่งงานต่อ
    @discardableResult
    public static func ingest(
        _ data: Data, now: Date = Date(), to url: URL = Paths.usageCache
    ) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let limits = root["rate_limits"] as? [String: Any]
        else { return nil }

        var fields: [(String, String)] = []
        var parts: [String] = []

        // เอกสารระบุว่าแต่ละหน้าต่างหายอิสระต่อกัน — คีย์ที่ไม่มีข้อมูลจะไม่ถูกเขียนเลย
        // การเขียนค่าว่างจะทำให้ฝั่งอ่านแยก "ไม่มี" ออกจาก "เป็น 0" ไม่ได้
        for (jsonKey, pctKey, resetKey, label) in [
            ("five_hour", "UTILIZATION", "RESETS_AT", "5h"),
            ("seven_day", "WEEKLY_UTILIZATION", "WEEKLY_RESETS_AT", "7d"),
        ] {
            guard let window = limits[jsonKey] as? [String: Any] else { continue }
            if let pct = window["used_percentage"] as? Int {
                fields.append((pctKey, String(pct)))
                parts.append("\(label) \(pct)%")
            } else if let pct = window["used_percentage"] as? Double {
                fields.append((pctKey, String(Int(pct.rounded()))))
                parts.append("\(label) \(Int(pct.rounded()))%")
            }
            if let epoch = window["resets_at"] as? Double {
                fields.append((resetKey, iso(Date(timeIntervalSince1970: epoch))))
            } else if let epoch = window["resets_at"] as? Int {
                fields.append((resetKey, iso(Date(timeIntervalSince1970: Double(epoch)))))
            }
        }

        guard !fields.isEmpty else { return nil }

        var merged = merge(fields, into: url)
        merged.append(("TIMESTAMP", String(Int(now.timeIntervalSince1970))))

        let text = merged.map { "\($0)=\($1)" }.joined(separator: "\n") + "\n"
        write(text, to: url)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// รวมกับค่าที่มีอยู่ในไฟล์ แทนที่จะเขียนทับดื้อๆ
    ///
    /// `rate_limits` ที่ Claude Code ป้อนมาคือค่าจาก **API response ล่าสุดของ session นี้**
    /// ซึ่งค้างได้ระหว่างที่ไม่มีการเรียก API ส่วนแหล่งอื่น (เช่น Claude Usage.app ที่ยิง
    /// API เอง หรืออีก session ที่คุยกับ Claude อยู่) อาจรู้ค่าที่ใหม่กว่าและเขียนไฟล์นี้ไว้แล้ว
    ///
    /// invariant ที่ใช้ตัดสิน: **ภายในหน้าต่างเดียวกัน เปอร์เซ็นต์เพิ่มอย่างเดียว**
    /// (`resets_at` ตรงกัน = หน้าต่างเดียวกัน) ค่าที่ต่ำกว่าจึงเป็นค่าที่เก่ากว่าเสมอ
    /// พอหน้าต่างหมุน `resets_at` จะเปลี่ยน แล้วค่าที่ลดลงกลายเป็นค่าที่ถูกต้อง
    static func merge(_ incoming: [(String, String)], into url: URL) -> [(String, String)] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return incoming }
        let existing = UsageReader.parse(text)
        var out = incoming
        var fresh = Dictionary(uniqueKeysWithValues: incoming)

        for (pctKey, resetKey) in [("UTILIZATION", "RESETS_AT"),
                                   ("WEEKLY_UTILIZATION", "WEEKLY_RESETS_AT")] {
            guard let oldPct = existing[pctKey].flatMap(Int.init),
                let newPct = fresh[pctKey].flatMap(Int.init),
                existing[resetKey] == fresh[resetKey],  // หน้าต่างเดียวกันเท่านั้นที่เทียบได้
                oldPct > newPct
            else { continue }
            fresh[pctKey] = String(oldPct)
            out = out.map { $0.0 == pctKey ? ($0.0, String(oldPct)) : $0 }
        }

        // คีย์ที่แหล่งอื่นเขียนไว้แต่เราไม่รู้จัก (เช่น PROFILE_NAME, COST_*) ต้องรอดไป
        // ไม่งั้นเราทำลายข้อมูลของเจ้าของร่วมที่เขียนไฟล์เดียวกันนี้
        let known = Set(["UTILIZATION", "RESETS_AT", "WEEKLY_UTILIZATION", "WEEKLY_RESETS_AT",
                         "TIMESTAMP"])
        for (k, v) in existing.sorted(by: { $0.key < $1.key }) where !known.contains(k) {
            out.append((k, v))
        }
        return out
    }

    /// เขียนแบบ temp + rename — Claude Usage.app เขียนไฟล์เดียวกันอยู่
    /// การ rename เป็น operation เดียว จึงไม่มีใครอ่านเจอไฟล์ที่เขียนค้างครึ่งทาง
    static func write(_ text: String, to url: URL) {
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tamaclaude.tmp")
        guard (try? text.write(to: tmp, atomically: false, encoding: .utf8)) != nil else { return }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        try? FileManager.default.removeItem(at: tmp)
    }

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }
}
