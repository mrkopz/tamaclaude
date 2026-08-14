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
        _ data: Data, now: Date = Date(), to url: URL = Paths.usageCache,
        ledger: URL = Paths.spendLedger, calendar: Calendar = .current
    ) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        // ไม่มี `rate_limits` ไม่ใช่เหตุให้เลิกอีกต่อไป — บัญชีที่ auth ด้วย API key
        // ของ Console ไม่เคยได้คีย์นี้เลย แต่ payload เดียวกันพก `cost` มาให้
        let limits = root["rate_limits"] as? [String: Any] ?? [:]

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

        // งบเงินเขียนคีย์ของตัวเอง ไม่ไปแย่งช่อง weekly
        //
        // เขียนเสมอเมื่อมี `cost` มา ไม่ใช่เขียนเฉพาะตอนช่อง weekly ว่าง เพราะ
        // ผู้ใช้คนเดียวเปิดได้ทั้ง session ที่ auth ด้วย subscription และ session
        // ที่ auth ด้วย API key พร้อมกัน — ทั้งสองยิง statusline เข้าไฟล์เดียวกัน
        // สลับกันไปมา ถ้าตัดสินใจกันตรงนี้ แถบจะกระพริบสลับสองความหมายตามว่า
        // session ไหนวาดทีหลัง การตัดสินจึงย้ายไปอยู่ที่ `UsageReader` ที่เดียว
        // ซึ่งเห็นทั้งสองคีย์พร้อมกันและเลือกครั้งเดียว
        if let id = root["session_id"] as? String,
            let cost = ((root["cost"] as? [String: Any])?["total_cost_usd"] as? NSNumber)?
                .doubleValue,
            let budget = SpendLedger.record(
                sessionID: id, costUSD: cost,
                // `rate_limits` มาด้วย = บัญชีนี้อยู่ในโควตา subscription ไม่ได้จ่ายรายทาง
                reportsQuota: !limits.isEmpty,
                now: now, at: ledger, calendar: calendar)
        {
            // ชื่อคีย์ล้อของเดิม: ไม่มีคำนำหน้า = บาน 5 ชั่วโมง, `WEEKLY_` = เจ็ดวัน
            for (reading, pctKey, resetKey) in [
                (budget.session, "BUDGET_UTILIZATION", "BUDGET_RESETS_AT"),
                (budget.weekly, "BUDGET_WEEKLY_UTILIZATION", "BUDGET_WEEKLY_RESETS_AT"),
            ] {
                fields.append((pctKey, String(reading.percent)))
                fields.append((resetKey, iso(reading.resetsAt)))
            }
            // บรรทัด fallback บอกว่าเป็นงบ ไม่ใช่โควตา — ผู้ใช้ที่ไม่มี statusline
            // เดิมจะได้ไม่เข้าใจว่า Anthropic เริ่มรายงานโควตาให้ API key แล้ว
            if !fields.contains(where: { $0.0 == "UTILIZATION" }) {
                parts.append("budget \(budget.session.percent)%")
            }
        }

        return commit(fields, parts: parts, now: now, to: url)
    }

    /// อ่าน payload ของ `/api/organizations/<org>/usage` แล้วเขียน cache เดียวกัน
    ///
    /// ทางเข้าที่สอง ไม่ใช่ module ที่สอง — กฎ "ภายในหน้าต่างเดียวกัน เปอร์เซ็นต์เพิ่ม
    /// อย่างเดียว" ต้องมีเจ้าของคนเดียว ถ้าแยกไปเขียน cache จากที่อื่น กฎจะมีสองสำเนา
    /// แล้ววันหนึ่งจะไม่ตรงกัน — ทั้งสองทางจึงลง `merge`/`write` ตัวเดียวกัน
    @discardableResult
    public static func ingestAPI(
        _ data: Data, now: Date = Date(), to url: URL = Paths.usageCache
    ) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var fields: [(String, String)] = []
        var parts: [String] = []

        // ชื่อคีย์ weekly มีหลายแบบที่เคยเจอในสนามจริง ส่วน `weekly_scoped` เป็น limit
        // ราย model ไม่ใช่ของทั้งบัญชี จึงไม่อยู่ในรายการ kind ที่ยอมรับ
        for (keys, kind, pctKey, resetKey, label) in [
            (["five_hour"], "session", "UTILIZATION", "RESETS_AT", "5h"),
            (["seven_day", "weekly", "week", "seven_days"], "weekly_all",
             "WEEKLY_UTILIZATION", "WEEKLY_RESETS_AT", "7d"),
        ] {
            guard let found = window(root, keys: keys, kind: kind) else { continue }
            fields.append((pctKey, String(found.percent)))
            // เวลาผ่าน formatter ตัวเดียวกับทางเข้าเดิมเสมอ ไม่ใช่ส่ง ISO ดิบลงไฟล์ —
            // "…:00Z" กับ "…:00.482Z" คือหน้าต่างเดียวกัน แต่เป็นคนละสตริง แล้ว merge
            // จะเข้าใจว่าหน้าต่างหมุนแล้วและปล่อยให้เปอร์เซ็นต์ถอยหลัง
            fields.append((resetKey, iso(found.resetsAt)))
            parts.append("\(label) \(found.percent)%")
        }

        return commit(fields, parts: parts, now: now, to: url)
    }

    /// หาหน้าต่างหนึ่งบานจาก payload — ระดับบนสุดก่อน แล้วค่อย `limits` array
    ///
    /// payload พก​ตัวเลขชุดเดียวกันมาสองที่ ระดับบนสุดกำกวมน้อยกว่า (คีย์บอกชนิด
    /// ตรงตัว) จึงอ่านก่อน `utilization` เป็น float ส่วน `percent` เป็น int —
    /// ปัดทั้งคู่ ไม่ตัดทิ้ง ไม่งั้นสองทางจะต่างกันหนึ่งจุดที่ค่าอย่าง 16.6
    ///
    /// เปอร์เซ็นต์ที่ไม่มี `resets_at` ที่อ่านออกถือว่าไม่มีหน้าต่าง — ทิ้งทั้งบาน
    /// เพราะกฎ "เพิ่มอย่างเดียว" เทียบได้ก็ต่อเมื่อรู้ว่าเป็นหน้าต่างเดียวกัน
    /// ตัวเลขลอยๆ จะเข้า merge ในฐานะหน้าต่างใหม่ แล้วลากค่าที่ถูกต้องให้ถอยหลัง
    static func window(
        _ root: [String: Any], keys: [String], kind: String
    ) -> (percent: Int, resetsAt: Date)? {
        for key in keys {
            guard let entry = root[key] as? [String: Any],
                let pct = (entry["utilization"] as? NSNumber)?.doubleValue,
                let at = (entry["resets_at"] as? String).flatMap(parseISO)
            else { continue }
            return (Int(pct.rounded()), at)
        }

        for case let entry as [String: Any] in root["limits"] as? [Any] ?? [] {
            guard entry["kind"] as? String == kind,
                let pct = (entry["percent"] as? NSNumber)?.doubleValue,
                let at = (entry["resets_at"] as? String).flatMap(parseISO)
            else { continue }
            return (Int(pct.rounded()), at)
        }
        return nil
    }

    /// จบงานของทั้งสองทางเข้า — merge, ประทับเวลา, เขียน
    ///
    /// ทางเข้าที่สอง ไม่ใช่ module ที่สอง: ทั้งสองทางต้องผ่านบรรทัดชุดนี้ชุดเดียว
    /// ไม่งั้นวันที่รูปแบบไฟล์เปลี่ยน จะมีที่ให้ลืมแก้อยู่หนึ่งที่เสมอ
    static func commit(
        _ fields: [(String, String)], parts: [String], now: Date, to url: URL
    ) -> String? {
        guard !fields.isEmpty else { return nil }

        var merged = merge(fields, into: url)
        merged.append(("TIMESTAMP", String(Int(now.timeIntervalSince1970))))

        let text = merged.map { "\($0)=\($1)" }.joined(separator: "\n") + "\n"
        write(text, to: url)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// ISO8601 ที่มีเศษวินาทีบ้างไม่มีบ้าง — ลองทั้งสองแบบ
    static func parseISO(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: text) { return date }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
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
                                   ("WEEKLY_UTILIZATION", "WEEKLY_RESETS_AT"),
                                   ("BUDGET_UTILIZATION", "BUDGET_RESETS_AT"),
                                   ("BUDGET_WEEKLY_UTILIZATION", "BUDGET_WEEKLY_RESETS_AT")] {
            guard let oldPct = existing[pctKey].flatMap(Int.init),
                let newPct = fresh[pctKey].flatMap(Int.init),
                existing[resetKey] == fresh[resetKey],  // หน้าต่างเดียวกันเท่านั้นที่เทียบได้
                oldPct > newPct
            else { continue }
            fresh[pctKey] = String(oldPct)
            out = out.map { $0.0 == pctKey ? ($0.0, String(oldPct)) : $0 }
        }

        // คีย์ของงบต้องข้ามรอบที่ไม่มี `cost` มาให้ — `ingestAPI` ไม่เคยมี และ
        // payload ของ Claude Code รุ่นเก่าก็ไม่มี ถ้าปล่อยให้หายไปตามกฎ `known`
        // ข้างล่าง แถบงบจะกระพริบตามว่ารอบล่าสุดมาจากทางเข้าไหน
        for key in ["BUDGET_UTILIZATION", "BUDGET_RESETS_AT",
                    "BUDGET_WEEKLY_UTILIZATION", "BUDGET_WEEKLY_RESETS_AT"]
        where fresh[key] == nil {
            guard let value = existing[key] else { continue }
            out.append((key, value))
        }

        // คีย์ที่แหล่งอื่นเขียนไว้แต่เราไม่รู้จัก (เช่น PROFILE_NAME, COST_*) ต้องรอดไป
        // ไม่งั้นเราทำลายข้อมูลของเจ้าของร่วมที่เขียนไฟล์เดียวกันนี้
        let known = Set(["UTILIZATION", "RESETS_AT", "WEEKLY_UTILIZATION", "WEEKLY_RESETS_AT",
                         "BUDGET_UTILIZATION", "BUDGET_RESETS_AT",
                         "BUDGET_WEEKLY_UTILIZATION", "BUDGET_WEEKLY_RESETS_AT", "TIMESTAMP"])
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
