import Foundation

/// ค่าเวลาทั้งหมดของตรรกะสถานะ รวมไว้ที่เดียวเพื่อให้เทสต์ตั้งค่าได้
public struct Timings: Sendable {
    /// Stop แล้วเงียบเกินเท่านี้ = ถือว่าต้องเตือนผู้ใช้ (เกณฑ์ใน DESIGN.md)
    public var stopAlert: TimeInterval = 45
    /// ท่าดีใจหลังงานจบ ก่อนกลับไป idle
    public var celebrate: TimeInterval = 4
    /// ท่าเดินเข้ามาของ session ใหม่
    public var entering: TimeInterval = 1.2
    /// ท่ามุดหายก่อนหายจากจอ
    public var leaving: TimeInterval = 1.2
    /// ไม่มีความเคลื่อนไหวเกินเท่านี้ = มาสคอตนอน
    public var sleep: TimeInterval = 300
    /// ไม่มีความเคลื่อนไหวเกินเท่านี้ = ทิ้ง session ไปเลย (กัน session ค้างจาก crash)
    public var evict: TimeInterval = 3600
    /// การ์ดหายเองเมื่อไม่มีใครสนใจ
    public var cardTTL: TimeInterval = 600

    public init() {}
}

/// สิ่งที่ session กำลังทำ — เก็บแค่นี้ ส่วนสถานะภาพคำนวณจากมันบวกเวลา
enum Activity: Equatable {
    case idle
    case thinking
    case tool(VisualState)
    case waiting  // Notification: Claude รอผู้ใช้ตอบ
    case failed   // StopFailure
}

struct Session {
    var id: String
    var project: String
    var activity: Activity = .thinking
    var startedAt: Date
    var lastActivity: Date
    /// เวลาที่ Stop ยิงและยังไม่มี prompt ใหม่ — ใช้ตัดสินเกณฑ์เตือน 45 วิ
    var stoppedAt: Date?
    var celebrateUntil: Date?
    var endingAt: Date?
    var subagents: Int = 0

    func visualState(now: Date, t: Timings) -> VisualState {
        if endingAt != nil { return .leaving }  // prune() เป็นคนเอาออกเมื่อท่าจบ
        if now < startedAt + t.entering { return .entering }
        switch activity {
        case .failed: return .error
        case .waiting: return .waiting
        case .tool, .thinking:
            // การกระจายงานชนะเครื่องมือ: ตอน subagent วิ่ง tool ที่เห็นเป็นของลูกน้อง
            // ไม่ใช่ของ session หลัก — "กำลังคุมงานอยู่" จึงตรงความจริงกว่า
            // (แต่แพ้ error กับ waiting ข้างบน: พังกับต้องการมือคน สำคัญกว่า)
            if subagents > 0 { return .conducting }
            if case .tool(let s) = activity { return s }
            return .thinking
        case .idle:
            if let c = celebrateUntil, now < c { return .celebrate }
            // นอนชนะการทวงถาม: ถ้าเงียบมาเป็นนาทีแล้ว ท่ายืนทวงตลอดกาลไม่ได้สื่ออะไรเพิ่ม
            // การเตือนยังอยู่ในรูปการ์ด ซึ่งเป็นคนละช่องทางกับท่าของมาสคอต
            if now >= lastActivity + t.sleep { return .sleeping }
            if let s = stoppedAt, now >= s + t.stopAlert { return .waiting }
            return .idle
        }
    }
}

struct StoredCard {
    var sessionId: String?
    var title: String
    var body: String
    var kind: CardKind
    var createdAt: Date
}

/// ตัวจริงของ daemon: กินเหตุการณ์จาก hook แล้วคายภาพหน้าจอออกมา
///
/// ไม่มี timer อยู่ข้างใน — เวลาถูกป้อนเข้ามาทุกครั้ง จึงเทสต์ได้ทั้งหมดโดยไม่ต้องรอจริง
public final class SessionStore {
    public var toolMap: ToolMap
    public var timings: Timings
    /// จำนวน slot บนจอ ที่เหลือถูกนับเป็น "+N"
    public let slotCount: Int

    private var order: [String] = []  // ลำดับซ้าย->ขวา ต้องนิ่ง = ลำดับที่ session เกิด
    private var sessions: [String: Session] = [:]
    private var cards: [StoredCard] = []

    public init(toolMap: ToolMap = .default, timings: Timings = Timings(), slotCount: Int = 4) {
        self.toolMap = toolMap
        self.timings = timings
        self.slotCount = slotCount
    }

    // MARK: - รับเหตุการณ์

    public func apply(_ e: HookEvent, now: Date = Date()) {
        let id = e.sessionId
        if sessions[id] == nil {
            // เหตุการณ์แรกที่เห็นเป็นตัวสร้าง session แม้จะไม่ใช่ SessionStart
            // (daemon อาจเพิ่งสตาร์ททีหลัง session)
            sessions[id] = Session(
                id: id,
                project: Text.fit(e.project, to: Text.Limit.project),
                startedAt: now,
                lastActivity: now
            )
            order.append(id)
        }
        guard var s = sessions[id] else { return }
        s.lastActivity = now
        s.endingAt = nil
        if let cwd = e.cwd, !cwd.isEmpty {
            s.project = Text.fit(e.project, to: Text.Limit.project)
        }

        switch e.hookEventName {
        case "SessionStart":
            s.startedAt = now
            s.activity = .idle
            s.stoppedAt = nil
            s.subagents = 0

        case "UserPromptSubmit":
            s.activity = .thinking
            s.stoppedAt = nil
            s.celebrateUntil = nil
            // เทิร์นใหม่ = ล้างตัวนับที่ค้างจากเทิร์นก่อน (SubagentStop ที่หายไปตอน
            // daemon ไม่ได้รัน จะทำให้ session ติดท่า conducting ตลอดกาลถ้าไม่ล้าง)
            s.subagents = 0
            dismissCards(for: id)

        case "PreToolUse":
            s.activity = .tool(toolMap.state(for: e.toolName ?? ""))
            s.stoppedAt = nil

        case "PostToolUse":
            s.activity = .thinking

        case "PreCompact":
            s.activity = .thinking

        case "SubagentStart":
            s.subagents += 1
            s.activity = .thinking

        case "SubagentStop":
            s.subagents = max(0, s.subagents - 1)

        case "Notification":
            s.activity = .waiting
            s.stoppedAt = nil
            push(
                StoredCard(
                    sessionId: id,
                    title: s.project,
                    body: e.message ?? "needs your input",
                    kind: .alert,
                    createdAt: now
                ))

        case "Stop":
            s.activity = .idle
            s.stoppedAt = now
            s.celebrateUntil = now + timings.celebrate
            // main loop จบแล้ว จะมี subagent ค้างจริงไม่ได้
            s.subagents = 0

        case "StopFailure", "SubagentStopFailure":
            s.activity = .failed
            s.stoppedAt = nil
            s.celebrateUntil = nil
            push(
                StoredCard(
                    sessionId: id,
                    title: s.project,
                    body: e.reason ?? e.message ?? "stopped with an error",
                    kind: .alert,
                    createdAt: now
                ))

        case "SessionEnd":
            s.endingAt = now
            s.activity = .idle
            s.subagents = 0
            dismissCards(for: id)

        default:
            break
        }
        sessions[id] = s
    }

    private func push(_ card: StoredCard) {
        // ใบใหม่สุดอยู่บน และ session หนึ่งมีการ์ดค้างได้ใบเดียว
        cards.removeAll { $0.sessionId != nil && $0.sessionId == card.sessionId }
        cards.insert(card, at: 0)
    }

    private func dismissCards(for sessionId: String) {
        cards.removeAll { $0.sessionId == sessionId }
    }

    // MARK: - เวลาเดิน

    /// ทิ้ง session ที่จบท่ามุดหายแล้ว/ค้างนานเกิน และการ์ดที่หมดอายุ
    public func prune(now: Date = Date()) {
        for (id, s) in sessions {
            let ended = s.endingAt.map { now >= $0 + timings.leaving } ?? false
            let stale = now >= s.lastActivity + timings.evict
            if ended || stale {
                sessions[id] = nil
                order.removeAll { $0 == id }
                dismissCards(for: id)
            }
        }
        cards.removeAll { now >= $0.createdAt + timings.cardTTL }
    }

    /// เติมการ์ดเตือนของ session ที่ Stop แล้วเงียบเกินเกณฑ์
    private func stopAlerts(now: Date) {
        for id in order {
            guard let s = sessions[id], let stopped = s.stoppedAt else { continue }
            guard now >= stopped + timings.stopAlert else { continue }
            guard !cards.contains(where: { $0.sessionId == id }) else { continue }
            push(
                StoredCard(
                    sessionId: id,
                    title: s.project,
                    body: "waiting for you",
                    kind: .alert,
                    createdAt: now
                ))
        }
    }

    // MARK: - ภาพหน้าจอ

    public func snapshot(now: Date = Date(), calendar: Calendar = .current) -> Snapshot {
        prune(now: now)
        stopAlerts(now: now)

        let live = order.compactMap { sessions[$0] }
        // เลือกตัวที่ได้ slot ตามความสำคัญ แต่ *วาด* ตามลำดับเกิดเสมอ
        // สิ่งที่ต้องนิ่งคือลำดับซ้าย->ขวา ไม่ใช่พิกัด (DESIGN.md)
        let chosen: [Session]
        if live.count <= slotCount {
            chosen = live
        } else {
            // เรียงตาม: ความสำคัญ -> ขยับล่าสุด -> เกิดทีหลัง
            // ข้อสุดท้ายทำให้ผลนิ่ง (ไม่ขึ้นกับการเรียงที่ไม่เสถียร) และตัดตัวที่เก่าสุด
            // และเงียบสุดออกก่อน ซึ่งเป็นตัวที่ผู้ใช้น่าจะสนใจน้อยที่สุด
            let ranked = live.enumerated().sorted { a, b in
                let pa = a.element.visualState(now: now, t: timings).priority
                let pb = b.element.visualState(now: now, t: timings).priority
                if pa != pb { return pa > pb }
                if a.element.lastActivity != b.element.lastActivity {
                    return a.element.lastActivity > b.element.lastActivity
                }
                return a.offset > b.offset
            }
            let keep = Set(ranked.prefix(slotCount).map { $0.offset })
            chosen = live.enumerated().filter { keep.contains($0.offset) }.map { $0.element }
        }

        let snaps = chosen.map {
            SessionSnap(project: $0.project, state: $0.visualState(now: now, t: timings))
        }

        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        let clock = f.string(from: now)
        f.dateFormat = "EEE d MMM"
        let date = f.string(from: now)

        return Snapshot(
            clock: clock,
            date: date,
            overflow: max(0, live.count - chosen.count),
            sessions: snaps,
            cards: cards.prefix(3).map {
                CardSnap(
                    title: Text.fit($0.title, to: Text.Limit.cardTitle),
                    body: Text.fit($0.body, to: Text.Limit.cardBody),
                    kind: $0.kind
                )
            }
        )
    }

    public var sessionCount: Int { sessions.count }
}
