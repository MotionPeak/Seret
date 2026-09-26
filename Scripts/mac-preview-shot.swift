// Launch the built Mac app into a DEBUG `-uiPreview` case, wait for its window, capture just that
// window (no shadow), then quit the app. Screen capture needs the Screen Recording permission for
// the process that runs this script.
//
// Usage: swift Scripts/mac-preview-shot.swift <case> <out.png> [settle-seconds=3]
//        [app=.build/mac/Build/Products/Debug/Seret.app] [extra app arguments…]
// The case `live` launches the real app (no -uiPreview).
import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: mac-preview-shot.swift <case> <out.png> [settle] [app] [args…]\n".utf8))
    exit(2)
}
let previewCase = args[1]
let out = args[2]
let settle = args.count > 3 ? (Double(args[3]) ?? 3) : 3
let appPath = args.count > 4 ? args[4] : ".build/mac/Build/Products/Debug/Seret.app"
let extra = args.count > 5 ? Array(args[5...]) : []

// One instance at a time, or the capture could find a stale window.
for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.solomons.seret.mac") {
    app.forceTerminate()
}
Thread.sleep(forTimeInterval: 0.5)

let process = Process()
process.executableURL = URL(fileURLWithPath: appPath + "/Contents/MacOS/Seret")
// Never restore (or save) window state: the preview shares the real app's bundle id, so it would
// reopen the owner's FULL-SCREEN window — on a Space of its own, where `screencapture` gets nothing.
process.arguments = ["-ApplePersistenceIgnoreState", "YES"]
    + (previewCase == "live" ? [] : ["-uiPreview", previewCase]) + extra
// The app's own output stays out of this script's: a caller piping it (`| tail -1`) would otherwise
// wait on the app, not on the capture.
process.standardOutput = FileHandle.nullDevice
process.standardError = FileHandle.nullDevice
try process.run()

// The app's main window is its LARGEST window on the normal layer (0, or 3 once floated). The first
// match can be a small auxiliary window (a 500×500 helper), so never take the first one. `.optionAll`, not on-screen
// only, so this still works while the owner is in another (e.g. full-screen) Space and the app is
// neither frontmost nor visible: `screencapture -l` renders a window by id wherever it is.
func windowID(owner pid: Int32) -> CGWindowID? {
    let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    func area(_ window: [String: Any]) -> CGFloat {
        guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds) else { return 0 }
        return rect.width * rect.height
    }
    return windows
        // Layer 0, or 3 once a DEBUG run floats its window in front (`ScrollBench.bringWindowForward`).
        .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid
            && [0, 3].contains($0[kCGWindowLayer as String] as? Int ?? -1) }
        .filter { area($0) >= 300 * 300 }
        .max { area($0) < area($1) }
        .flatMap { $0[kCGWindowNumber as String] as? CGWindowID }
}

var found: CGWindowID?
for _ in 0..<75 where found == nil {          // up to 15 s for the first window
    found = windowID(owner: process.processIdentifier)
    if found == nil { Thread.sleep(forTimeInterval: 0.2) }
}
guard found != nil else {
    process.terminate()
    FileHandle.standardError.write(Data("no window appeared for case \(previewCase)\n".utf8))
    exit(1)
}
Thread.sleep(forTimeInterval: settle)        // let animations and images settle
// Re-resolve after settling: the main window can appear after an auxiliary one did.
guard let id = windowID(owner: process.processIdentifier) ?? found else { exit(1) }
let capture = Process()
capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
capture.arguments = ["-x", "-o", "-l\(id)", out]
try capture.run()
capture.waitUntilExit()
process.terminate()
// A preview playing video can ignore SIGTERM (seen with libvlc mid-play, minutes later still up) —
// it must never outlive its capture.
let deadline = Date().addingTimeInterval(3)
while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
if process.isRunning { kill(process.processIdentifier, SIGKILL) }
print("wrote \(out) (window \(id), case \(previewCase))")
