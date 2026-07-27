import Foundation
import TamaCore

let usage = """
tamaclaude — Claude Code session display for the CYD board

usage:
  tamaclaude                     menu bar app (runs the daemon itself)
  tamaclaude --hook              read one hook event on stdin, forward to the daemon
  tamaclaude --daemon [options]  run the daemon
  tamaclaude --install-hooks     write the hook entries into ~/.claude/settings.json
  tamaclaude --install-statusline  take over statusLine.command to capture rate_limits
  tamaclaude --remove-statusline   give the statusLine slot back to the previous command
  tamaclaude --usage-cache       read statusline JSON on stdin, write the usage cache
  tamaclaude --send <json>       send one hand-written event (for testing)

daemon options:
  --print       also print every snapshot to stdout
  --no-ble      skip bluetooth entirely (pairs well with --print)
  -v            verbose logging
"""

let rawArgs = Array(CommandLine.arguments.dropFirst())
Log.verbose = rawArgs.contains("-v")

// LaunchServices แถม `-psn_0_12345` มาให้ตอนเปิดจาก Finder และ `-v` เป็นแค่ระดับ log
// ไม่ใช่โหมด — ทั้งคู่ต้องไม่ทำให้แอปเข้าใจว่าถูกสั่งโหมดที่ไม่รู้จักแล้วออกทันที
let args = rawArgs.filter { $0 != "-v" && !$0.hasPrefix("-psn_") }

/// ต้องถืออ้างอิงไว้ ไม่งั้น DispatchSource ถูกปล่อยแล้วสัญญาณไม่ถึง
var signalSources: [DispatchSourceSignal] = []

func fail(_ msg: String) -> Never {
    Log.info(msg)
    exit(1)
}

switch args.first {
case "--hook":
    exit(HookClient.run())

case "--send":
    guard args.count > 1, let data = args[1].data(using: .utf8) else {
        fail("--send needs a JSON string")
    }
    let ok = SocketClient(path: Paths.socket).send(data)
    exit(ok ? 0 : 1)

case "--install-hooks":
    do {
        try HookInstaller.install()
        Log.info("hooks installed in \(HookInstaller.settingsPath.path)")
    } catch {
        fail("could not install hooks: \(error)")
    }

case "--install-statusline":
    do {
        try StatuslineInstaller.install()
        let prev = StatuslineInstaller.delegatedCommandInScript()
        Log.info("statusline installed at \(Paths.statusline.path)")
        Log.info(prev.map { "delegating rendering to: \($0)" } ?? "no previous statusline to delegate to")
    } catch {
        fail("could not install statusline: \(error)")
    }

case "--remove-statusline":
    do {
        try StatuslineInstaller.uninstall()
        Log.info("statusline slot restored")
    } catch {
        fail("could not remove statusline: \(error)")
    }

case "--usage-cache":
    // เรียกจาก statusline.sh เท่านั้น — ต้องไม่ตายและไม่บ่นไม่ว่า stdin จะเป็นอะไร
    // เพราะ exit code ที่ไม่ใช่ 0 จะไปโผล่เป็นบรรทัด statusline ที่พังของผู้ใช้
    //
    // อาร์กิวเมนต์ที่สองเป็นพาธปลายทาง มีไว้เพื่อทดสอบท่อทั้งเส้นโดยไม่แตะไฟล์จริง
    // (`NSHomeDirectory()` บน macOS อ่านจาก getpwuid ไม่สน $HOME จึงหลอกด้วย env ไม่ได้)
    let target = args.count > 1 ? URL(fileURLWithPath: args[1]) : Paths.usageCache
    let stdin = FileHandle.standardInput.readDataToEndOfFile()
    if let line = UsageWriter.ingest(stdin, to: target) { print(line) }
    exit(0)

case "--daemon":
    Paths.ensureStateDir()
    Log.toFile = true
    let store = SessionStore(toolMap: ToolMap.loadOrDefault(Paths.toolConfig))
    var transports: [Transport] = []
    if !args.contains("--no-ble") { transports.append(BLETransport()) }
    if args.contains("--print") || args.contains("--no-ble") {
        transports.append(PrintTransport())
    }
    let daemon = Daemon(store: store, transports: transports)
    do {
        try daemon.start()
    } catch {
        fail("daemon failed to start: \(error)")
    }
    // ปิดให้เรียบร้อยเสมอ ไม่งั้นไฟล์ socket ค้างและรอบหน้าสตาร์ทไม่ขึ้น
    for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler {
            daemon.stop()
            exit(0)
        }
        src.resume()
        signalSources.append(src)
    }
    dispatchMain()

case "--help", "-h":
    print(usage)

case nil:
    // ไม่มีอาร์กิวเมนต์ = ถูกเปิดแบบ .app ปกติ -> เมนูบาร์ (ซึ่งเป็น daemon ในตัว)
    MenuBar.run()

default:
    fail("unknown option \(args[0])\n\n\(usage)")
}
