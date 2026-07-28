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
        equal(late.cards.first?.kind, .alert, "and it is an alert")
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
            MenuBadge(percent: 0, isAlarming: false),
            "a fresh window really is 0%")

        equal(
            MenuBadge.from([UsageSnap(percent: 42, remaining: w / 2)]),
            MenuBadge(percent: 42, isAlarming: false),
            "42% with half the window left is on pace")
        equal(
            MenuBadge.from([UsageSnap(percent: 60, remaining: w / 2)]),
            MenuBadge(percent: 60, isAlarming: true),
            "60% with half the window left is ahead of pace, red before 85%")
        equal(
            MenuBadge.from([UsageSnap(percent: 90, remaining: 0)])?.isAlarming, nil,
            "a rolled window is unknown even at 90% — it cannot alarm about a number it lost")
        equal(
            MenuBadge.from([UsageSnap(percent: 86, remaining: UsageSnap.unknown)]),
            MenuBadge(percent: 86, isAlarming: true),
            "over 85% is red even when the countdown is missing")
        equal(
            MenuBadge.from([UsageSnap(percent: 85, remaining: UsageSnap.unknown)]),
            MenuBadge(percent: 85, isAlarming: false),
            "85% itself is not over the line, and no countdown means no pace check")
        // นาฬิกาสองฝั่งไม่ตรงกันทำให้ countdown ยาวเกินหน้าต่างได้ ถ้าปล่อยให้ elapsed ติดลบ
        // แม้แต่ 0% ก็จะแซง pace แล้วแถบเมนูแดงตั้งแต่หน้าต่างยังไม่เริ่ม
        equal(
            MenuBadge.from([UsageSnap(percent: 0, remaining: w * 2)]),
            MenuBadge(percent: 0, isAlarming: false),
            "a countdown longer than the window is clock skew, not negative elapsed time")
    }

    suite("statusline script never breaks the user's own statusline") {
        let script = StatuslineInstaller.script(
            binary: "/Applications/tamaclaude.app/Contents/MacOS/tamaclaude",
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
