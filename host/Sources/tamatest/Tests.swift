import Foundation
import TamaCore

let t0 = Date(timeIntervalSince1970: 1_700_000_000)

func event(
    _ name: String,
    _ session: String = "s1",
    tool: String? = nil,
    cwd: String = "/Users/x/Documents/GitHub/tamaclaude",
    message: String? = nil
) -> HookEvent {
    HookEvent(
        hookEventName: name, sessionId: session, cwd: cwd, toolName: tool, message: message)
}

/// store ที่ข้ามท่าเดินเข้ามา — เทสต์ส่วนใหญ่ไม่ได้สนใจท่านั้น
func store() -> SessionStore {
    var timings = Timings()
    timings.entering = 0
    return SessionStore(timings: timings)
}

func runAllTests() {
    suite("tool mapping") {
        equal(ToolMap.default.state(for: "Read"), .reading, "Read is reading")
        equal(ToolMap.default.state(for: "Bash"), .building, "Bash is building")
        equal(ToolMap.default.state(for: "WebSearch"), .searching, "WebSearch is searching")
        equal(
            ToolMap.default.state(for: "mcp__tolaria__search_notes"), .beacon,
            "mcp__ prefix rule applies")
        equal(ToolMap.default.state(for: "LSP"), .beacon, "LSP talks to a service, not the disk")
        equal(ToolMap.default.state(for: "SomethingNew"), .thinking, "unknown tool falls back")
    }

    suite("tool map config file") {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tools-\(UUID().uuidString).json")
        try Data(#"{"fallback":"idle","tools":{"Read":"building","zz__*":"error"}}"#.utf8)
            .write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let map = try ToolMap.load(from: url)
        equal(map.state(for: "Read"), .building, "config overrides a built-in")
        equal(map.state(for: "zz__x"), .error, "config adds a prefix rule")
        equal(map.state(for: "Whatever"), .idle, "config sets the fallback")
        equal(map.state(for: "Bash"), .building, "untouched built-ins survive")
    }

    suite("session state") {
        let s = store()
        s.apply(event("SessionStart"), now: t0)
        s.apply(event("PreToolUse", tool: "Edit"), now: t0 + 1)
        equal(s.snapshot(now: t0 + 1).sessions.first?.state, .writing, "tool drives the mascot")
        s.apply(event("PostToolUse", tool: "Edit"), now: t0 + 2)
        equal(
            s.snapshot(now: t0 + 2).sessions.first?.state, .writing,
            "the pose lingers so a fast tool is still visible")
        equal(s.snapshot(now: t0 + 7).sessions.first?.state, .thinking, "back to thinking after a tool")
        equal(s.snapshot(now: t0 + 7).sessions.first?.project, "tamaclaude", "project name from cwd")
    }

    suite("every pose stays on screen long enough to read") {
        let s = store()
        s.apply(event("PreToolUse", tool: "Read"), now: t0)
        equal(s.snapshot(now: t0).sessions.first?.state, .reading, "the pose goes up at once")

        // เครื่องมือรัวๆ ในหนึ่งวินาที: ท่าที่ถูกข้ามหายไปเลย ไม่เข้าคิวมาเล่าย้อนหลัง
        s.apply(event("PostToolUse", tool: "Read"), now: t0 + 0.2)
        s.apply(event("PreToolUse", tool: "Edit"), now: t0 + 0.3)
        s.apply(event("PostToolUse", tool: "Edit"), now: t0 + 0.5)
        equal(s.snapshot(now: t0 + 1).sessions.first?.state, .reading, "a burst does not flicker")
        equal(s.snapshot(now: t0 + 4).sessions.first?.state, .reading, "it holds the whole window")
        equal(s.snapshot(now: t0 + 5).sessions.first?.state, .thinking, "then catches up to now")

        // แต่เรื่องด่วนกว่าไม่ต้องรอคิว
        let f = store()
        f.apply(event("PreToolUse", tool: "Read"), now: t0)
        equal(f.snapshot(now: t0).sessions.first?.state, .reading, "a tool is on screen")
        f.apply(event("StopFailure"), now: t0 + 1)
        equal(f.snapshot(now: t0 + 1).sessions.first?.state, .error, "trouble cuts the line")
    }

    suite("a permission card does not outlive the request") {
        let s = store()
        s.apply(event("PreToolUse", tool: "Bash"), now: t0)
        s.apply(event("Notification", message: "Claude needs your permission"), now: t0 + 1)
        equal(s.snapshot(now: t0 + 1).cards.count, 1, "the request raises a card")

        s.apply(event("PostToolUse", tool: "Bash"), now: t0 + 5)
        equal(s.snapshot(now: t0 + 5).cards.count, 0, "granting it and moving on clears the card")

        // ปฏิเสธไม่มี PostToolUse ตามมาเสมอ ตัวจบเทิร์นจึงต้องล้างให้ด้วย
        let d = store()
        d.apply(event("Notification", message: "Claude needs your permission"), now: t0)
        d.apply(event("Stop"), now: t0 + 3)
        equal(d.snapshot(now: t0 + 3).cards.count, 0, "so does the turn ending")
    }

    suite("subagents") {
        let s = store()
        s.apply(event("PreToolUse", tool: "Edit"), now: t0)
        equal(s.snapshot(now: t0).sessions.first?.state, .writing, "tool state before any subagent")

        s.apply(event("SubagentStart"), now: t0 + 1)
        equal(
            s.snapshot(now: t0 + 1).sessions.first?.state, .conducting,
            "a running subagent takes over the mascot")

        // subagent ตัวใน ยิง hook ด้วย session_id เดียวกัน — ท่าต้องไม่กระพริบตามมัน
        s.apply(event("PreToolUse", tool: "Bash"), now: t0 + 2)
        equal(
            s.snapshot(now: t0 + 2).sessions.first?.state, .conducting,
            "tools fired from inside the subagent do not steal the slot back")

        s.apply(event("SubagentStart"), now: t0 + 3)
        s.apply(event("SubagentStop"), now: t0 + 4)
        equal(
            s.snapshot(now: t0 + 4).sessions.first?.state, .conducting,
            "one of two finishing is not the end of it")
        s.apply(event("SubagentStop"), now: t0 + 5)
        equal(
            s.snapshot(now: t0 + 6).sessions.first?.state, .thinking,
            "the last one finishing hands the mascot back")
    }

    suite("subagents lose to trouble") {
        let s = store()
        s.apply(event("SubagentStart"), now: t0)
        s.apply(event("Notification", message: "allow Bash?"), now: t0 + 1)
        equal(
            s.snapshot(now: t0 + 1).sessions.first?.state, .waiting,
            "needing you beats being busy")

        let f = store()
        f.apply(event("SubagentStart"), now: t0)
        f.apply(event("StopFailure"), now: t0 + 1)
        equal(f.snapshot(now: t0 + 1).sessions.first?.state, .error, "so does breaking")
    }

    suite("subagent counter never sticks") {
        // SubagentStop ที่หายไป (daemon ไม่ได้รันตอนนั้น) ต้องไม่ทำให้ท่าค้างตลอดกาล
        for (name, expected) in [("Stop", VisualState.celebrate), ("UserPromptSubmit", .thinking)] {
            let s = store()
            s.apply(event("SubagentStart"), now: t0)
            s.apply(event("SubagentStart"), now: t0 + 1)
            s.apply(event(name), now: t0 + 2)
            equal(s.snapshot(now: t0 + 2).sessions.first?.state, expected, "\(name) clears it")
        }
    }

    suite("walk in, burrow out") {
        let s = SessionStore()
        s.apply(event("SessionStart"), now: t0)
        equal(s.snapshot(now: t0).sessions.first?.state, .entering, "new session walks in")
        equal(s.snapshot(now: t0 + 3).sessions.first?.state, .idle, "then settles")
        s.apply(event("SessionEnd"), now: t0 + 5)
        equal(s.snapshot(now: t0 + 5).sessions.first?.state, .leaving, "ending session burrows away")
        equal(s.snapshot(now: t0 + 8).sessions.count, 0, "and is gone after the animation")
    }

    suite("stop and the 45 second rule") {
        let s = store()
        s.apply(event("Stop"), now: t0)
        equal(s.snapshot(now: t0 + 1).sessions.first?.state, .celebrate, "celebrates first")
        equal(s.snapshot(now: t0 + 10).sessions.first?.state, .idle, "then idles")
        equal(s.snapshot(now: t0 + 44).cards.count, 0, "silence under the threshold is fine")

        let late = s.snapshot(now: t0 + 46)
        equal(late.cards.count, 1, "silence past the threshold raises a card")
        equal(late.cards.first?.kind, .done, "a finished turn is not an alert")
        equal(late.cards.first?.body, "your turn", "it says whose move it is")
        equal(late.sessions.first?.state, .waiting, "mascot asks for you")

        s.apply(event("UserPromptSubmit"), now: t0 + 50)
        let after = s.snapshot(now: t0 + 52)
        equal(after.cards.count, 0, "answering clears the card")
        equal(after.sessions.first?.state, .thinking, "and puts it back to work")
    }

    suite("notification") {
        let s = store()
        s.apply(event("Notification", message: "Claude needs your permission"), now: t0)
        let snap = s.snapshot(now: t0)
        equal(snap.sessions.first?.state, .waiting, "notification means waiting")
        equal(snap.cards.first?.body, "Claude needs your permission", "message becomes the card body")
        equal(snap.cards.first?.kind, .alert, "something is genuinely stuck on you")
    }

    suite("red means a hand is needed") {
        // สีแดงสงวนไว้ให้เรื่องที่เดินต่อเองไม่ได้ ไม่ใช่ทุกเทิร์นที่จบ
        let f = store()
        f.apply(event("StopFailure"), now: t0)
        equal(f.snapshot(now: t0).cards.first?.kind, .alert, "breaking is an alert")

        let d = store()
        d.apply(event("Stop"), now: t0)
        equal(d.snapshot(now: t0 + 46).cards.first?.kind, .done, "a quiet finished turn is not")
    }

    suite("time alone changes the picture") {
        let s = store()
        s.apply(event("Stop"), now: t0)
        equal(s.snapshot(now: t0 + 400).sessions.first?.state, .sleeping, "idle long enough = asleep")
        equal(s.snapshot(now: t0 + 4000).sessions.count, 0, "stale sessions are evicted")
    }

    suite("slot order") {
        let s = store()
        for i in 1...3 {
            s.apply(
                event("PreToolUse", "s\(i)", tool: "Read", cwd: "/tmp/p\(i)"),
                now: t0 + Double(i))
        }
        s.apply(event("PreToolUse", "s1", tool: "Bash", cwd: "/tmp/p1"), now: t0 + 10)
        equal(
            s.snapshot(now: t0 + 10).sessions.map(\.project), ["p1", "p2", "p3"],
            "left-to-right order never shuffles")
    }

    suite("overflow") {
        let s = store()
        for i in 1...5 {
            s.apply(event("SessionStart", "s\(i)", cwd: "/tmp/p\(i)"), now: t0)
        }
        s.apply(event("Notification", "s5", cwd: "/tmp/p5", message: "look"), now: t0 + 1)
        let snap = s.snapshot(now: t0 + 1)
        equal(snap.overflow, 2, "sessions past the slot count are counted, not drawn")
        equal(
            snap.sessions.map(\.project), ["p3", "p4", "p5"],
            "the urgent one keeps its slot")

        let s2 = store()
        for i in 1...6 {
            s2.apply(event("SessionStart", "s\(i)", cwd: "/tmp/p\(i)"), now: t0)
        }
        s2.apply(event("Notification", "s1", cwd: "/tmp/p1", message: "hey"), now: t0 + 1)
        expect(
            s2.snapshot(now: t0 + 1).cards.contains { $0.body == "hey" },
            "an alert from an overflowed session still reaches the user")
    }

    suite("text for the board font") {
        equal(Text.sanitize("done \u{2014} ok"), "done - ok", "em dash becomes a hyphen")
        equal(Text.sanitize("caf\u{00E9} \u{4E2D}\u{6587}"), "caf", "undrawable characters are dropped")
        equal(Text.sanitize("a\u{2026}"), "a...", "ellipsis is spelled out")
        equal(Text.sanitize("a \n\t b "), "a b", "whitespace collapses")
        equal(Text.clip("abcdefgh", to: 5), "ab...", "clipping is marked")
        equal(Text.clip("abc", to: 5), "abc", "short text is untouched")
        let dirty = "Edit \u{2192} src/main.swift \u{2014} \u{201C}quoted\u{201D} \u{4E2D}"
        expect(Text.fit(dirty, to: 46).allSatisfy { $0.isASCII }, "output is always plain ASCII")
    }

    suite("wire format") {
        let big = Snapshot(
            clock: "14:32",
            date: "Mon 27 Jul",
            overflow: 3,
            sessions: (1...4).map { SessionSnap(project: "project-name\($0)", state: .searching) },
            cards: (1...3).map {
                CardSnap(
                    title: "a fairly long notification title \($0)",
                    body: "and a body that describes what happened \($0)",
                    kind: .alert)
            })
        let data = try big.encoded()
        expect(data.count <= Wire.maxPayload, "worst case fits one MTU (got \(data.count)B)")

        let squeezed = try JSONDecoder().decode(
            Snapshot.self, from: big.encoded(maxBytes: 200))
        equal(squeezed.sessions.count, 4, "sessions survive the squeeze")
        equal(squeezed.clock, "14:32", "so does the clock")

        let snap = Snapshot(
            clock: "09:05", date: "Tue 1 Jan",
            sessions: [SessionSnap(project: "tamaclaude", state: .writing)],
            cards: [CardSnap(title: "t", body: "b", kind: .done)])
        let back = try JSONDecoder().decode(Snapshot.self, from: snap.encoded())
        equal(back, snap, "round trips")
    }

    suite("usage cache is written in the shape the old statusline reads") {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        let stdin = """
            {"model":{"id":"claude-opus-5"},
             "rate_limits":{"five_hour":{"used_percentage":35,"resets_at":1700011000},
                            "seven_day":{"used_percentage":48,"resets_at":1700111000}}}
            """
        let line = UsageWriter.ingest(Data(stdin.utf8), now: t0, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        expect(line?.contains("5h 35%") == true, "fallback line reports the session window")
        expect(text.contains("UTILIZATION=35"), "session percent uses the original key name")
        expect(text.contains("WEEKLY_UTILIZATION=48"), "weekly percent too")
        // ISO ไม่ใช่ epoch — statusline เดิม parse ด้วย date -ju -f "%Y-%m-%dT%H:%M:%S"
        expect(text.contains("RESETS_AT=2023-11-15T0"), "reset time is written back as ISO8601")
        expect(!text.contains("=\n"), "no key is ever written with an empty value")

        // หน้าต่างที่ไม่มีมาต้องไม่โผล่เป็นคีย์ — ไม่งั้นแยก \"ไม่มี\" จาก 0% ไม่ออก
        // เริ่มจากไฟล์สะอาด ไม่งั้นกติกา \"ห้ามถอยหลัง\" จะเก็บค่าเดิมไว้ ซึ่งเป็นคนละเรื่องกัน
        try? FileManager.default.removeItem(at: url)
        let partial = #"{"rate_limits":{"five_hour":{"used_percentage":0,"resets_at":1700011000}}}"#
        UsageWriter.ingest(Data(partial.utf8), now: t0, to: url)
        let only = try String(contentsOf: url, encoding: .utf8)
        expect(only.contains("UTILIZATION=0"), "zero is a real value, not missing")
        expect(!only.contains("WEEKLY_"), "an absent window writes no keys at all")

        expect(UsageWriter.ingest(Data(#"{"model":{"id":"x"}}"#.utf8), now: t0, to: url) == nil,
               "no rate_limits means nothing to record")
    }

    suite("usage cache never goes backwards") {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        // แหล่งอื่นเขียนไว้ก่อน (Claude Usage.app ยิง API เอง จึงรู้ค่าที่ใหม่กว่าได้)
        try Data("""
            UTILIZATION=54
            RESETS_AT=2023-11-15T03:00:00Z
            WEEKLY_UTILIZATION=33
            WEEKLY_RESETS_AT=2023-11-20T00:00:00Z
            PROFILE_NAME=ThaiTop
            """.utf8).write(to: url)

        // stdin ของ statusline ค้างอยู่ที่ค่าเก่า เพราะยังไม่มี API response ใหม่ใน session นี้
        let stale = """
            {"rate_limits":{"five_hour":{"used_percentage":47,"resets_at":1700017200},
                            "seven_day":{"used_percentage":33,"resets_at":1700438400}}}
            """
        UsageWriter.ingest(Data(stale.utf8), now: t0, to: url)
        var text = try String(contentsOf: url, encoding: .utf8)
        expect(text.contains("UTILIZATION=54"), "a lower percent in the same window is stale, not new")
        expect(text.contains("PROFILE_NAME=ThaiTop"), "keys owned by other writers survive")

        // ค่าที่สูงขึ้นในหน้าต่างเดิมคือค่าใหม่จริง ต้องเขียน
        let fresher = #"{"rate_limits":{"five_hour":{"used_percentage":61,"resets_at":1700017200}}}"#
        UsageWriter.ingest(Data(fresher.utf8), now: t0, to: url)
        text = try String(contentsOf: url, encoding: .utf8)
        expect(text.contains("UTILIZATION=61"), "a higher percent always wins")

        // หน้าต่างหมุนแล้ว (resets_at ต่างไป) เปอร์เซ็นต์ที่ลดลงกลายเป็นค่าที่ถูก
        let rolled = #"{"rate_limits":{"five_hour":{"used_percentage":3,"resets_at":1700035200}}}"#
        UsageWriter.ingest(Data(rolled.utf8), now: t0, to: url)
        text = try String(contentsOf: url, encoding: .utf8)
        expect(text.contains("UTILIZATION=3"), "a new window may legitimately drop the percent")
    }

    suite("the /usage payload lands in the same cache through the same rules") {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        // shape A — ตัวเลขอยู่ระดับบนสุด และเป็น float
        let topLevel = """
            {"five_hour":{"utilization":16.6,"resets_at":"2023-11-15T03:00:00Z"},
             "seven_day":{"utilization":42.0,"resets_at":"2023-11-20T00:00:00Z"},
             "limits":[{"kind":"session","percent":3,"resets_at":"2023-11-15T03:00:00Z"}]}
            """
        let line = UsageWriter.ingestAPI(Data(topLevel.utf8), now: t0, to: url)
        var text = try String(contentsOf: url, encoding: .utf8)
        expect(line?.contains("5h 17%") == true, "16.6 rounds up, it does not truncate to 16")
        expect(text.contains("UTILIZATION=17"), "the top-level pair wins over the limits array")
        expect(text.contains("WEEKLY_UTILIZATION=42"), "weekly comes from seven_day")
        expect(text.contains("RESETS_AT=2023-11-15T03:00:00Z"), "reset time is ISO8601")
        expect(text.contains("WEEKLY_RESETS_AT=2023-11-20T00:00:00Z"), "weekly reset time too")

        // shape B — ต้องได้ตัวเลขเดียวกับ shape A ไม่ต่างกันหนึ่งจุด
        try? FileManager.default.removeItem(at: url)
        let array = """
            {"limits":[{"kind":"session","percent":17,"resets_at":"2023-11-15T03:00:00Z"},
                       {"kind":"weekly_all","percent":42,"resets_at":"2023-11-20T00:00:00Z"},
                       {"kind":"weekly_scoped","percent":99,"resets_at":"2023-11-20T00:00:00Z"}]}
            """
        UsageWriter.ingestAPI(Data(array.utf8), now: t0, to: url)
        text = try String(contentsOf: url, encoding: .utf8)
        expect(text.contains("UTILIZATION=17"), "the array path agrees with the top-level path")
        expect(text.contains("WEEKLY_UTILIZATION=42"), "weekly_all is the account-wide window")
        expect(!text.contains("=99"), "weekly_scoped is per-model and is never read as any window")

        // weekly_scoped อย่างเดียวไม่ใช่ weekly — ต้องไม่มีคีย์ weekly เลย ไม่ใช่เขียนเป็น 0
        try? FileManager.default.removeItem(at: url)
        let scopedOnly = """
            {"limits":[{"kind":"session","percent":5,"resets_at":"2023-11-15T03:00:00Z"},
                       {"kind":"weekly_scoped","percent":70,"resets_at":"2023-11-20T00:00:00Z"}]}
            """
        UsageWriter.ingestAPI(Data(scopedOnly.utf8), now: t0, to: url)
        text = try String(contentsOf: url, encoding: .utf8)
        expect(text.contains("UTILIZATION=5"), "the session window still lands")
        expect(!text.contains("WEEKLY_"), "an absent weekly window writes no keys at all")

        // ชื่อคีย์ weekly ที่เคยเจอในสนามจริงต้องอ่านได้เหมือนกัน
        try? FileManager.default.removeItem(at: url)
        let altKey = #"{"weekly":{"utilization":12,"resets_at":"2023-11-20T00:00:00Z"}}"#
        UsageWriter.ingestAPI(Data(altKey.utf8), now: t0, to: url)
        text = try String(contentsOf: url, encoding: .utf8)
        expect(text.contains("WEEKLY_UTILIZATION=12"), "\"weekly\" is another name for seven_day")
    }

    suite("both entrances agree on what a window is") {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        // เศษวินาทีต้องไม่ทำให้สตริงเวลาต่างกัน ไม่งั้น merge จะนึกว่าหน้าต่างหมุนแล้ว
        let fractional = #"{"five_hour":{"utilization":54,"resets_at":"2023-11-15T03:00:00.482Z"}}"#
        UsageWriter.ingestAPI(Data(fractional.utf8), now: t0, to: url)
        var text = try String(contentsOf: url, encoding: .utf8)
        expect(text.contains("RESETS_AT=2023-11-15T03:00:00Z"),
               "fractional seconds normalise to the same string as whole seconds")

        // statusline ให้ epoch ของหน้าต่างเดียวกันมา ค่าที่ต่ำกว่าจึงเป็นค่าเก่า
        let stale = #"{"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1700017200}}}"#
        UsageWriter.ingest(Data(stale.utf8), now: t0, to: url)
        text = try String(contentsOf: url, encoding: .utf8)
        expect(text.contains("UTILIZATION=54"), "the API entrance and the statusline share one window")

        // แล้วสลับทางกลับ — ทาง API ก็ต้องถอยหลังไม่ได้เหมือนกัน
        let backwards = #"{"five_hour":{"utilization":11,"resets_at":"2023-11-15T03:00:00Z"}}"#
        UsageWriter.ingestAPI(Data(backwards.utf8), now: t0, to: url)
        text = try String(contentsOf: url, encoding: .utf8)
        expect(text.contains("UTILIZATION=54"), "a lower percent in the same window is stale either way")

        // หน้าต่างหมุนแล้ว ค่าที่ลดลงกลายเป็นค่าที่ถูก
        let rolled = #"{"five_hour":{"utilization":2,"resets_at":"2023-11-15T08:00:00Z"}}"#
        UsageWriter.ingestAPI(Data(rolled.utf8), now: t0, to: url)
        text = try String(contentsOf: url, encoding: .utf8)
        expect(text.contains("UTILIZATION=2"), "a new window may legitimately drop the percent")
    }

    suite("a payload we cannot read leaves the cache alone") {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        let before = """
            UTILIZATION=54
            RESETS_AT=2023-11-15T03:00:00Z
            COST_TOTAL=12.34
            PROFILE_NAME=ThaiTop
            """
        try Data(before.utf8).write(to: url)

        // เปอร์เซ็นต์ที่ไม่รู้ว่าอยู่หน้าต่างไหน (ไม่มี resets_at หรือ parse ไม่ออก) ใช้ไม่ได้ —
        // ถ้าปล่อยผ่าน merge จะนับเป็นหน้าต่างใหม่แล้วลากค่าที่ถูกต้องให้ถอยหลัง
        for junk in ["not json at all", "[]", "{}", #"{"limits":[]}"#,
                     #"{"limits":[{"kind":"weekly_scoped","percent":9}]}"#,
                     #"{"five_hour":{"resets_at":"2023-11-15T03:00:00Z"}}"#,
                     #"{"five_hour":{"utilization":9}}"#,
                     #"{"five_hour":{"utilization":9,"resets_at":"tuesday-ish"}}"#,
                     #"{"limits":[{"kind":"session","percent":9}]}"#] {
            expect(UsageWriter.ingestAPI(Data(junk.utf8), now: t0, to: url) == nil,
                   "nothing to record in: \(junk)")
        }
        equal(try String(contentsOf: url, encoding: .utf8), before,
              "a failed parse never touches the file, let alone deletes it")

        // เจ้าของร่วมของไฟล์ต้องรอดผ่านทางเข้าใหม่เหมือนที่รอดผ่านทางเข้าเดิม
        let good = #"{"five_hour":{"utilization":80,"resets_at":"2023-11-15T03:00:00Z"}}"#
        UsageWriter.ingestAPI(Data(good.utf8), now: t0, to: url)
        let after = try String(contentsOf: url, encoding: .utf8)
        expect(after.contains("PROFILE_NAME=ThaiTop"), "keys owned by other writers survive")
        expect(after.contains("COST_TOTAL=12.34"), "including the cost keys")
        expect(after.contains("TIMESTAMP=\(Int(t0.timeIntervalSince1970))"), "the write is stamped")

        // temp + rename — ไม่มีไฟล์ค้างให้ใครอ่านเจอครึ่งทาง
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tamaclaude.tmp")
        expect(!FileManager.default.fileExists(atPath: tmp.path), "no temp file is left behind")
    }

    suite("the session key file is refused unless only its owner can read it") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("key-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func keyFile(_ text: String, mode: Int) throws -> URL {
            let url = dir.appendingPathComponent("key-\(mode)-\(UUID().uuidString)")
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.posixPermissions: mode], ofItemAtPath: url.path)
            return url
        }

        func code(_ url: URL) -> Int32? {
            do {
                _ = try UsagePoll.readKey(at: url)
                return nil
            } catch let failure as UsagePoll.Failure {
                return failure.code
            } catch {
                return -1
            }
        }

        let good = try keyFile("sk-secret\n", mode: 0o600)
        equal(try UsagePoll.readKey(at: good), "sk-secret",
              "a 600 file gives its key back, trimmed")

        // credential เต็มบัญชี — บิตของ group หรือ other ติดบิตเดียวก็ไม่ใช่ของเราคนเดียวแล้ว
        for mode in [0o640, 0o604, 0o644, 0o660, 0o666] {
            equal(code(try keyFile("sk-secret", mode: mode)), UsagePoll.Failure.unusableKeyFile,
                  "mode \(String(mode, radix: 8)) is readable by someone else")
        }

        equal(code(try keyFile("", mode: 0o600)), UsagePoll.Failure.unusableKeyFile,
              "an empty file is not a key")
        equal(code(try keyFile("  \n\t ", mode: 0o600)), UsagePoll.Failure.unusableKeyFile,
              "neither is a file of whitespace")
        equal(code(dir.appendingPathComponent("nothing-here")),
              UsagePoll.Failure.unusableKeyFile, "a missing file says how to make one")

        // symlink มีสิทธิ์ 0o755 เสมอ — ถ้าดูสิทธิ์ของ link แทนของไฟล์ปลายทาง ผู้ใช้ที่
        // เก็บ key ไว้ที่อื่นแล้ว link มาจะโดนปฏิเสธพร้อมคำแนะนำ chmod ที่แก้อะไรไม่ได้
        let link = dir.appendingPathComponent("link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: good)
        equal(try UsagePoll.readKey(at: link), "sk-secret",
              "a symlink to a 600 file is the file's permissions, not the link's")

        // ทุกข้อความต้องบอกวิธีแก้ และต้องไม่พา key ติดออกไปด้วย
        do {
            _ = try UsagePoll.readKey(at: try keyFile("sk-secret", mode: 0o644))
            expect(false, "a 644 key file must be refused, not read")
        } catch let failure as UsagePoll.Failure {
            expect(failure.message.contains("chmod 600"), "the message says how to fix it")
            expect(!failure.message.contains("sk-secret"), "and never carries the key itself")
        }
    }

    suite("an org id is parsed out of the response and still not trusted") {
        func parsed(_ json: String) -> String? {
            try? UsagePoll.organizationID(from: Data(json.utf8))
        }

        equal(parsed(#"[{"uuid":"abc-123","id":"legacy"}]"#), "abc-123", "uuid wins")
        equal(parsed(#"[{"id":"legacy-77"}]"#), "legacy-77", "id is the fallback")
        equal(parsed(#"[{"uuid":"first"},{"uuid":"second"}]"#), "first",
              "the first org is the one we mean")

        for junk in ["[]", "{}", "not json", #"[{"name":"no id here"}]"#, #"[{"uuid":""}]"#,
                     #"["a string, not an object"]"#] {
            expect(parsed(junk) == nil, "no org id in: \(junk)")
        }

        // id ที่เปลี่ยน path ได้ ต้องตายตั้งแต่ในมือเรา ไม่ว่าจะมาจาก response ของเราเอง
        // หรือจาก env ที่ผู้ใช้ตั้งไว้ — ปลายทางเป็นของคนอื่น ทุกค่าจึงเป็นค่าภายนอก
        for bad in ["../../admin", "a/b", "/", "..", "x/../../y", ""] {
            expect((try? UsagePoll.validated(bad)) == nil, "rejected as an org id: \(bad)")
            expect(parsed(#"[{"uuid":"\#(bad)"}]"#) == nil,
                   "and rejected just the same when it arrives in a response: \(bad)")
        }
        equal(try UsagePoll.validated("abc-123"), "abc-123", "an ordinary uuid passes through")
    }

    suite("usage reader turns the cache into board-ready rows") {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        expect(UsageReader.read(now: t0, from: url) == nil, "a missing file shows no panel")

        try Data("""
            UTILIZATION=35
            RESETS_AT=2023-11-14T23:45:00Z
            WEEKLY_UTILIZATION=48
            WEEKLY_RESETS_AT=2023-11-16T07:00:00Z
            TIMESTAMP=1700000000
            """.utf8).write(to: url)
        let rows = UsageReader.read(now: t0, from: url)
        equal(rows?.count, 2, "always two rows when there is anything to show")
        equal(rows?[0].percent, 35, "session percent survives")
        // t0 คือ 2023-11-14T22:13:20Z — เหลือ 1h31m40s ปัดลงเป็น 1h31m
        equal(rows?[0].remaining, 5460, "session countdown in seconds")
        equal(rows?[1].remaining, 117_960, "weekly countdown too")
        expect((rows?[0].remaining ?? 1) % 60 == 0, "remaining is rounded to whole minutes")

        // หน้าต่างหมุนไปแล้ว: เปอร์เซ็นต์ที่ค้างอยู่ผิดแน่นอน ค่าที่ถูกคือ \"ไม่รู้\"
        try Data("UTILIZATION=90\nRESETS_AT=2023-11-14T00:00:00Z\n".utf8).write(to: url)
        let rolled = UsageReader.read(now: t0, from: url)
        equal(rolled?[0].percent, UsageSnap.unknown, "a rolled window forgets its percent")
        equal(rolled?[0].remaining, 0, "and reads as resetting")
        equal(rolled?[1].isKnown, false, "the window that was never there stays unknown")

        // ไม่มี TTL — ค่าเก่าคือค่าที่ถูก ตราบใดที่ยังไม่ถึงเวลารีเซ็ต
        try Data("UTILIZATION=12\nRESETS_AT=2023-11-15T03:00:00Z\nTIMESTAMP=1\n".utf8)
            .write(to: url)
        equal(UsageReader.read(now: t0, from: url)?[0].percent, 12,
              "an ancient TIMESTAMP does not invalidate a percent")
    }

    suite("usage on the wire") {
        let snap = Snapshot(
            clock: "17:04", date: "Mon 27 Jul",
            sessions: [SessionSnap(project: "tamaclaude", state: .writing)],
            usage: [UsageSnap(percent: 35, remaining: 10_980),
                    UsageSnap(percent: 48, remaining: 111_600)])
        let data = try snap.encoded()
        let json = String(decoding: data, as: UTF8.self)
        expect(json.contains(#""u":[[35,10980],[48,111600]]"#), "encodes as bare pairs: \(json)")
        equal(try JSONDecoder().decode(Snapshot.self, from: data), snap, "round trips")

        // โควตาตกก่อน session เมื่อพื้นที่ไม่พอ — session คือเหตุผลที่จอนี้มีอยู่
        let crowded = Snapshot(
            clock: "17:04", date: "Mon 27 Jul",
            sessions: (1...4).map { SessionSnap(project: "project-name\($0)", state: .searching) },
            cards: (1...3).map {
                CardSnap(title: "title \($0)", body: "body \($0)", kind: .alert)
            },
            usage: [UsageSnap(percent: 35, remaining: 10_980),
                    UsageSnap(percent: 48, remaining: 111_600)])
        let squeezed = try JSONDecoder().decode(
            Snapshot.self, from: crowded.encoded(maxBytes: 160))
        equal(squeezed.sessions.count, 4, "sessions still survive")
        expect(squeezed.usage == nil, "usage is dropped before any session is")
    }

    suite("the menu bar badge shows the 5 hour window, or nothing at all") {
        let w = UsageReader.sessionWindow

        expect(MenuBadge.from(nil) == nil, "no usage at all means the plain icon comes back")
        expect(
            MenuBadge.from([UsageSnap(), UsageSnap(percent: 48, remaining: w)]) == nil,
            "a known weekly does not rescue an unknown session — the badge is the 5 h window")
        expect(
            MenuBadge.from([UsageSnap(percent: UsageSnap.unknown, remaining: 0)]) == nil,
            "a rolled window means unknown, never 0%")

        // ศูนย์เป็นค่าจริง: หน้าต่างเพิ่งรีเซ็ตแล้วยังไม่ได้ใช้ ต้องเห็น 0% ไม่ใช่ไอคอนเปล่า
        equal(
            MenuBadge.from([UsageSnap(percent: 0, remaining: w)]),
            MenuBadge(percent: 0, pace: 0),
            "a fresh window really is 0% with the clock at the start")

        equal(
            MenuBadge.from([UsageSnap(percent: 42, remaining: w / 2)]),
            MenuBadge(percent: 42, pace: 50),
            "42% with half the window left is on pace")
        expect(
            MenuBadge(percent: 42, pace: 50).isAlarming == false,
            "behind the clock is not a warning")
        expect(
            MenuBadge(percent: 60, pace: 50).isAlarming,
            "ahead of the clock is")
        // ขีดต้องรู้ว่าเวลาเดินไปถึงไหน ไม่ใช่แค่ว่าแซงหรือไม่แซง — สีตอบข้อหลังไปแล้ว
        equal(
            MenuBadge.from([UsageSnap(percent: 60, remaining: w / 4)])?.pace, 75,
            "the pace is where the clock is, in the same percent the bar is drawn in")
        equal(
            MenuBadge.from([UsageSnap(percent: 90, remaining: 0)])?.isAlarming, nil,
            "a rolled window is unknown even at 90% — it cannot alarm about a number it lost")
        // pace เป็นเกณฑ์เดียว — เลขสูงๆ ที่ยังตามเวลาทันไม่ใช่เรื่องต้องเตือน
        equal(
            MenuBadge.from([UsageSnap(percent: 90, remaining: w / 10)]),
            MenuBadge(percent: 90, pace: 90),
            "90% with a tenth of the window left is exactly on pace, so no colour")
        expect(
            MenuBadge(percent: 90, pace: 90).isAlarming == false, "exactly on pace is not ahead")
        equal(
            MenuBadge.from([UsageSnap(percent: 99, remaining: UsageSnap.unknown)]),
            MenuBadge(percent: 99, pace: MenuBadge.unknown),
            "no countdown means no pace to be ahead of, and no fixed threshold to trip")
        expect(
            MenuBadge(percent: 99, pace: MenuBadge.unknown).isAlarming == false,
            "an unknown pace cannot be overtaken, so it never turns red")
        // นาฬิกาสองฝั่งไม่ตรงกันทำให้ countdown ยาวเกินหน้าต่างได้ ถ้าปล่อยให้ elapsed ติดลบ
        // แม้แต่ 0% ก็จะแซง pace แล้วแถบเมนูแดงตั้งแต่หน้าต่างยังไม่เริ่ม
        equal(
            MenuBadge.from([UsageSnap(percent: 0, remaining: w * 2)]),
            MenuBadge(percent: 0, pace: 0),
            "a countdown longer than the window is clock skew, not negative elapsed time")
    }

    suite("the popover cards say what the board panel says") {
        let session = UsageReader.sessionWindow
        let weekly = UsageReader.weeklyWindow
        // 2023-11-14 22:13:20 UTC — ตรึงโซนเวลาไว้ ไม่งั้นบรรทัดเวลาขึ้นกับเครื่องที่รัน
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        expect(QuotaCard.cards(nil, now: now, calendar: utc) == nil,
               "no usage at all means no cards, not two empty ones")
        expect(QuotaCard.cards([UsageSnap(), UsageSnap()], now: now, calendar: utc) == nil,
               "two unknown windows are still nothing to show")

        let cards = QuotaCard.cards(
            [UsageSnap(percent: 42, remaining: session / 2), UsageSnap()],
            now: now, calendar: utc)
        equal(cards?.count, 2, "there are always two windows, even when one is unknown")
        equal(cards?[0].percent, 42, "the session card carries the session figure")
        equal(cards?[0].pace, 50, "half the window gone is the tick at 50")
        equal(cards?[1].percent, UsageSnap.unknown,
              "a window without a figure is unknown, never 0%")
        equal(cards?[1].level, .unknown, "and unknown has a colour of its own, not green")
        equal(cards?[1].reset, "No reset time yet", "with nothing to count down to")
        // ป้ายแทนบรรทัดคำอธิบายบนใบ weekly — ทั้งสองอย่างพร้อมกันคือการพูดซ้ำ
        expect(cards?[0].pill == nil && cards?[0].subtitle.isEmpty == false,
               "the session card explains itself in a line under its name")
        equal(cards?[1].pill, "Weekly", "the weekly card says which window in a pill instead")
        expect(cards?[1].subtitle.isEmpty == true, "and then has no line to repeat it in")

        // สามขั้นของบอร์ด — แต่ pace แซงเมื่อไรเป็นแดงทันทีแม้ยังไม่ถึง 85
        equal(QuotaCard.level(percent: 10, pace: 50), .good, "well behind the clock is fine")
        equal(QuotaCard.level(percent: 60, pace: 90), .warn, "60 is the first step up")
        equal(QuotaCard.level(percent: 85, pace: 90), .crit, "85 is the last one")
        equal(QuotaCard.level(percent: 61, pace: 60), .crit,
              "ahead of the pace is red long before 85")
        equal(QuotaCard.level(percent: 90, pace: 90), .crit,
              "exactly on pace is not ahead, but 90 trips the percent threshold anyway")
        equal(QuotaCard.level(percent: 61, pace: UsageSnap.unknown), .warn,
              "no pace to overtake leaves only the percent steps")
        equal(QuotaCard.level(percent: UsageSnap.unknown, pace: 50), .unknown,
              "an unknown figure has no level to be at")

        // สัมพัทธ์ตอบ "อีกนานไหม" สัมบูรณ์ตอบ "ตอนนั้นคือเมื่อไรของวัน"
        equal(QuotaCard.resetLine(remaining: 8640, now: now, calendar: utc),
              "Resets in 2h 24m (Tomorrow 00:37)",
              "both readings on one line, and midnight is tomorrow")
        equal(QuotaCard.resetLine(remaining: 2700, now: now, calendar: utc),
              "Resets in 45m (Today 22:58)", "under an hour drops the hours")
        equal(QuotaCard.resetLine(remaining: 30, now: now, calendar: utc),
              "Resets in 1m (Today 22:13)", "under a minute rounds up — 0m reads as over")
        // ชื่อวันภายในหนึ่งสัปดาห์กำกวมพอๆ กับไม่มี — "Fri" ไหน ศุกร์นี้หรือศุกร์หน้า
        equal(QuotaCard.resetLine(remaining: 3 * 86_400, now: now, calendar: utc),
              "Resets in 3d 0h (Nov 17, 22:13)",
              "a weekly reset days out needs a date, not just a clock time")
        equal(QuotaCard.resetLine(remaining: 0, now: now, calendar: utc), "Resetting now",
              "a countdown at zero is a rolled window, not a reset in zero minutes")
        equal(
            QuotaCard.resetLine(remaining: UsageSnap.unknown, now: now, calendar: utc),
            "No reset time yet", "no countdown is its own sentence")

        // การ์ด weekly ใช้ความยาวหน้าต่างของตัวเอง — pace ที่คิดด้วยหน้าต่าง 5 ชม.
        // จะเต็ม 100 ตลอดเวลาแล้วทุกอย่างเป็นสีแดง
        let fresh = QuotaCard.cards(
            [UsageSnap(), UsageSnap(percent: 20, remaining: weekly * 3 / 4)],
            now: now, calendar: utc)
        equal(fresh?[1].pace, 25, "a quarter into the week is a tick at 25")
        equal(fresh?[1].level, .good, "20% a quarter of the way in is behind the clock")
    }

    suite("statusline script never breaks the user's own statusline") {
        let script = StatuslineInstaller.script(
            binary: "/Applications/TamaClaude.app/Contents/MacOS/tamaclaude",
            delegateTo: "bash /Users/x/.claude/statusline-command.sh")
        expect(script.contains("exit 0"), "always exits clean")
        expect(script.contains("|| true"), "a failing delegate cannot take the line down")
        expect(script.contains("--usage-cache"), "captures rate_limits on the way through")
        expect(script.contains("2>/dev/null"), "our own noise never reaches the status line")

        // พาธที่มีเครื่องหมายคำพูดต้องไม่หลุดออกจาก quote แล้วกลายเป็นคำสั่ง
        let nasty = StatuslineInstaller.script(binary: "/tmp/it's here/bin", delegateTo: nil)
        expect(nasty.contains(#"BIN='/tmp/it'\''s here/bin'"#), "single quotes are escaped")
        expect(nasty.contains("PREV=''"), "no previous command is an empty PREV")

        // ติดตั้งซ้ำต้องอ่านคำสั่งเดิมกลับจากสคริปต์ที่ตัวเองเขียนไว้ได้
        // ไม่งั้นการอัปเกรดจะลบ statusline ของผู้ใช้ทิ้งเงียบๆ
        let quoted = StatuslineInstaller.script(
            binary: "/bin/tc", delegateTo: "bash '/Users/x/my statusline.sh'")
        expect(quoted.contains(#"PREV='bash '\''/Users/x/my statusline.sh'\'''"#),
               "quotes inside the delegated command survive: \(quoted.split(separator: "\n")[8])")
    }

    suite("state enum is the contract with the firmware") {
        // ต้องตรงกับ STATES ใน tools/gen/mascot.py
        let expected: Set<String> = [
            "idle", "reading", "writing", "building", "searching", "thinking",
            "waiting", "sleeping", "alert", "celebrate", "error", "entering", "leaving",
            "conducting", "beacon",
        ]
        equal(Set(VisualState.allCases.map(\.rawValue)), expected, "no state drifted")
    }

    suite("the foot of the popover says what the menu used to say") {
        equal(PanelText.board(connected: true), "Board connected", "connected reads plainly")
        equal(
            PanelText.board(connected: false), "Looking for the board\u{2026}",
            "not connected is a search in progress, not a failure")

        equal(
            PanelText.sessions(Snapshot(clock: "10:00", date: "1 Jan")), ["No sessions"],
            "an empty snapshot still says something")

        let one = Snapshot(
            clock: "10:00", date: "1 Jan",
            sessions: [SessionSnap(project: "tamaclaude", state: .writing)])
        equal(
            PanelText.sessions(one), ["tamaclaude \u{00B7} writing"],
            "a session is its project and its state")

        let many = Snapshot(
            clock: "10:00", date: "1 Jan", overflow: 2,
            sessions: [
                SessionSnap(project: "p1", state: .writing),
                SessionSnap(project: "p2", state: .thinking),
            ])
        equal(
            PanelText.sessions(many),
            ["p1 \u{00B7} writing", "p2 \u{00B7} thinking", "+2 more"],
            "sessions past the slot count are counted on a row of their own")
        // แถวนี้ต้องมาท้ายสุดเสมอ ไม่งั้น `+N more` อ่านเหมือนอธิบายแถวที่อยู่ใต้มัน
        equal(
            PanelText.sessions(many).last, "+2 more", "the count is the last row, never the first")
    }

    suite("the app writes the key file so the user never has to chmod it") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keywrite-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("nested").appendingPathComponent("session-key")

        func mode(_ url: URL) throws -> Int {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return ((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777
        }

        // ไดเรกทอรียังไม่มีตอนเขียนครั้งแรกได้ — แอปที่เพิ่งติดตั้งยังไม่เคยสร้างอะไรเลย
        try SessionKeyFile.write("  sk-fresh\n", to: url)
        equal(try mode(url), 0o600, "the file is readable only by its owner from the start")
        equal(try UsagePoll.readKey(at: url), "sk-fresh",
              "and reads back through the same rules that guard it, trimmed")

        // ไฟล์ที่ผู้ใช้เคยสร้างเองแบบ 644 ต้องกลายเป็น 600 หลังเขียนทับ ไม่ใช่คงสิทธิ์เดิมไว้
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        try SessionKeyFile.write("sk-second", to: url)
        equal(try mode(url), 0o600, "overwriting a loose file tightens it")
        equal(try UsagePoll.readKey(at: url), "sk-second", "and the new key is the one on disk")

        do {
            try SessionKeyFile.write("   \n", to: url)
            expect(false, "an empty key must be refused, not written")
        } catch let failure as UsagePoll.Failure {
            equal(failure.code, UsagePoll.Failure.unusableKeyFile, "refused as an unusable key")
            expect(!failure.message.contains("sk-second"), "and no message ever carries a key")
        }
        equal(try UsagePoll.readKey(at: url), "sk-second", "a refused write leaves the old key")

        expect(SessionKeyFile.isUsable(at: url), "a written key is usable")
        expect(!SessionKeyFile.isUsable(at: dir.appendingPathComponent("nothing")),
               "a missing file is not")
    }

    suite("the org list and the status travel on stdout, not in a second state file") {
        let report = UsagePoll.Report(
            orgs: [UsagePoll.Org(id: "abc-123", name: "Personal"),
                   UsagePoll.Org(id: "def-456", name: "Acme Corp")],
            summary: "session 42% \u{00B7} weekly 7%")
        let parsed = PollOutput.parse(PollOutput.render(report))
        equal(parsed.orgs, report.orgs, "a rendered report parses back to the same orgs")
        equal(parsed.summary, report.summary, "and to the same status line")

        // ชื่อ org มีช่องว่างได้ ส่วน id ไม่มี — ตัดที่ช่องว่างแรกเท่านั้น
        equal(PollOutput.parse("org abc-123 Acme Corp Ltd").orgs,
              [UsagePoll.Org(id: "abc-123", name: "Acme Corp Ltd")], "only the first space splits")
        equal(PollOutput.parse("org abc-123").orgs,
              [UsagePoll.Org(id: "abc-123", name: "abc-123")], "a nameless org shows its id")

        // id ที่เปลี่ยน path ได้ ตายตรงนี้เหมือนตอนมาจากเน็ต — ทางเดินของมันจบที่ URL เหมือนกัน
        equal(PollOutput.parse("org ../../admin Evil\norg ok-1 Fine").orgs,
              [UsagePoll.Org(id: "ok-1", name: "Fine")], "an id that could change the path is dropped")

        equal(PollOutput.parse("").summary, nil, "silence is not a status")
        equal(PollOutput.parse("org a-1 One\nkey expired").summary, "key expired",
              "the status is the line that is not an org")
    }

    suite("one org is silent, several are a choice") {
        let orgs = [UsagePoll.Org(id: "one", name: "One"), UsagePoll.Org(id: "two", name: "Two")]
        equal(UsagePoll.pick(orgs, preferred: nil)?.id, "one", "no choice yet means the first")
        equal(UsagePoll.pick(orgs, preferred: "two")?.id, "two", "the chosen one wins")
        // ตัวที่เลือกไว้แล้วหายไปจากบัญชี ต้องไม่ทำให้ทั้งเรื่องหยุด — ยิงตัวแรกไปก่อน
        equal(UsagePoll.pick(orgs, preferred: "gone")?.id, "one",
              "a stale choice falls back instead of polling an org that is not there")
        expect(UsagePoll.pick([], preferred: "one") == nil, "no orgs, nothing to pick")

        equal(UsagePoll.organizations(from: Data(#"[{"uuid":"u1","name":"Personal"},{"id":"u2"}]"#.utf8)),
              [UsagePoll.Org(id: "u1", name: "Personal"), UsagePoll.Org(id: "u2", name: "u2")],
              "uuid wins, id is the fallback, and a nameless org is named by its id")
        equal(UsagePoll.organizations(from: Data(#"[{"uuid":"../x"},{"uuid":"ok"}]"#.utf8)),
              [UsagePoll.Org(id: "ok", name: "ok")],
              "one unusable org does not take the usable ones with it")
        equal(UsagePoll.organizations(from: Data("not json".utf8)), [], "junk is an empty list")
    }

    suite("the refresh interval is a choice the app remembers, and 30s is not one of them") {
        equal(PollInterval.stored(nil), .minute, "never chosen means 60s, not Off")
        equal(PollInterval.stored(30), .minute, "30s is not on the menu; fall back")
        equal(PollInterval.stored(0), .off, "Off is a real choice and must survive a restart")
        equal(PollInterval.stored(300), .fiveMinutes, "5 min round trips")
        equal(PollInterval.allCases.map(\.title), ["Off", "60s", "5 min"], "three choices, in order")
    }

    suite("the timer spawns one child per round and stops when the key is rejected") {
        final class Fake {
            var launches: [String?] = []
            var kills = 0
            var done: ((UsagePoller.Outcome) -> Void)?
            var hasKey = true

            func launcher() -> UsagePoller.Launcher {
                { [self] orgID, done in
                    launches.append(orgID)
                    self.done = done
                    return { [self] in kills += 1 }
                }
            }

            func finish(_ code: Int32, _ output: String = "") {
                let done = self.done
                self.done = nil
                done?(UsagePoller.Outcome(code: code, output: output))
            }
        }

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

        let fake = Fake()
        let poller = UsagePoller(
            interval: .minute, hasKey: { fake.hasKey }, launch: fake.launcher())

        poller.tick(now: t0)
        equal(fake.launches.count, 1, "the first tick polls — figures at launch, not in a minute")
        poller.tick(now: at(1))
        equal(fake.launches.count, 1, "a child that is still running is not joined by another")
        fake.finish(0, "org o-1 One\nsession 5%")
        equal(poller.status, "session 5%", "the summary is what the child said last")
        equal(poller.orgs, [UsagePoll.Org(id: "o-1", name: "One")], "and the org list came with it")

        poller.tick(now: at(30))
        equal(fake.launches.count, 1, "half a minute is not a minute")
        poller.tick(now: at(60))
        equal(fake.launches.count, 2, "a full round spawns exactly one child")

        // 5xx เน็ตหลุด — รอบหน้าก็หายเอง ไม่มีอะไรให้ผู้ใช้ทำ จึงต้องไม่หยุดยิง
        fake.finish(1, "claude.ai returned HTTP 503")
        expect(poller.blocked == nil, "a server-side error is not the user's problem")
        poller.tick(now: at(120))
        equal(fake.launches.count, 3, "so the next round still goes out")

        // 401/403 — ยิงต่อไปก็ได้ 401 เหมือนเดิมทุกนาที จนกว่าจะมีคนแปะ key ใหม่
        fake.finish(UsagePoll.Failure.rejectedKey, "claude.ai rejected the session key")
        equal(poller.blocked, .expiredKey, "a rejected key is a blocked pipe")
        poller.tick(now: at(180))
        poller.pollNow(now: at(181))
        equal(fake.launches.count, 3, "and nothing goes out while it is blocked")

        poller.keyWasSet(now: at(200))
        expect(poller.blocked == nil, "a fresh key unblocks")
        equal(fake.launches.count, 4, "and polls at once rather than waiting out the round")

        // ลูกที่ไม่จบใน 30 วินาทีถูกฆ่า ไม่งั้นลูกที่ค้างจะกองกันทุกนาที
        poller.tick(now: at(229))
        equal(fake.kills, 0, "under the timeout the child is left alone")
        poller.tick(now: at(231))
        equal(fake.kills, 1, "past it the child is killed")
        expect(!poller.isRunning, "and the slot is free again")
        // ลูกที่ถูกฆ่าแล้วยังพูดทีหลังได้ — เสียงจากอดีตต้องไม่ทับสถานะปัจจุบัน
        fake.finish(UsagePoll.Failure.rejectedKey, "too late")
        expect(poller.blocked == nil, "a killed child cannot block the poller from its grave")

        poller.tick(now: at(300))
        equal(fake.launches.count, 5, "and the next round runs as usual")

        // ไฟล์ key ที่ใช้ไม่ได้เป็นป้ายบอกอาการ ไม่ใช่ล็อก — ตัวที่กันไม่ให้ยิงคือไฟล์เอง
        // ผู้ใช้ที่ `chmod 600` เองข้างนอกจึงกลับมายิงได้โดยไม่ต้องเปิดปิดแอปหรือแปะ key ซ้ำ
        fake.hasKey = false
        fake.finish(UsagePoll.Failure.unusableKeyFile, "session-key is readable by other users")
        equal(poller.blocked, .unusableKeyFile, "the panel says what is wrong with the file")
        poller.tick(now: at(360))
        equal(fake.launches.count, 5, "and nothing is spawned while the file is unusable")
        fake.hasKey = true
        poller.tick(now: at(420))
        equal(fake.launches.count, 6, "a file fixed from outside resumes the rounds by itself")
        fake.finish(1, "claude.ai returned HTTP 503")
        expect(poller.blocked == nil, "and getting past the file clears the label")

        // Off แปลว่าไม่ยิงเลย ไม่ใช่ยิงช้าลง
        poller.interval = .off
        poller.tick(now: at(600))
        poller.pollNow(now: at(601))
        equal(fake.launches.count, 6, "Off does not poll, not even when asked directly")

        // ไม่มี key ก็ไม่ต้องเผาโปรเซสทุกนาทีเพื่อให้ได้ error เดิม
        poller.interval = .minute
        fake.hasKey = false
        poller.tick(now: at(700))
        equal(fake.launches.count, 6, "no key, no child")
        fake.hasKey = true
        poller.tick(now: at(800))
        equal(fake.launches.count, 7, "a key that appears is picked up on the next round")

        // ปิดแอป → ไม่มีลูกเหลือค้าง
        poller.stop()
        equal(fake.kills, 2, "quitting kills the child rather than orphaning it")

        // org ที่ยิงจริงเดินทางไปกับลูก ส่วน key ไม่เคยเดินทางแบบนั้น · ตัวที่เลือกไว้แล้ว
        // หายไปจากบัญชีถอยเป็นตัวแรกตรงนี้ ไม่ใช่ในลูก — ลูกได้ id มาก็ต้องเชื่อ
        poller.preferredOrg = "o-2"
        poller.pollNow(now: at(900))
        equal(fake.launches.last, "o-1",
              "a choice that is not in the list we know falls back to the first")
        fake.finish(0, "org o-1 One\norg o-2 Two\nsession 8%")
        poller.pollNow(now: at(960))
        equal(fake.launches.last, "o-2", "once the list has it, the choice rides along")
        fake.finish(0, "org o-1 One\nsession 9%")
        poller.pollNow(now: at(1020))
        equal(fake.launches.last, "o-1",
              "and an org that vanishes from the account falls back rather than 404 forever")
    }

    suite("the child is a real process: stdout comes back, and killing it kills it") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spawn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func script(_ body: String) throws -> URL {
            let url = dir.appendingPathComponent("fake-\(UUID().uuidString).sh")
            try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        }

        /// callback ของ launcher มาถึงทาง main queue — เทสต์ต้องหมุน run loop ให้มันวิ่ง
        func wait(_ done: () -> Bool, _ seconds: TimeInterval = 5) -> Bool {
            let deadline = Date() + seconds
            while Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                if done() { return true }
            }
            return done()
        }

        final class Result: @unchecked Sendable {
            var outcome: UsagePoller.Outcome?
        }

        // key ไม่เคยผ่าน env — org id ผ่านได้ ไม่ใช่ความลับ · exit code เดินทางกลับมาครบ
        let talker = try script(
            #"echo "org $TAMACLAUDE_ORG_ID Acme Corp"; echo "key expired"; exit 2"#)
        let spoke = Result()
        _ = PollProcess.launcher(talker)("o-9") { spoke.outcome = $0 }
        expect(wait { spoke.outcome != nil }, "the child's exit is reported back")
        equal(spoke.outcome?.code, UsagePoll.Failure.rejectedKey, "with its exit code intact")
        let parsed = PollOutput.parse(spoke.outcome?.output ?? "")
        equal(parsed.orgs, [UsagePoll.Org(id: "o-9", name: "Acme Corp")],
              "the org id rode along in the environment and came back on stdout")
        equal(parsed.summary, "key expired", "and so did the status line")

        // ลูกที่ค้างต้องตายจริงตอนถูกฆ่า ไม่ใช่แค่ถูกลืม
        let sleeper = try script("sleep 60")
        let killed = Result()
        let kill = PollProcess.launcher(sleeper)(nil) { killed.outcome = $0 }
        expect(!wait({ killed.outcome != nil }, 0.3), "it is still running before we ask")
        kill()
        expect(wait { killed.outcome != nil }, "a killed child stops, and says it stopped")
        expect((killed.outcome?.code ?? 0) != 0, "a killed child never looks like a success")
    }

    suite("the app opens a window of its own, once, and never in a loop") {
        final class Fake {
            var launches = 0
            var kills = 0
            var done: ((SessionOutcome) -> Void)?

            func launcher() -> SessionStarter.Launcher {
                { [self] done in
                    launches += 1
                    self.done = done
                    return { [self] in kills += 1 }
                }
            }

            func finish(_ outcome: SessionOutcome = .ok) {
                let done = self.done
                self.done = nil
                done?(outcome)
            }
        }

        let w = UsageReader.sessionWindow
        let open = [UsageSnap(percent: 12, remaining: w / 2)]
        // หน้าต่างหมดอายุ = countdown ถึงศูนย์ ซึ่งแบดจ์อ่านว่า "ไม่มีอะไรจะบอก"
        let gone = [UsageSnap(percent: UsageSnap.unknown, remaining: 0)]

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

        let fake = Fake()
        let starter = SessionStarter(enabled: false, launch: fake.launcher())

        starter.tick(now: t0, usage: gone)
        equal(fake.launches, 0, "the switch is off by default, and off spends nothing")

        starter.enabled = true
        starter.tick(now: at(1), usage: open)
        equal(fake.launches, 0, "a window that is already open needs no help")

        starter.tick(now: at(2), usage: gone)
        equal(fake.launches, 1, "no window and the switch on starts exactly one session")
        starter.tick(now: at(3), usage: gone)
        equal(fake.launches, 1, "a child that is still running is not joined by another")

        fake.finish(.ok)
        starter.tick(now: at(4), usage: gone)
        equal(fake.launches, 1, "the cooldown starts when the child ends, not when it began")
        starter.tick(now: at(304), usage: gone)
        equal(fake.launches, 1,
              "and the cooldown running out is not permission: this window already had its turn")

        starter.tick(now: at(400), usage: open)
        equal(fake.launches, 1, "a window that appears is not itself a reason to start anything")
        starter.tick(now: at(401), usage: gone)
        equal(fake.launches, 2, "but once that window has gone, the next one may be opened")

        // การเย็นตัวกันการยิงรัวในช่วงที่หน้าต่างใหม่ยังไม่ปรากฏในตัวเลข
        fake.finish(.failed)
        starter.tick(now: at(402), usage: gone)
        starter.tick(now: at(403), usage: open)
        starter.tick(now: at(404), usage: gone)
        equal(fake.launches, 2, "five minutes must pass after a child ends, armed or not")
        starter.tick(now: at(702), usage: gone)
        equal(fake.launches, 3, "and then it may go again")

        // ลูกที่ค้างต้องไม่กินช่องเดียวที่มีอยู่ไว้ตลอดกาล
        starter.tick(now: at(731), usage: gone)
        equal(fake.kills, 0, "under the timeout the child is left alone")
        starter.tick(now: at(733), usage: gone)
        equal(fake.kills, 1, "past it the child is killed")
        expect(!starter.isRunning, "and the slot is free again")
        fake.finish(.ok)  // เสียงจากอดีตต้องไม่ทำให้รอบถัดไปค้าง

        starter.tick(now: at(800), usage: open)
        starter.tick(now: at(1034), usage: gone)
        equal(fake.launches, 4, "a killed child does not wedge the round after it")

        // ปิดแอป → ไม่มีลูกเหลือค้าง
        starter.stop()
        equal(fake.kills, 2, "quitting kills the child rather than orphaning it")

        starter.enabled = false
        starter.tick(now: at(1100), usage: open)
        starter.tick(now: at(1500), usage: gone)
        equal(fake.launches, 4, "a switch turned off stops the feature dead, figures or not")

        // หน้าต่างที่ลูกของเราเองเป็นคนเปิดโผล่ในตัวเลขได้ตั้งแต่ลูกยังไม่ตาย ถ้าสถานะหยุดเดิน
        // ระหว่างที่มีลูกวิ่งอยู่ หน้าต่างนั้นจะผ่านไปโดยไม่มีใครเห็น แล้วสวิตช์จะตายถาวร
        let live = Fake()
        let watcher = SessionStarter(enabled: true, launch: live.launcher())
        watcher.tick(now: t0, usage: gone)
        equal(live.launches, 1, "one session goes out")
        watcher.tick(now: at(10), usage: open)
        watcher.tick(now: at(20), usage: gone)
        live.finish(.ok)
        watcher.tick(now: at(30), usage: gone)
        equal(live.launches, 1, "the cooldown still has to run out")
        watcher.tick(now: at(330), usage: gone)
        equal(live.launches, 2,
              "a window that came and went while the child was alive was still seen")

        // ยังไม่เคยมี cache เลยก็คือไม่มีหน้าต่าง — กฎนั้นเป็นของ `MenuBadge` ตัวเดียว
        let cold = Fake()
        let fresh = SessionStarter(enabled: true, launch: cold.launcher())
        fresh.tick(now: t0, usage: nil)
        equal(cold.launches, 1, "no figures at all is no window, not an unknown to wait out")
    }

    suite("a ticked switch that starts nothing has to say why") {
        final class Fake {
            var launches = 0
            var done: ((SessionOutcome) -> Void)?

            func launcher() -> SessionStarter.Launcher {
                { [self] done in
                    launches += 1
                    self.done = done
                    return {}
                }
            }

            func finish(_ outcome: SessionOutcome) {
                let done = self.done
                self.done = nil
                done?(outcome)
            }
        }

        let gone = [UsageSnap(percent: UsageSnap.unknown, remaining: 0)]
        let open = [UsageSnap(percent: 12, remaining: UsageReader.sessionWindow / 2)]
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

        // หา binary ไม่เจอ = ไม่มีอะไรถูกยิงเลย และไม่มีวันถูกยิงอีกจนกว่าคนจะลงมือ
        let absent = Fake()
        let lost = SessionStarter(enabled: true, launch: absent.launcher())
        lost.tick(now: t0, usage: gone)
        absent.finish(.noBinary(["/opt/homebrew/bin/claude"]))
        equal(lost.blocked, .noBinary(["/opt/homebrew/bin/claude"]),
              "a missing binary is a reason the user can act on, and it says where we looked")
        lost.tick(now: at(1), usage: gone)
        lost.tick(now: at(400), usage: gone)
        lost.tick(now: at(500), usage: open)
        lost.tick(now: at(900), usage: gone)
        equal(absent.launches, 1,
              "and nothing else goes out, not after the cooldown and not after a whole window")

        // ปิดแล้วเปิดใหม่คือคำสั่ง "ฉันแก้แล้ว ลองอีกที" — ต้องยิงได้ทันที ไม่ใช่รออีกห้านาที
        lost.enabled = false
        lost.enabled = true
        expect(lost.blocked == nil, "turning the switch on again clears the lock")
        lost.tick(now: at(901), usage: gone)
        equal(absent.launches, 2, "and the next tick starts a session, cooldown and all")

        // ยังไม่ได้ login = ยิงอีกกี่รอบก็จบแบบเดิม
        let anon = Fake()
        let out = SessionStarter(enabled: true, launch: anon.launcher())
        out.tick(now: t0, usage: gone)
        anon.finish(.authFailed)
        equal(out.blocked, .notLoggedIn, "a child that ended without a login locks too")
        out.tick(now: at(400), usage: gone)
        equal(anon.launches, 1, "and stays locked")

        // เน็ตสะดุด/timeout/แยกไม่ออก = ไม่ล็อก รอบหน้าที่ครบเงื่อนไขยิงตามปกติ
        let flaky = Fake()
        let patient = SessionStarter(enabled: true, launch: flaky.launcher())
        patient.tick(now: t0, usage: gone)
        flaky.finish(.failed)
        expect(patient.blocked == nil, "a failure we cannot explain is not a reason to stop")
        // tick ถัดไปเป็นคนประทับเวลาที่ลูกจบ การเย็นตัวจึงนับจากตรงนั้น ไม่ใช่จาก t0
        patient.tick(now: at(1), usage: gone)
        patient.tick(now: at(302), usage: gone)
        equal(flaky.launches, 2, "the next round that meets the conditions goes out as usual")

        // สวิตช์ที่ปิดอยู่แล้วถูกสั่งปิดซ้ำไม่ใช่การปลดล็อก
        flaky.finish(.authFailed)
        patient.enabled = true
        equal(patient.blocked, .notLoggedIn,
              "setting the switch to what it already was is not the user acting")

        // exit code บอกแค่ว่าไม่สำเร็จ — สิ่งที่แยกชนิดได้คือสิ่งที่ลูกพูดตอนตาย
        equal(SessionProcess.classify(code: 0, output: ""), .ok, "code zero is a session")
        equal(SessionProcess.classify(code: 1, output: "Invalid API key · Please run /login"),
              .authFailed, "the login line is the one thing worth locking on")
        equal(SessionProcess.classify(code: 1, output: "fetch failed: network is unreachable"),
              .failed, "anything else is this round's bad luck")
        equal(SessionProcess.classify(code: 143, output: ""), .failed,
              "a child we killed ourselves has nothing to confess")

        // ผู้ใช้ที่ติดตั้งไว้ที่แปลกๆ ชี้เองได้ และค่าที่ชี้ *แทนที่* รายการ ไม่ใช่ถูกเติมท้าย
        let searched = ClaudeBinary.candidates(override: "/somewhere/odd/claude")
        equal(searched.map(\.path), ["/somewhere/odd/claude"],
              "a path the user set is the only place we look")
        expect(ClaudeBinary.candidates(override: nil).count > 1,
               "without one we walk the known places")

        // คีย์ที่ไม่มี UI ต้องมีเทสต์ ไม่งั้นชื่อคีย์ที่พิมพ์ผิดจะไม่มีอะไรจับได้เลย
        let defaults = UserDefaults(suiteName: "tamatest.claudePath")!
        defaults.removePersistentDomain(forName: "tamatest.claudePath")
        expect(ClaudeBinary.override(defaults) == nil, "an unset key is no override")
        defaults.set("   ", forKey: ClaudeBinary.overrideKey)
        expect(ClaudeBinary.override(defaults) == nil,
               "and neither is a key holding nothing but space")
        defaults.set("  /odd/claude \n", forKey: ClaudeBinary.overrideKey)
        equal(ClaudeBinary.override(defaults), "/odd/claude",
              "a path pasted with whitespace around it is still that path")
        defaults.removePersistentDomain(forName: "tamatest.claudePath")
        equal(ClaudeBinary.locate(searched), .missing(["/somewhere/odd/claude"]),
              "and a place with nothing in it comes back naming itself")

        // บรรทัดในแผงมีเฉพาะตอนล็อก และ path ที่ค้นมาอยู่ใน tooltip ไม่ใช่ในบรรทัด
        expect(PanelText.startProblem(nil) == nil, "nothing to say when it can start")
        expect(PanelText.startProblemDetail(nil) == nil, "and nothing to hover over either")
        expect(PanelText.startProblem(.notLoggedIn)?.contains("logged in") == true,
               "a login that never happened says so")
        let missing = StartBlock.noBinary(["/a/claude", "/b/claude"])
        expect(PanelText.startProblem(missing)?.contains("/a/claude") != true,
               "the line itself stays one line wide")
        expect(PanelText.startProblemDetail(missing)?.contains("/b/claude") == true,
               "while the places we looked are a hover away")
    }

    suite("a broken pipe and a stale figure are two different sentences") {
        expect(PanelText.keyProblem(nil) == nil, "nothing to say when the pipe is fine")
        expect(PanelText.keyProblem(.expiredKey)?.contains("expired") == true,
               "an expired key says so")
        expect(PanelText.keyProblem(.unusableKeyFile)?.contains("unusable") == true,
               "an unusable key file is its own sentence")

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        equal(PanelText.updated(stamp: nil, now: now), "No quota figures yet",
              "never having figures is an age too")
        // วินาทีมีความหมายที่นี่ที่เดียวในแอป — ทั้งฟีเจอร์เกิดจาก "เลขนี้ค้างหรือเปล่า"
        equal(PanelText.updated(stamp: now.addingTimeInterval(-12), now: now),
              "Updated 12s ago", "seconds answer the question the whole panel exists for")
        equal(PanelText.updated(stamp: now.addingTimeInterval(-600), now: now),
              "Updated 10m ago", "minutes past the minute")
        equal(PanelText.updated(stamp: now.addingTimeInterval(-7200), now: now),
              "Updated 2h ago", "hours past the hour")
        equal(PanelText.updated(stamp: now.addingTimeInterval(-3 * 86400), now: now),
              "Updated 3d ago", "days past two days")
        // นาฬิกาเครื่องเดินถอยหลังได้ (sleep, NTP) — อายุติดลบต้องไม่กลายเป็นข้อความประหลาด
        equal(PanelText.updated(stamp: now.addingTimeInterval(120), now: now),
              "Updated 0s ago", "a stamp from the future is not a negative age")
    }

    suite("the head of the popover names the org the figures came from") {
        let orgs = [UsagePoll.Org(id: "o-1", name: "Personal"),
                    UsagePoll.Org(id: "o-2", name: "Acme Corp")]
        equal(PanelText.heading(orgs: orgs, current: "o-2", hasKey: true), "Acme Corp",
              "the org being polled is what the head says")
        // ยังไม่ได้ตั้ง key = ยังไม่เคยถามใครว่ามี org อะไรบ้าง ชื่อแอปจึงจริงกว่าชื่อ org
        equal(PanelText.heading(orgs: orgs, current: "o-2", hasKey: false), "TamaClaude",
              "no key means no org to speak of, whatever is left in the list")
        equal(PanelText.heading(orgs: [], current: nil, hasKey: true), "TamaClaude",
              "before the first round comes back there is still nothing to name")
        // ตัวที่เลือกไว้แล้วหายไปจากบัญชีถูกถอยเป็นตัวแรกโดย `currentOrg` ก่อนถึงตรงนี้แล้ว
        // ที่นี่จึงเจอ id ที่ไม่มีในรายการได้เฉพาะตอนรายการยังไม่มา
        equal(PanelText.heading(orgs: orgs, current: "gone", hasKey: true), "TamaClaude",
              "an id we cannot name is not a name")

        expect(!PanelText.canSwitchOrg(orgs: [orgs[0]], hasKey: true), "one org is not a choice")
        expect(PanelText.canSwitchOrg(orgs: orgs, hasKey: true), "two are")
        // หัวแผงที่พูดว่ายังไม่มี org พร้อมลูกศรที่กางรายการ org ได้ คือสองประโยคที่ขัดกันเอง
        expect(!PanelText.canSwitchOrg(orgs: orgs, hasKey: false),
               "a list left over from the last key is not a choice either")
    }

    suite("the refresh button is the way out, not the way of life") {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func at(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }

        let ready = RefreshControl.state(running: false, hasKey: true, finished: nil, now: now)
        expect(ready.enabled, "with nothing in the way the button is a button")
        expect(!ready.spinning, "and it is not pretending to work")

        let busy = RefreshControl.state(running: true, hasKey: true, finished: nil, now: now)
        expect(!busy.enabled, "a round already in flight cannot be asked for twice")
        expect(busy.spinning, "and the panel says so while it is in flight")

        // เย็นตัว 10 วินาที — endpoint นี้ไม่มีเอกสาร ปุ่มที่กดรัวได้ทำลายเหตุผลที่เราตัด
        // ตัวเลือก 30 วินาทีทิ้งไปทั้งหมด
        let cooling = RefreshControl.state(
            running: false, hasKey: true, finished: now, now: at(4))
        expect(!cooling.enabled, "straight after a round it stays down")
        expect(!cooling.spinning, "cooling down is not the same picture as working")
        expect(cooling.tooltip.contains("6s"), "and it says how long: \(cooling.tooltip)")
        expect(RefreshControl.state(running: false, hasKey: true, finished: now, now: at(10))
                .enabled, "ten seconds later it is a button again")
        // นาฬิกาเครื่องเดินถอยหลังได้ (sleep, NTP) — ต้องไม่กลายเป็นการเย็นตัวชั่วนิรันดร์
        expect(!RefreshControl.state(running: false, hasKey: true, finished: at(60), now: now)
                .enabled, "a finish stamped in the future still cools down")
        expect(RefreshControl.state(running: false, hasKey: true, finished: at(60), now: at(70))
                .enabled, "but only for the ten seconds it is owed")

        expect(!RefreshControl.state(running: false, hasKey: false, finished: nil, now: now)
                .enabled, "with no key there is nothing the button could ask for")

        // เปิดแผงคือสัญญาณความตั้งใจที่ชัดพอจะยิงเอง — แต่เฉพาะตอนค่าที่มีเก่ากว่ารอบที่ตั้งไว้
        expect(RefreshControl.wantsPoll(interval: .minute, stamp: nil, now: now),
               "no figures at all is as stale as it gets")
        expect(!RefreshControl.wantsPoll(interval: .minute, stamp: at(-30), now: now),
               "a figure younger than the round is what the round would have fetched anyway")
        expect(RefreshControl.wantsPoll(interval: .minute, stamp: at(-90), now: now),
               "past the round, opening the panel fetches")
        expect(!RefreshControl.wantsPoll(interval: .fiveMinutes, stamp: at(-90), now: now),
               "the same figure is fresh when the round the user chose is longer")
        // `Off` คือคำสั่งว่าอย่ายิงเอง — การเปิดแผงยังเป็นการยิงเอง ปุ่มต่างหากที่ไม่ใช่
        expect(!RefreshControl.wantsPoll(interval: .off, stamp: nil, now: now),
               "Off means the app never polls on its own, opening the panel included")

        // รอบที่ล้มเหลวไม่เคยขยับ `stamp` — ถ้าดูแต่ `stamp` การเปิดปิดแผงตอนเน็ตล่มจะยิง
        // ลูกทุกครั้งที่ชำเลืองดู ซึ่งถี่กว่ารอบที่ผู้ใช้ตั้งไว้ ทั้งที่เขาไม่ได้ขออะไรเลย
        expect(!RefreshControl.wantsPoll(
                interval: .minute, stamp: nil, polled: at(-20), now: now),
               "a round that went out twenty seconds ago is the round this open would fire")
        expect(RefreshControl.wantsPoll(
                interval: .minute, stamp: nil, polled: at(-90), now: now),
               "past the round it fires again, whether or not the last one came back")
    }

    suite("a hand on the button beats Off and beats a key that is spent") {
        final class Fake {
            var launches = 0
            var done: ((UsagePoller.Outcome) -> Void)?
            var hasKey = true

            func launcher() -> UsagePoller.Launcher {
                { [self] _, done in
                    launches += 1
                    self.done = done
                    return {}
                }
            }

            func finish(_ code: Int32, _ output: String = "") {
                let done = self.done
                self.done = nil
                done?(UsagePoller.Outcome(code: code, output: output))
            }
        }

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

        let fake = Fake()
        let poller = UsagePoller(interval: .off, hasKey: { fake.hasKey }, launch: fake.launcher())

        // การหยุด polling ไม่ได้แปลว่าห้ามดูค่าใหม่
        poller.refreshNow(now: t0)
        equal(fake.launches, 1, "Off stops the rounds, it does not take the button away")
        poller.refreshNow(now: at(1))
        equal(fake.launches, 1, "but a round in flight is still one round at a time")

        fake.finish(UsagePoll.Failure.rejectedKey, "claude.ai rejected the session key")
        equal(poller.blocked, .expiredKey, "a rejected key still blocks the rounds")
        poller.pollNow(now: at(2))
        equal(fake.launches, 1, "so nothing goes out by itself")
        // ผู้ใช้อาจเพิ่งไปเอา key ใหม่มาแปะข้างนอก การกดปุ่มคือวิธีถามว่า "ได้หรือยัง"
        poller.refreshNow(now: at(3))
        equal(fake.launches, 2, "the button asks anyway — the key may have been replaced")
        fake.finish(UsagePoll.Failure.rejectedKey, "claude.ai rejected the session key")
        equal(poller.blocked, .expiredKey, "and if it was not, the answer is the same as before")

        // ไม่มีไฟล์ key = ไม่มีอะไรให้ถาม ต่อให้กดก็ไม่มีคำถามจะยิง
        fake.hasKey = false
        poller.refreshNow(now: at(4))
        equal(fake.launches, 2, "with no key at all there is nothing to ask with")

        // ยิงเองแล้วรอบถัดไปต้องนับหนึ่งใหม่ ไม่ใช่ยิงซ้ำทันทีเพราะรอบเดิมครบพอดี
        fake.hasKey = true
        poller.interval = .minute
        poller.refreshNow(now: at(100))
        fake.finish(0, "session 5%")
        poller.tick(now: at(140))
        equal(fake.launches, 3, "a manual round resets the clock on the automatic one")
        poller.tick(now: at(161))
        equal(fake.launches, 4, "which then carries on as usual")
    }

    suite("the cache says how old its figures are") {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stamp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        expect(UsageReader.stamp(from: url) == nil, "no file, no age")

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        UsageWriter.ingestAPI(
            Data(#"{"five_hour":{"utilization":10,"resets_at":"2023-11-15T03:00:00Z"}}"#.utf8),
            now: t0, to: url)
        equal(UsageReader.stamp(from: url), t0, "the stamp the writer left is the age we read")
    }

    suite("hook event decoding") {
        let json = """
            {"session_id":"abc","transcript_path":"/tmp/t.jsonl","cwd":"/Users/x/repo",
             "hook_event_name":"PreToolUse","tool_name":"Edit",
             "tool_input":{"file_path":"/Users/x/repo/a.swift"}}
            """
        let e = try JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
        equal(e.hookEventName, "PreToolUse", "hook name decodes")
        equal(e.toolName, "Edit", "tool name decodes")
        equal(e.project, "repo", "project comes from the last path component")

        let bare = try JSONDecoder().decode(
            HookEvent.self, from: Data(#"{"session_id":"a","hook_event_name":"Stop"}"#.utf8))
        equal(bare.project, "claude", "missing cwd still names something")
    }

    suite("socket round trip") {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("tama-\(UUID().uuidString).sock")
        let box = Box()
        let server = SocketServer(path: path) { box.append($0) }
        try server.start()
        defer { server.stop() }

        let sent = SocketClient(path: path).send(Data(#"{"hook_event_name":"Stop"}"#.utf8))
        expect(sent, "client writes to the socket")
        expect(box.wait(for: 1, timeout: 2), "server receives the line")

        let dead = SocketClient(
            path: FileManager.default.temporaryDirectory
                .appendingPathComponent("nope-\(UUID().uuidString).sock"))
        expect(!dead.send(Data("{}".utf8)), "no daemon means a clean false, not a hang")
    }
}

/// ที่พักข้อมูลข้ามคิวสำหรับเทสต์ socket
final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Data] = []

    func append(_ d: Data) {
        lock.lock()
        items.append(d)
        lock.unlock()
    }

    func wait(for count: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date() + timeout
        while Date() < deadline {
            lock.lock()
            let n = items.count
            lock.unlock()
            if n >= count { return true }
            usleep(20_000)
        }
        return false
    }
}
