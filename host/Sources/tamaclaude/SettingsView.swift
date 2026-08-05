import SwiftUI
import TamaCore

/// โครงหน้าต่างตั้งค่า — sidebar สี่ช่อง กับหน้าย่อยที่ดริลเข้าจากลิสต์หน้า
///
/// FIRST VIEWPORT: เปิดที่ **Screen** ไม่ใช่ Board — การ์ดใบเดียวกลางจอคือหน้าทั้งห้า
/// เรียงตามลำดับจริงบนบอร์ด แต่ละแถวตอบพร้อมกันสามอย่างโดยไม่ต้องคลิก: ชื่อหน้า ·
/// สถานะย่อ · สวิตช์ที่เปิดมันอยู่
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var pane: Pane? = .screen
    /// เส้นทางดริลเข้าหน้าย่อย — ล้างทุกครั้งที่เปลี่ยนช่องใน sidebar ไม่งั้นผู้ใช้ที่กด
    /// Wi-Fi ระหว่างอยู่ในหน้า Crypto จะกลับมาเจอหน้า Crypto ค้างอยู่ข้างใน
    @State private var path: [PageKind] = []

    enum Pane: String, CaseIterable, Identifiable, Hashable {
        case board, screen, wifi, claude

        var id: String { rawValue }

        var title: String {
            switch self {
            case .board: return "Board"
            case .screen: return "Screen"
            case .wifi: return "Wi-Fi"
            case .claude: return "Claude"
            }
        }

        var icon: String {
            switch self {
            case .board: return "display"
            case .screen: return "rectangle.stack"
            case .wifi: return "wifi"
            case .claude: return "terminal"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 168, ideal: 178, max: 220)
            // ปุ่มพับ sidebar ที่ SwiftUI แถมมาเองไปนั่งกลาง title bar เพราะหน้าต่างนี้
            // ไม่มี toolbar ของตัวเองให้มันเกาะ — และหน้าตั้งค่าสี่ช่องไม่มีเหตุให้พับอยู่แล้ว
            // ผู้ใช้ที่พับมันไปจะเหลือหน้าต่างที่ไปช่องอื่นไม่ได้เลย
            .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack(path: $path) {
                detail
                    .navigationDestination(for: PageKind.self) { kind in
                        PageDetailPane(model: model, kind: kind)
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.tama)
        .onChange(of: pane) { path = [] }
        .frame(minWidth: 660, minHeight: 460)
    }

    @ViewBuilder
    private var detail: some View {
        switch pane ?? .screen {
        case .board: BoardPane(model: model)
        case .screen: ScreenPane(model: model, open: { path.append($0) })
        case .wifi: WiFiPane(model: model)
        case .claude: ClaudePane(model: model)
        }
    }
}

/// เปลือกของทุกหน้า — ชื่อหน้า แล้วเนื้อที่เลื่อนได้
///
/// ชื่ออยู่ในตัวเนื้อหา ไม่ใช่ใน title bar เพราะ title bar เป็นของทั้งหน้าต่าง ("TamaClaude
/// Settings") และหน้าต่างที่เปลี่ยนชื่อตัวเองตามช่องที่เลือกทำให้ผู้ใช้หามันไม่เจอใน
/// Mission Control
struct PaneShell<Content: View>: View {
    let title: String
    /// หน้าย่อยส่งทางกลับเข้ามา — หน้าบนสุดไม่มี
    var back: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.groupGap) {
                VStack(alignment: .leading, spacing: 2) {
                    // ทางกลับอยู่ในเนื้อหา ไม่ใช่ปุ่มที่ NavigationStack วางให้ใน title bar —
                    // ปุ่มที่ระบบวางเองในหน้าต่างที่ไม่มี toolbar ไปโผล่กลางแถบชื่อ ซึ่ง
                    // เป็นที่ที่ไม่มีใครมองหาปุ่มย้อนกลับ
                    if let back {
                        Button { back() } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Screen")
                            }
                            .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .handCursor()
                        .keyboardShortcut("[", modifiers: .command)
                    }
                    Text(title).font(.system(size: 15, weight: .semibold))
                }
                content
            }
            .padding(20)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
