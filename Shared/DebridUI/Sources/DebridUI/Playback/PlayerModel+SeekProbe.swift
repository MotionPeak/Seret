#if DEBUG
import Foundation

/// DEBUG-only: measure where a long seek actually LANDS.
///
/// "Skip a big amount and it doesn't drop you off at that point" is the one open playback report
/// that needs no freeze to reproduce and no remote to drive — it either happens on every long seek
/// or it does not. The suspect is `:input-fast-seek`, which tells libvlc to land on the nearest
/// keyframe rather than seek precisely; on a REMUX with sparse keyframes that can be a long way
/// from where the viewer asked.
///
/// So: seek a known distance, then watch the playhead for twenty seconds and print where it went.
/// Run it against a build with the option and one without (`-noFastSeek`) and the difference is the
/// answer.
///
///     … -- -vlcLog -autoPlay -autoSeek 1200
///     … -- -vlcLog -autoPlay -autoSeek 1200 -noFastSeek
extension PlayerModel {

    /// Target for the probe seek, in seconds. nil = not requested.
    static var seekProbeTarget: Double? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-autoSeek"), i + 1 < args.count else { return nil }
        return Double(args[i + 1])
    }

    /// Seconds to HOLD a scan for, in seconds. nil = not requested.
    ///
    /// Holding an arrow is how a viewer actually travels twenty minutes, and it is not the same
    /// code path as a scrub: it is a burst of accelerating skips, throttled so only every nth one
    /// reaches the engine, with one flush on release. A direct seek landing correctly says nothing
    /// about whether that burst does.
    static var scanProbeHold: Double? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-autoScan"), i + 1 < args.count else { return nil }
        return Double(args[i + 1])
    }

    /// DEBUG-only: is `-resumeProbe` set? Prints the timeline of a resume.
    ///
    /// The open question is whether the "best-effort seek right at load" in `loadCurrentSource()`
    /// is honored at all. libvlc has no input thread until the media opens, so a `set_time` issued
    /// before then may simply be dropped — in which case EVERY resume pays the slow path: open and
    /// buffer at byte 0, play from the start, wait for a tick, seek, then buffer again at the real
    /// offset. That is two buffering cycles and a visible jump, and it would explain "resume is not
    /// instant" exactly. This measures it instead of assuming it.
    static var resumeProbeEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-resumeProbe")
    }

    /// Stamp one moment in the resume timeline, relative to the load that started it.
    func resumeProbe(_ event: String) {
        guard Self.resumeProbeEnabled else { return }
        let now = Date().timeIntervalSince1970
        if resumeProbeStart == 0 { resumeProbeStart = now }
        print(String(format: "[resume] %+6.2fs %@ | target=%@ pos=%@ seekIssued=%@ rendered=%@",
                     now - resumeProbeStart, event, Self.t(resumeTarget), Self.t(position),
                     resumeSeekIssued ? "Y" : "N", hasRenderedFrame ? "Y" : "N"))
    }

    /// Fire once, a few seconds after the first frame, so the measurement is of a settled stream
    /// rather than of the opening buffer.
    func startSeekProbeIfRequested() {
        guard !seekProbeStarted else { return }
        if let hold = Self.scanProbeHold { seekProbeStarted = true; runScanProbe(holding: hold); return }
        if let spec = Self.skipProbeSpec { seekProbeStarted = true; runSkipProbe(spec); return }
        guard let target = Self.seekProbeTarget else { return }
        seekProbeStarted = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self else { return }
            // How fast does VLCKit actually report time? The give-up window is counted in ticks,
            // so this number is what converts it into seconds.
            let before = self.debugTickCount
            try? await Task.sleep(for: .seconds(4))
            let rate = Double(self.debugTickCount - before) / 4.0
            print(String(format: "[seek] tick rate %.1f/s → the %d-tick give-up window is %.1fs",
                         rate, self.pendingSeekGraceTicks, Double(self.pendingSeekGraceTicks) / max(rate, 0.001)))

            let from = self.position
            print("[seek] settled at \(Self.t(from)) — asking for \(Self.t(target))")
            self.scrub(to: target)

            // Sample rather than wait for one "landed" moment: the interesting failures are a
            // playhead that arrives somewhere else, and one that arrives and then slides.
            var elapsed = 0.0
            for mark in [1.0, 2.0, 3.0, 5.0, 8.0, 12.0, 20.0] {
                try? await Task.sleep(for: .seconds(mark - elapsed))
                elapsed = mark
                let drift = self.position - target
                print("[seek] +\(Int(mark))s position=\(Self.t(self.position)) "
                    + "drift=\(String(format: "%+.1f", drift))s "
                    + "buffering=\(self.isBuffering) phase=\(self.phase)")
            }
        }
    }

    /// Hold a forward scan for `hold` seconds, release, then watch where it settles.
    private func runScanProbe(holding hold: Double) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self else { return }
            let from = self.position
            print("[scan] settled at \(Self.t(from)) — holding forward for \(hold)s")
            self.beginScan(direction: 1)
            try? await Task.sleep(for: .seconds(hold))
            let shown = self.position
            self.endScan()
            print("[scan] released — bar shows \(Self.t(shown)) "
                + "(travelled \(Self.t(shown - from)))")

            var elapsed = 0.0
            for mark in [1.0, 2.0, 3.0, 5.0, 8.0, 12.0, 20.0] {
                try? await Task.sleep(for: .seconds(mark - elapsed))
                elapsed = mark
                // Against the position the BAR promised on release: that is what the viewer was
                // aiming at, and "it doesn't drop you off at that point" is this number being big.
                let missed = self.position - shown
                print("[scan] +\(Int(mark))s position=\(Self.t(self.position)) "
                    + "vs-released=\(String(format: "%+.1f", missed))s "
                    + "buffering=\(self.isBuffering) phase=\(self.phase)")
            }
        }
    }

    /// `-autoSkips "10,-10,30,10x4,@1965"`: the skips a viewer actually makes, in order. `10` is one
    /// tap forward, `-10` one back, `10x4` four taps 0.28s apart (the cadence on the iPad's log),
    /// and `@1965` a scrub straight to 32:45 — how a run reaches the stretch of a file a report
    /// was about.
    ///
    /// Exists to A/B libvlc's read-ahead (`-prefetchKiB` / `-prefetchThreshold`) on the same file
    /// with the same inputs. The latency printed here is coarse — landing is only noticed on a
    /// time tick, about one a second — so the figures to compare are libvlc's own, in vlc.log:
    /// `[seret] seek` → `seek: preroll{ req` (the network part) → `Stream buffering done`.
    static var skipProbeSpec: [(delta: Double, taps: Int, absolute: Bool)]? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-autoSkips"), i + 1 < args.count else { return nil }
        let steps = args[i + 1].split(separator: ",").compactMap { token -> (Double, Int, Bool)? in
            if token.hasPrefix("@") { return Double(token.dropFirst()).map { ($0, 1, true) } }
            let parts = token.split(separator: "x")
            guard let delta = Double(parts[0]) else { return nil }
            return (delta, parts.count > 1 ? Int(parts[1]) ?? 1 : 1, false)
        }
        return steps.isEmpty ? nil : steps
    }

    private func runSkipProbe(_ steps: [(delta: Double, taps: Int, absolute: Bool)]) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))      // a settled stream, as a viewer would have
            for step in steps {
                guard let self else { return }
                let label = step.absolute ? "@\(Int(step.delta))"
                    : step.taps > 1 ? "\(Int(step.delta))x\(step.taps)" : "\(Int(step.delta))"
                print("[skips] \(label) from \(Self.t(self.position))")
                if step.absolute { self.scrub(to: step.delta) }
                for tap in 0..<(step.absolute ? 0 : step.taps) {
                    if tap > 0 { try? await Task.sleep(for: .milliseconds(280)) }
                    self.skip(step.delta)
                }
                let tapped = Date()
                var landed = false
                for _ in 0..<400 {                           // up to 40s
                    try? await Task.sleep(for: .milliseconds(100))
                    if self.pendingSeek == nil, !self.isBuffering, self.phase == .playing {
                        landed = true; break
                    }
                }
                print(String(format: "[skips] %@ %@ after %.1fs at %@", label,
                             landed ? "landed" : "NOT landed", Date().timeIntervalSince(tapped),
                             Self.t(self.position)))
                try? await Task.sleep(for: .seconds(8))      // watch a while before the next skip
            }
            print("[skips] done")
        }
    }

    private static func t(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
#endif
