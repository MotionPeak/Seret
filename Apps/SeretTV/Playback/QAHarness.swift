#if DEBUG
import SwiftUI
import UIKit
import QuartzCore
import DebridUI
import DebridCore

/// DEBUG-only QA sweep harness: scripted sessions on a real Apple TV, which takes no synthesized
/// input. Everything it measures lands in `Library/Caches/vlc.log` as `[qa]` lines beside libvlc's
/// own timestamped lines, so one pulled file carries the whole timeline.
///
///     -qaScript "open:Dune;wait:20;close;wait:4;open:Dune;wait:20;close"
///
/// Steps (`;`-separated):
/// - `open:<text>`     push the player for the first film whose title contains the text, from the
///                     start (a show's first episode if no film matches)
/// - `resume:<text>`   the same, but resuming from the saved position (the Resume path)
/// - `ep:<text>:<n>`   the n-th episode (0-based, season/episode order) of the matching show
/// - `close`           pop to the root, exactly as Menu leaves the player
/// - `wait:<s>`        idle for s seconds
/// - `tab:<item>`      switch the side-menu page (home, movies, shows, watchlist, library)
/// - `scroll`          walk every scroll view on screen, page by page, and back
/// - `bg`              send the app to the background (Home press) — come back with a relaunch
/// - `skip:<spec>`     `-autoSkips` grammar, against the playing model ("10,-10,10x4,@1200,p30")
///
/// Always on while the harness runs: a main-thread hang detector, a CADisplayLink frame meter,
/// the player's phase/buffering/first-frame transitions, libvlc's picture counters, and the
/// process footprint.
@MainActor
enum QA {
    static let script: [String]? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-qaScript"), i + 1 < args.count else { return nil }
        return args[i + 1].split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
    }()

    static var isOn: Bool { script != nil || ProcessInfo.processInfo.arguments.contains("-qaProbe") }

    /// The model of the player on screen, for `skip:` steps and the stats sampler.
    static weak var currentModel: PlayerModel?
    static weak var currentEngine: VLCKitVideoPlayerEngine?

    nonisolated static func log(_ line: String) {
        DiagnosticsLog.shared.write("[qa] \(line)")
        print("[qa] \(line)")
    }

    static func t(_ s: Double) -> String {
        guard s.isFinite else { return "-" }
        let v = Int(s.rounded()); return String(format: "%d:%02d:%02d", v / 3600, (v % 3600) / 60, v % 60)
    }

    // MARK: - Always-on meters

    private static var started = false
    static func startMeters() {
        guard isOn, !started else { return }
        started = true
        HangDetector.shared.start()
        FrameMeter.shared.start()
        Task { @MainActor in
            while true {
                log(String(format: "mem footprint=%.0fMB", footprintMB()))
                try? await Task.sleep(for: .seconds(30))
            }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                               object: nil, queue: .main) { _ in log("app background") }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                               object: nil, queue: .main) { _ in log("app foreground") }
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: .main) { _ in log("MEMORY WARNING") }
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size
                                           / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    // MARK: - Requests

    static func request(in store: LibraryStore, step: String) -> PlaybackRequest? {
        let parts = step.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        let (verb, needle) = (parts[0], parts[1])
        if verb == "ep" || (verb != "resume" && !store.movies.contains(where: {
            $0.title.localizedCaseInsensitiveContains(needle) })) {
            guard let show = store.shows.first(where: { $0.title.localizedCaseInsensitiveContains(needle) })
            else { return nil }
            let index = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
            guard let ep = show.seasons.sortedBySeason()
                .flatMap({ $0.episodes.sorted(by: { $0.number < $1.number }) })
                .dropFirst(index).first else { return nil }
            log("request \(show.title) S\(ep.season)E\(ep.number) \(describe(ep.source))")
            return PlaybackRequest(item: show, source: ep.source, resumeAt: nil,
                                   label: "\(show.title) — S\(ep.season)·E\(ep.number)",
                                   contentKey: WatchKey.content(forShow: show, episode: ep),
                                   episode: ep, fromStart: verb != "resume")
        }
        guard let item = store.movies.first(where: { $0.title.localizedCaseInsensitiveContains(needle) }),
              let source = item.sources.best else { return nil }
        log("request \(item.title) \(describe(source)) fromStart=\(verb != "resume")")
        return PlaybackRequest(item: item, source: source, resumeAt: nil, label: item.title,
                               contentKey: WatchKey.content(forMovie: item), episode: nil,
                               fromStart: verb != "resume")
    }

    private static func describe(_ s: MediaSource) -> String {
        [s.parsed.resolution, s.parsed.videoCodec, s.parsed.source, s.parsed.audioCodec]
            .compactMap { $0 }.joined(separator: "·") + " size=\(s.sizeBytes.map { "\($0 / 1_000_000)MB" } ?? "?")"
    }

    // MARK: - Scroll walk

    /// Every scroll view in the key window with room to move, longest first.
    static func scrollViews() -> [UIScrollView] {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return [] }
        var found: [UIScrollView] = []
        func walk(_ v: UIView) {
            if let s = v as? UIScrollView, !s.isHidden, s.window != nil,
               s.contentSize.height > s.bounds.height + 10 || s.contentSize.width > s.bounds.width + 10 {
                found.append(s)
            }
            v.subviews.forEach(walk)
        }
        walk(window)
        return found
    }

    /// Page through the main vertical scroll view; at each stop, run every visible horizontal rail
    /// to its end and back. Animated, so the frame meter sees what a viewer would.
    static func scrollWalk() async {
        let all = scrollViews()
        let vertical = all.filter { $0.contentSize.height > $0.bounds.height + 10 }
            .max(by: { $0.contentSize.height < $1.contentSize.height })
        log("scroll start: \(all.count) scroll views, vertical content=\(Int(vertical?.contentSize.height ?? 0))")
        FrameMeter.shared.beginWindow("scroll")
        let pages = vertical.map { max(1, Int(ceil($0.contentSize.height / max($0.bounds.height * 0.6, 1)))) } ?? 1
        for page in 0..<min(pages, 30) {
            if let v = vertical {
                let y = min(CGFloat(page) * v.bounds.height * 0.6, v.contentSize.height - v.bounds.height)
                v.setContentOffset(CGPoint(x: 0, y: max(0, y)), animated: true)
                try? await Task.sleep(for: .milliseconds(900))
            }
            let rails = scrollViews().filter { $0.contentSize.width > $0.bounds.width + 10
                && $0.convert($0.bounds, to: nil).intersects(UIScreen.main.bounds) }
            for rail in rails.prefix(3) {
                var x: CGFloat = 0
                while x < rail.contentSize.width - rail.bounds.width {
                    x = min(x + rail.bounds.width * 0.5, rail.contentSize.width - rail.bounds.width)
                    rail.setContentOffset(CGPoint(x: x, y: 0), animated: true)
                    try? await Task.sleep(for: .milliseconds(450))
                }
                rail.setContentOffset(.zero, animated: true)
                try? await Task.sleep(for: .milliseconds(450))
            }
        }
        vertical?.setContentOffset(.zero, animated: true)
        try? await Task.sleep(for: .milliseconds(900))
        FrameMeter.shared.endWindow("scroll")
        log("scroll done")
    }

    /// The Home button, as far as the app can tell: the documented-by-folklore suspend selector.
    static func background() {
        UIControl().sendAction(NSSelectorFromString("suspend"), to: UIApplication.shared, for: nil)
    }

    /// `-autoSkips` grammar, against the model on screen.
    static func runSkips(_ spec: String) async {
        guard let model = currentModel else { log("skip: no player"); return }
        for token in spec.split(separator: ",") {
            let start = Date()
            if token.hasPrefix("@") {
                let target = Double(token.dropFirst()) ?? 0
                log("skip \(token) from \(t(model.position))")
                model.scrub(to: target)
            } else if token.hasPrefix("%") {
                let pct = Double(token.dropFirst()) ?? 0
                let target = model.duration * pct / 100
                log("skip \(token) → \(t(target)) from \(t(model.position))")
                model.scrub(to: target)
            } else if token.hasPrefix("p") {
                log("pause \(token)")
                model.pause()
                try? await Task.sleep(for: .seconds(Double(token.dropFirst()) ?? 1))
                model.play()
            } else if token.hasPrefix("s") {                      // hold-to-scan for N seconds
                let hold = Double(token.dropFirst()) ?? 3
                log("scan hold \(hold)s from \(t(model.position))")
                model.beginScan(direction: 1)
                try? await Task.sleep(for: .seconds(hold))
                log("scan release at bar \(t(model.position))")
                model.endScan()
            } else {
                let parts = token.split(separator: "x")
                let delta = Double(parts[0]) ?? 10
                let taps = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
                log("skip \(token) from \(t(model.position))")
                for i in 0..<taps {
                    if i > 0 { try? await Task.sleep(for: .milliseconds(280)) }
                    model.skip(delta)
                }
            }
            // Landed = no seek pending, not buffering, playing, and the frame counter moving.
            let shown = model.position
            var landed = false
            for _ in 0..<600 {
                try? await Task.sleep(for: .milliseconds(50))
                if !model.debugSeekPending, !model.isBuffering, model.phase == .playing { landed = true; break }
            }
            log(String(format: "skip %@ %@ after %.2fs at %@ (bar said %@)", String(token),
                       landed ? "landed" : "NOT-landed", Date().timeIntervalSince(start),
                       t(model.position), t(shown)))
            try? await Task.sleep(for: .seconds(6))
        }
    }
}

// MARK: - Script runner (driven by LibraryShell, which owns the path)

@MainActor
final class QAScriptRunner {
    static let shared = QAScriptRunner()
    private var running = false

    func runIfRequested(store: LibraryStore?, push: @escaping (PlaybackRequest) -> Void,
                        popToRoot: @escaping () -> Void, selectTab: @escaping (SideMenuItem) -> Void) {
        guard !running, let steps = QA.script, let store, !store.movies.isEmpty else { return }
        running = true
        QA.startMeters()
        Task { @MainActor in
            QA.log("script start: \(steps.count) steps")
            try? await Task.sleep(for: .seconds(3))
            for (n, step) in steps.enumerated() {
                QA.log("step \(n) \(step)")
                let verb = step.split(separator: ":").first.map(String.init) ?? step
                switch verb {
                case "open", "resume", "ep":
                    if let req = QA.request(in: store, step: step) { push(req) }
                    else { QA.log("step \(n) NO MATCH \(step)") }
                case "close":
                    let pos = QA.currentModel.map { QA.t($0.position) } ?? "-"
                    QA.log("close at \(pos)")
                    popToRoot()
                case "wait":
                    try? await Task.sleep(for: .seconds(Double(step.dropFirst(5)) ?? 1))
                case "tab":
                    if let item = SideMenuItem(rawValue: String(step.dropFirst(4))) { selectTab(item) }
                    try? await Task.sleep(for: .seconds(2))
                case "scroll":
                    await QA.scrollWalk()
                case "bg":
                    QA.background()
                case "skip":
                    await QA.runSkips(String(step.dropFirst(5)))
                default:
                    QA.log("step \(n) UNKNOWN \(step)")
                }
            }
            QA.log("script done")
        }
    }
}

// MARK: - Player probe (attached by PlayerHost)

struct QAPlayerProbe: ViewModifier {
    let model: PlayerModel
    let engine: VLCKitVideoPlayerEngine
    @State private var appeared = Date()
    @State private var sampler: Task<Void, Never>?

    func body(content: Content) -> some View {
        if QA.isOn {
            content
                .onAppear {
                    appeared = Date()
                    QA.currentModel = model
                    QA.currentEngine = engine
                    QA.log("player appear")
                    FrameMeter.shared.beginWindow("player")
                    sampler = Task { @MainActor in
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(10))
                            QA.log("stats pos=\(QA.t(model.position))/\(QA.t(model.duration)) phase=\(model.phase) "
                                   + (engine.debugStatsLine() ?? "no-media"))
                        }
                    }
                }
                .onDisappear {
                    sampler?.cancel()
                    QA.log("player disappear at \(QA.t(model.position)) " + (engine.debugStatsLine() ?? ""))
                    FrameMeter.shared.endWindow("player")
                }
                .onChange(of: model.phase) { old, new in
                    QA.log(String(format: "phase %@ → %@ (+%.2fs)", "\(old)", "\(new)",
                                  Date().timeIntervalSince(appeared)))
                }
                .onChange(of: model.isBuffering) { _, new in
                    QA.log(String(format: "buffering %@ at %@ (+%.2fs)", new ? "ON" : "off",
                                  QA.t(model.position), Date().timeIntervalSince(appeared)))
                }
                .onChange(of: model.hasRenderedFrame) { _, new in
                    if new {
                        QA.log(String(format: "FIRST FRAME +%.2fs at %@", Date().timeIntervalSince(appeared),
                                      QA.t(model.position)))
                    }
                }
        } else {
            content
        }
    }
}

// MARK: - Main-thread hang detector

/// A background thread pings the main queue every 50ms; a reply that takes longer than 100ms is a
/// hang the viewer can feel (a missed focus move, a frozen spinner). Logs each one with its length.
final class HangDetector: @unchecked Sendable {
    static let shared = HangDetector()
    private let threshold: TimeInterval = 0.1

    func start() {
        let thread = Thread { [threshold] in
            while true {
                let sem = DispatchSemaphore(value: 0)
                let sent = CFAbsoluteTimeGetCurrent()
                DispatchQueue.main.async { sem.signal() }
                if sem.wait(timeout: .now() + threshold) == .timedOut {
                    sem.wait()
                    let ms = (CFAbsoluteTimeGetCurrent() - sent) * 1000
                    QA.log(String(format: "HANG main thread blocked %.0fms", ms))
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        thread.name = "qa.hang"
        thread.qualityOfService = .userInteractive
        thread.start()
    }
}

// MARK: - Frame meter

/// CADisplayLink on the main run loop: a frame later than 1.5× the display's interval is a dropped
/// frame on the app's side of the render pipeline (libvlc's own video frames are its counters).
@MainActor
final class FrameMeter: NSObject {
    static let shared = FrameMeter()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames = 0, hitches = 0, worst: Double = 0, hitchMs: Double = 0
    private var windows: [String: (frames: Int, hitches: Int, worst: Double, hitchMs: Double, start: Date)] = [:]
    private var periodStart = Date()

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard last > 0 else { return }
        let dt = link.timestamp - last
        let expected = link.duration > 0 ? link.duration : 1.0 / 60
        frames += 1
        var hitch = 0.0
        if dt > expected * 1.5 { hitches += 1; hitch = (dt - expected) * 1000; hitchMs += hitch }
        worst = max(worst, dt * 1000)
        for key in windows.keys {
            windows[key]!.frames += 1
            if hitch > 0 { windows[key]!.hitches += 1; windows[key]!.hitchMs += hitch }
            windows[key]!.worst = max(windows[key]!.worst, dt * 1000)
        }
        if Date().timeIntervalSince(periodStart) >= 10 {
            if hitches > 0 {
                QA.log(String(format: "frames 10s: %d frames, %d hitches, hitch %.0fms total, worst %.0fms, interval %.1fms",
                              frames, hitches, hitchMs, worst, expected * 1000))
            }
            frames = 0; hitches = 0; worst = 0; hitchMs = 0; periodStart = Date()
        }
    }

    func beginWindow(_ name: String) { windows[name] = (0, 0, 0, 0, Date()) }

    func endWindow(_ name: String) {
        guard let w = windows.removeValue(forKey: name) else { return }
        let secs = Date().timeIntervalSince(w.start)
        QA.log(String(format: "window %@: %.1fs %d frames (%.1f fps) %d hitches, hitch time %.0fms (%.1f ms/s), worst %.0fms",
                      name, secs, w.frames, Double(w.frames) / max(secs, 0.001), w.hitches, w.hitchMs,
                      w.hitchMs / max(secs, 0.001), w.worst))
    }
}
#endif
