import AppKit
import SwiftUI

/// ไวยากรณ์ภาพของหน้าตั้งค่า — การ์ด แถว บรรทัดสถานะ และปุ่มลากจัดลำดับ
///
/// THESIS: ลิสต์หน้าคือกระดูกสันหลัง ไม่ใช่แท็บ · หน้าต่างนี้ปฏิเสธ IA เดิมที่ให้ weather
/// ถูกฝังใต้แท็บ Pages ขณะที่ crypto/stocks/calendar ซึ่งเป็นพี่น้องกันได้แท็บของตัวเอง
/// แล้วหลุดจากลิสต์ที่คุมว่ามันเปิดอยู่ไหม
///
/// OWN-WORLD: โครงมาจาก System Settings (sidebar + การ์ดมุมโค้ง + ดริลเข้า) ผิวมาจาก
/// Raycast/Linear (จังหวะแน่นกว่าระบบ เส้นขอบเฮร์ไลน์ ไม่มีเงา) สีเดียวที่ไม่ใช่ของระบบ
/// คือส้ม `#D97757` ของมาสคอต ซึ่งใช้เป็น tint ตัวเดียวทั้งหน้าต่าง — เป็นวิธีที่หน้าต่างนี้
/// บอกว่ามันเป็นของมาสคอตโดยไม่ต้องวาดมาสคอต (แดงของ error มาจากระบบ ไม่นับเป็นสีที่สอง)
enum Metrics {
    /// สูงพอให้ logo 16pt (= 32 device px, ขนาดไฟล์จริง) นั่งได้โดยไม่ต้องขยาย
    static let row: CGFloat = 34
    static let rowPadH: CGFloat = 12
    static let radius: CGFloat = 10
    /// ระหว่างการ์ด — ห่างกว่าในแถวหลายเท่า กลุ่มถึงจะอ่านเป็นกลุ่ม
    static let groupGap: CGFloat = 18
    static let paneWidth: CGFloat = 420
}

extension Color {
    /// `#D97757` — brand commitment ที่แตะไม่ได้ (PRODUCT.md) เป็น accent ตัวเดียวของแอป
    static let tama = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
}

// --- การ์ดหนึ่งใบ --------------------------------------------------------------

/// กลุ่มของแถวในกรอบมุมโค้ง — ขอบเป็นเส้นเดียว ไม่มีเงา
///
/// ไม่มีเงาโดยตั้งใจ: เงาที่ไม่มีระยะยกจริงคือของตกแต่ง และหน้าตั้งค่าที่มีการ์ดหกใบ
/// ซ้อนเงากันจะอ่านเป็นพื้นผิวขรุขระแทนที่จะเป็นรายการ
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

/// เส้นคั่นระหว่างแถว — เยื้องซ้ายเท่าระยะขอบของแถว ไม่ใช่ชนขอบการ์ด
struct CardDivider: View {
    var body: some View {
        Divider().padding(.leading, Metrics.rowPadH)
    }
}

/// แถวเปล่าที่รู้ความสูงของตัวเอง — ทุกอย่างในการ์ดผ่านตัวนี้ ความสูงจึงเท่ากันทั้งใบ
struct CardRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .frame(maxWidth: .infinity, minHeight: Metrics.row, alignment: .leading)
            .padding(.horizontal, Metrics.rowPadH)
            .padding(.vertical, 4)
    }
}

/// แถวที่มีชื่อซ้าย ตัวควบคุมขวา
///
/// ชื่ออยู่ชิดซ้ายจริง ไม่ใช่จัดขวาในคอลัมน์กว้างตายตัวเหมือนของเดิม — คอลัมน์ 130pt
/// ที่ตั้งไว้เองบังคับให้แถวที่ไม่มีชื่อ (ติ๊กทุกอัน) ต้องเยื้องเข้ามาโดยไม่มีอะไรอยู่ตรงนั้น
struct LabeledRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        CardRow {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control
        }
    }
}

// --- ข้อความรอบการ์ด -----------------------------------------------------------

/// หัวกลุ่ม — ตัวพิมพ์ปกติ ไม่ใช่ตัวใหญ่จัดระยะ
///
/// จะมีต่อเมื่อหน้าหนึ่งมีการ์ดตั้งแต่สองใบที่ต้องเรียกชื่อแยกกัน การ์ดใบเดียวในหน้า
/// ที่มีชื่อหน้าอยู่แล้วไม่ต้องมีหัวซ้ำ
struct GroupHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}

/// ประโยคใต้การ์ด — หนึ่งประโยค ฉบับเต็มอยู่หลังปุ่ม `ⓘ` ที่หัวการ์ด
struct Footnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// บรรทัดสถานะที่ **จองความสูงไว้เสมอ** แม้ตอนไม่มีอะไรจะพูด
///
/// ของเดิมปล่อยให้มันยุบหายตอนว่าง ผลคือเลย์เอาต์กระโดดทุกครั้งที่ค่าจริงเข้ามาจาก
/// service — ซึ่งเกิดหลังหน้าต่างเปิดไปแล้วเสมอ ผู้ใช้จึงเห็นทุกอย่างขยับตอนที่เขา
/// กำลังจะกดปุ่มพอดี
struct StatusLine: View {
    let text: String
    var isProblem = false

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: 11))
            .foregroundStyle(isProblem ? Color(nsColor: .systemRed) : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 15, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// ปุ่ม `ⓘ` ที่เก็บคำอธิบายฉบับยาว
///
/// ของเดิมวางย่อหน้าสี่ประโยคขนาด 11pt ไว้ท้ายทุกแท็บ ซึ่งกินพื้นที่เท่ากับตัวควบคุม
/// ทั้งหมดรวมกันในบางแท็บ · เนื้อหาไม่ได้ถูกตัดสักคำ มันแค่ย้ายไปอยู่หลังปุ่มที่คน
/// อ่านครั้งเดียวแล้วไม่ต้องอ่านอีก ส่วนประโยคที่ *ต้อง* เห็นทุกครั้งยังอยู่เป็น `Footnote`
struct HelpButton: View {
    let text: String
    @State private var open = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            Image(systemName: "info.circle").font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .handCursor()
        .help("What this page does")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(width: 300)
        }
    }
}

/// หัวการ์ดที่มีปุ่มช่วยเหลืออยู่ขวาสุด
struct HeadingRow: View {
    let title: String
    var help: String?

    var body: some View {
        HStack(spacing: 6) {
            GroupHeading(text: title)
            if let help { HelpButton(text: help) }
            Spacer(minLength: 0)
        }
    }
}

// --- เคอร์เซอร์ ------------------------------------------------------------------

/// เปลี่ยนเคอร์เซอร์ตอนเมาส์อยู่บนของที่กดได้
///
/// **ใช้กับปุ่มที่เป็นสัญลักษณ์เปล่าเท่านั้น ไม่ใช่ทุกอย่างที่คลิกได้** — บน macOS มือชี้
/// สงวนไว้ให้ลิงก์ ปุ่มที่มีขอบใช้ลูกศรตามปกติเพราะขอบเป็นตัวบอกอยู่แล้วว่ากดได้
/// (System Settings, Finder, Xcode ทำแบบนี้ทั้งหมด) ของที่ต้องการตัวช่วยคือ `›` `−` `ⓘ`
/// ซึ่งไม่มีอะไรรอบตัวบอกเลยว่ามันเป็นปุ่ม
///
/// ที่จับลากได้มือ *เปิด* ไม่ใช่มือชี้ — มันไม่ใช่ของที่กดแล้วเกิดอะไรขึ้น มันคือของที่จับแล้วลาก
///
/// `push`/`pop` ต้องเท่ากันเสมอ view ที่หายไปตอนเมาส์ยังอยู่บนมัน (กดปุ่มลบแถวตัวเอง)
/// จึงต้องคืนเคอร์เซอร์เองใน `onDisappear` ไม่งั้นมือค้างอยู่ทั้งหน้าต่าง
private struct HoverCursor: ViewModifier {
    let cursor: NSCursor
    @State private var inside = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != inside else { return }
                inside = hovering
                if hovering { cursor.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if inside {
                    NSCursor.pop()
                    inside = false
                }
            }
    }
}

extension View {
    /// มือชี้ — ปุ่มสัญลักษณ์เปล่าและลิงก์
    func handCursor() -> some View { modifier(HoverCursor(cursor: .pointingHand)) }
    /// มือเปิด — ของที่จับแล้วลาก
    func grabCursor() -> some View { modifier(HoverCursor(cursor: .openHand)) }
}

// --- การลากจัดลำดับ ------------------------------------------------------------

/// แถวที่กำลังถูกยกอยู่
///
/// `origin` คือตำแหน่งตอน *เริ่ม* ลาก และเป็นตัวเดียวที่ใช้คำนวณปลายทาง — `index` ของ view
/// เปลี่ยนไปเองทุกครั้งที่แถวถูกย้าย การเอามันไปบวกกับระยะลากสะสมจึงพาเลยเป้าแล้วเด้งกลับ
/// ทุกเฟรม ซึ่งอ่านออกมาเป็นแถวที่กระพริบ
struct Lift: Equatable {
    var origin: Int
    var index: Int
    var delta: CGFloat
}

/// ระยะห่างจากหัวแถวหนึ่งถึงหัวแถวถัดไป — **วัดเอา ไม่ใช่ตั้งค่าคงที่**
///
/// `Metrics.row` เป็นความสูง *ต่ำสุด* ของเนื้อแถว ไม่ใช่ระยะที่แถวกินจริง ซึ่งยังบวก
/// padding แนวตั้งกับเส้นคั่นเข้าไปอีก การเอาค่าคงที่ 34 ไปหารระยะลากที่กินจริงราว 43
/// ทำให้ลากผ่านหนึ่งแถวนับได้ไม่ถึงหนึ่งขั้น แล้วปัดขึ้นบ้างลงบ้างสลับกันตรงรอยต่อ
///
/// ความสูงของการ์ดไม่เปลี่ยนระหว่างลาก (แถวแค่ถูก offset) ค่าที่วัดจึงนิ่งพอจะเชื่อได้
private struct RowPitchKey: PreferenceKey {
    static let defaultValue: CGFloat = Metrics.row
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension View {
    func measureRowPitch(count: Int, into pitch: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RowPitchKey.self,
                    value: count > 0 ? proxy.size.height / CGFloat(count) : Metrics.row)
            }
        )
        .onPreferenceChange(RowPitchKey.self) { pitch.wrappedValue = $0 }
    }
}

/// ที่จับสำหรับลากจัดลำดับ — แทนปุ่ม `▲`/`▼` ที่เคยมีสองปุ่มต่อแถว
///
/// เลือกลากแทนปุ่ม เพราะสองปุ่มต่อแถวคูณห้าแถวคือสิบปุ่มที่กินความกว้างซึ่งตอนนี้
/// ช่องสรุปสถานะต้องใช้
///
/// **แต่การลากอย่างเดียวคือการถอยหลัง**: ปุ่มเดิมกดด้วยแป้นพิมพ์ได้และ VoiceOver
/// อ่านออก ส่วนการลากไม่มีทั้งสองอย่าง ที่จับใบนี้จึงประกาศตัวเป็น adjustable —
/// VoiceOver ย้ายแถวด้วยลูกศรขึ้นลงได้ตรงๆ — และแถวที่ใช้มันแนบเมนูคลิกขวาไว้ด้วย
/// ทางเข้าที่ *ไม่ใช่* การลากจึงยังมีสองทาง เท่าที่เคยมี
///
/// คำนวณปลายทางจากระยะลากหารด้วยความสูงแถว แล้ว *ย้ายจริงทันที* ระหว่างลาก
/// ไม่ใช่รอปล่อย — แถวที่ขยับตามนิ้วคือสิ่งเดียวที่ยืนยันว่ามันจะลงตรงนั้น
struct ReorderHandle: View {
    let index: Int
    let count: Int
    /// ระยะจริงต่อแถว วัดมาจากการ์ด
    let pitch: CGFloat
    /// ชื่อพื้นที่พิกัดของการ์ด — **ห้ามใช้ `.local`**
    ///
    /// `.local` คือพิกัดของ view ที่ gesture เกาะอยู่ ซึ่งก็คือที่จับใบนี้เอง พอแถวถูกย้าย
    /// ที่จับก็เลื่อนไปด้วย จุดอ้างอิงของการลากเลื่อนตาม แล้ว `translation` กระโดดไปหนึ่ง
    /// แถวทันทีโดยที่เมาส์ไม่ได้ขยับ — คำนวณปลายทางใหม่ ย้ายกลับ วนอย่างนั้นทุกเฟรม
    /// ตราบใดที่ยังกดค้าง · พิกัดของการ์ดไม่ขยับ ระยะที่วัดได้จึงเป็นระยะที่เมาส์เดินจริง
    let space: String
    var enabled = true
    @Binding var lift: Lift?
    /// (จากตำแหน่ง, ไปตำแหน่ง) — ผู้เรียกเป็นคนรู้ว่าลิสต์ของตัวเองย้ายยังไง
    let move: (Int, Int) -> Void
    /// ปล่อยเมาส์แล้วค่อยส่งค่าออกจริง
    ///
    /// **ระหว่างลากห้ามแตะ model**: ทางออกของลำดับวิ่งไป `UserDefaults` และวิ่งต่อไปถึง
    /// บอร์ด แล้วป้อนสถานะกลับเข้าหน้าต่าง การเขียนมันทุกเฟรมของการลากคือการสร้าง
    /// ลิสต์ใหม่ทั้งใบสองรอบต่อเฟรม ซึ่งอ่านออกมาเป็นทั้งลิสต์กระพริบ · `move` จึงขยับ
    /// แค่ลำดับชั่วคราวในหน้าต่าง ส่วนใบนี้เป็นตัวส่งออก ครั้งเดียว
    let commit: () -> Void

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(enabled ? Color.secondary : Color(nsColor: .tertiaryLabelColor))
            .frame(width: 16, height: Metrics.row)
            .contentShape(Rectangle())
            .grabCursor()
            .gesture(enabled && count > 1 ? drag : nil)
            .accessibilityElement()
            .accessibilityLabel("Position \(index + 1) of \(count)")
            .accessibilityHint("Adjust to move this row")
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                // ทางนี้ขยับทีละขั้นและจบในตัว จึงส่งออกทันที ไม่มีการลากให้รอปล่อย
                switch direction {
                case .increment:
                    guard index < count - 1 else { return }
                    move(index, index + 1)
                case .decrement:
                    guard index > 0 else { return }
                    move(index, index - 1)
                @unknown default: return
                }
                commit()
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(space))
            .onChanged { value in
                let origin = lift?.origin ?? index
                let current = lift?.index ?? index
                let steps = Int((value.translation.height / pitch).rounded())
                let target = min(max(0, origin + steps), count - 1)
                if target != current { move(current, target) }
                // ระยะที่เหลือหลังหักช่องที่ย้ายไปแล้ว — แถวจึงตามเมาส์ต่อเนื่อง
                // ไม่ใช่ดีดกลับที่ศูนย์ทุกครั้งที่ข้ามช่อง
                lift = Lift(
                    origin: origin, index: target,
                    delta: value.translation.height - CGFloat(target - origin) * pitch)
            }
            // ปล่อยแล้วแถวยังค้างอยู่ครึ่งช่องได้ — เลื่อนกลับเข้าที่ ไม่ใช่ตัดภาพ
            .onEnded { _ in
                withAnimation(.snappy(duration: 0.16)) { lift = nil }
                commit()
            }
    }
}

/// ระยะที่แถวหนึ่งต้องขยับตามนิ้ว — ศูนย์เมื่อไม่ใช่แถวที่กำลังลาก
func liftOffset(_ lift: Lift?, at index: Int) -> CGFloat {
    lift?.index == index ? (lift?.delta ?? 0) : 0
}

// --- ของเล็กที่ใช้ซ้ำ ------------------------------------------------------------

/// logo ที่ขนาดเท่าไฟล์จริง (16pt = 32 device px บนจอ Retina) ไม่ขยาย
///
/// เหตุผลอยู่ครบใน `LogoIconImage` แล้ว: หน้าตั้งค่าที่โชว์รูปคมกว่าที่จอทำได้คือ
/// หน้าตั้งค่าที่โกหกเรื่องผลลัพธ์
struct LogoBadge: View {
    let symbol: String
    var dimmed = false

    var body: some View {
        Image(nsImage: LogoIconImage.image(for: symbol) ?? NSImage())
            .resizable()
            .frame(width: 16, height: 16)
            .opacity(dimmed ? 0.4 : 1)
    }
}

/// ปุ่ม `−` ใต้การ์ดรายการ — สำนวนตารางของ macOS แทนปุ่ม `Remove` ที่เคยมีทุกแถว
struct ListFooterButtons<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) { content }
            .padding(.horizontal, 4)
    }
}

extension View {
    /// ทางย้ายแถวที่ไม่ต้องลาก — คู่กับ `ReorderHandle` เสมอ ไม่ใช่ทางเลือกเสริม
    ///
    /// อยู่ที่นี่ที่เดียวเพราะทั้งลิสต์หน้าและ watchlist สองใบต้องใช้คำเดียวกัน
    /// เมนูที่พูดว่า "Move up" ที่หนึ่งและ "Move earlier" อีกที่คือสองสำนวนในหน้าต่างเดียว
    @ViewBuilder
    func reorderMenu(index: Int, count: Int, move: @escaping (Int, Int) -> Void) -> some View {
        contextMenu {
            Button("Move Up") { move(index, index - 1) }.disabled(index == 0)
            Button("Move Down") { move(index, index + 1) }.disabled(index >= count - 1)
        }
    }
}
