#if DEBUG
import AppKit
import QuartzCore

/// `-scrollBench [home|library|movies|shows|watchlist] [seconds]` — scrolls the page on screen top
/// to bottom and back at a steady 2,400 pt/s, one step per display frame, and prints how evenly the
/// frames arrived: the fps achieved, the hitches (a frame that took ≥ 1.5× the refresh interval),
/// the time lost to them, and the worst frame. Then quits.
///
/// It measures main-thread frame pacing — the kind of stall SwiftUI work causes — through the
/// display link, which is late exactly when the main thread was busy.
@MainActor
final class ScrollBench: NSObject {
    private static var current: ScrollBench?

    private let scrollView: NSScrollView
    private let duration: Double
    private var link: CADisplayLink?
    private var start: CFTimeInterval = 0
    private var last: CFTimeInterval = 0
    private var intervals: [Double] = []
    private var direction: CGFloat = 1
    private let speed: CGFloat = 2400

    private init(scrollView: NSScrollView, duration: Double) {
        self.scrollView = scrollView
        self.duration = duration
    }

    /// A window on another Space — the usual case when the owner's own Seret is full screen — is
    /// never drawn, so SwiftUI never even runs the page's tasks and the bench would wait forever.
    /// Benchmark, `-uiPreview` and `-typeSearch` runs only: float the window in front, on whatever
    /// Space is showing — `.canJoinAllSpaces`, since a window already placed on the desktop Space does
    /// not follow `.moveToActiveSpace` into a full-screen one, and `screencapture` then gets nothing.
    static func bringWindowForward() {
        let args = ProcessInfo.processInfo.arguments
        guard requestedSection() != nil || args.contains("-uiPreview") || args.contains("-typeSearch")
        else { return }
        for delay in [0.3, 1.0, 2.0, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                for window in NSApp.windows where window.frame.height > 200 {
                    window.collectionBehavior.remove(.moveToActiveSpace)
                    window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
                    window.level = .floating
                    window.orderFrontRegardless()
                }
                NSApp.activate()
            }
        }
    }

    /// The section to bench, if `-scrollBench` was passed.
    static func requestedSection(arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let index = arguments.firstIndex(of: "-scrollBench") else { return nil }
        let next = index + 1 < arguments.count ? arguments[index + 1] : "home"
        return next.hasPrefix("-") ? "home" : next
    }

    static func run(after delay: Double) {
        let args = ProcessInfo.processInfo.arguments
        let seconds = args.firstIndex(of: "-scrollBench").flatMap { i in
            i + 2 < args.count ? Double(args[i + 2]) : nil } ?? 10
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let content = window.contentView,
                  let scrollView = largestVerticalScrollView(in: content) else {
                report("[scrollBench] no scroll view found")
                NSApp.terminate(nil)
                return
            }
            let bench = ScrollBench(scrollView: scrollView, duration: seconds)
            current = bench
            bench.begin(in: content)
        }
    }

    /// Printed AND appended to `Caches/scrollbench.txt` — stdout is often gone by the time the
    /// app quits.
    static func report(_ line: String) {
        print(line)
        fflush(stdout)
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let url = dir.appendingPathComponent("scrollbench.txt")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private static func largestVerticalScrollView(in root: NSView) -> NSScrollView? {
        var best: NSScrollView?
        var bestHeight: CGFloat = 0
        func walk(_ view: NSView) {
            if let scroll = view as? NSScrollView, let doc = scroll.documentView,
               doc.frame.height > scroll.contentView.bounds.height + 200,
               doc.frame.height > bestHeight {
                best = scroll
                bestHeight = doc.frame.height
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        return best
    }

    private func begin(in view: NSView) {
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        let doc = scrollView.documentView?.frame.height ?? 0
        Self.report("[scrollBench] scrolling \(Int(doc)) pt of content for \(Int(duration)) s")
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if start == 0 {
            start = now
            last = now
            return
        }
        let dt = now - last
        last = now
        intervals.append(dt)

        let clip = scrollView.contentView
        let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height)
        var y = clip.bounds.origin.y + direction * speed * CGFloat(dt)
        if y >= maxY { y = maxY; direction = -1 }
        if y <= 0 { y = 0; direction = 1 }
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)

        if now - start >= duration { finish(refresh: link.targetTimestamp - link.timestamp) }
    }

    private func finish(refresh: Double) {
        link?.invalidate()
        link = nil
        let frame = intervals.sorted()[intervals.count / 2]   // the median interval is the refresh
        let hitches = intervals.filter { $0 >= frame * 1.5 }
        let lost = hitches.reduce(0) { $0 + ($1 - frame) }
        let total = intervals.reduce(0, +)
        let p99 = intervals.sorted()[Int(Double(intervals.count - 1) * 0.99)]
        Self.report(String(format: "[scrollBench] %.0f Hz · %.1f fps · %d hitches · %.1f ms lost per s · p99 %.1f ms · worst %.1f ms",
                           1 / frame, Double(intervals.count) / total, hitches.count,
                           lost * 1000 / total, p99 * 1000, (intervals.max() ?? 0) * 1000))
        // Hitches per second of the run: a burst in the first seconds is rows being built for the
        // first time; hitches spread evenly are a per-frame cost.
        var perSecond = [Int](repeating: 0, count: Int(duration.rounded(.up)) + 1)
        var elapsed = 0.0
        for dt in intervals {
            elapsed += dt
            if dt >= frame * 1.5 { perSecond[min(perSecond.count - 1, Int(elapsed))] += 1 }
        }
        Self.report("[scrollBench] hitches by second: \(perSecond.map(String.init).joined(separator: " "))")
        NSApp.terminate(nil)
    }
}

/// `-dumpViews [seconds=12]` — after the delay, appends the main window's AppKit view tree to
/// `Caches/scrollbench.txt`: each view's class, frame in window coordinates, hidden/alpha, and every
/// scroll view's offset and document size. It is how the Search overflow was found — the window's
/// SwiftUI root laid out 1684 pt tall inside an 828 pt window, the sidebar's rows above its top edge.
@MainActor
enum ViewDump {
    static func scheduleIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-dumpViews") else { return }
        let delay = i + 1 < args.count ? Double(args[i + 1]) ?? 12 : 12
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = NSApp.windows.max(by: { $0.frame.width < $1.frame.width }),
                  let root = window.contentView?.superview ?? window.contentView else { return }
            var lines = ["window \(window.frame.integral) key=\(window.isKeyWindow)"]
            func walk(_ view: NSView, _ depth: Int) {
                let frame = view.convert(view.bounds, to: nil).integral
                var extra = ""
                if let scroll = view as? NSScrollView {
                    extra = " scroll-origin=\(scroll.contentView.bounds.origin) doc=\(scroll.documentView?.frame.size ?? .zero)"
                }
                lines.append(String(repeating: "  ", count: depth)
                    + "\(type(of: view)) \(frame) hidden=\(view.isHidden) alpha=\(view.alphaValue) subs=\(view.subviews.count)" + extra)
                guard depth < 9 else { return }
                for sub in view.subviews { walk(sub, depth + 1) }
            }
            walk(root, 0)
            ScrollBench.report(lines.joined(separator: "\n"))
        }
    }
}
#endif
