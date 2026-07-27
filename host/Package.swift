// swift-tools-version: 6.0
import PackageDescription

// ไม่ใช้ testTarget เพราะเครื่องที่มีแค่ Command Line Tools (ไม่มี Xcode เต็มตัว)
// จะ *build* ชุดเทสต์ผ่านแต่ไม่รันมันเลยและยัง exit 0 ซึ่งอันตรายกว่าไม่มีเทสต์
// `swift run tamatest` เป็น executable ธรรมดา จึงรันได้เหมือนกันทุกเครื่อง
let package = Package(
    name: "tamaclaude",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "TamaCore",
            path: "Sources/TamaCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "tamaclaude",
            dependencies: ["TamaCore"],
            path: "Sources/tamaclaude",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // ฝัง Info.plist ลงไบนารี — CLI ที่ไม่มีมันจะถูก CoreBluetooth ปฏิเสธเงียบๆ
            // (ไม่มี callback ไม่มี error ไม่มีกล่องขออนุญาต)
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/tamaclaude/Info.plist",
                ])
            ]
        ),
        .executableTarget(
            name: "tamatest",
            dependencies: ["TamaCore"],
            path: "Sources/tamatest",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
