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
process.arguments = (previewCase == "live" ? [] : ["-uiPreview", previewCase]) + extra
try process.run()

// The app's main window is its LARGEST normal-layer (0) window. The first match can be a small
// auxiliary window (a 500×500 helper), so never take the first one. `.optionAll`, not on-screen
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
        .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
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
print("wrote \(out) (window \(id), case \(previewCase))")
