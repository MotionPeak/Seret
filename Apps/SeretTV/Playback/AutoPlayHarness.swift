#if DEBUG
import SwiftUI
import DebridUI
import DebridCore

/// DEBUG-only: start playing a library title on launch, with no remote.
///
/// It exists to answer one question that only the device can answer — whether libvlc decodes this
/// library's HEVC in hardware (`videotoolbox`) or falls back to software (`avcodec`). The tvOS
/// simulator cannot: it reports "device doesn't support HEVC" and always falls back, so its answer
/// is an artifact of the simulator rather than a fact about the Apple TV.
///
/// A real Apple TV takes no synthesized input, so the usual way to get a stream playing is to hand
/// someone the remote. Pairing this with `-vlcLog` turns the whole measurement into one command:
///
///     xcrun devicectl device process launch --device <id> --console \
///         com.solomons.seret.tv -vlcLog -autoPlay
///
/// `-autoPlay` alone picks the heaviest thing in the library (2160p first, HEVC first) because that
/// is the class of file that stutters. `-autoPlay <n>` picks the n-th candidate instead, so a run
/// can be repeated against a different release without a rebuild.
///
/// Starts from zero deliberately — a resumed playhead would seek before the decoder settles and
/// muddy the first seconds of the log, which is exactly where the decoder is announced.
struct AutoPlayHarness: ViewModifier {
    let session: AppSession
    let index: Int

    @State private var request: PlaybackRequest?
    @State private var started = false

    /// `-autoMemory` runs the whole footprint timeline: idle, playing, and — the part that matters —
    /// after the player is dismissed.
    ///
    /// The device's memory-pressure logs show Seret at ~830 MB while tvOS kills daemons around it,
    /// and the claim that this is playback working set rather than a leak rests on a SIMULATOR
    /// measurement. The simulator is not where the memory pressure is happening. This measures
    /// `phys_footprint` — the exact number jetsam judges a process by — on the device.
    private var runsMemoryTimeline: Bool {
        ProcessInfo.processInfo.arguments.contains("-autoMemory")
    }

    func body(content: Content) -> some View {
        content
            .task(id: session.libraryStore?.movies.count ?? 0) { await startIfReady() }
            // `PlaybackRequest` is not Identifiable, so the cover is driven by a plain Bool over
            // the stored request rather than by `item:`.
            .fullScreenCover(isPresented: Binding(get: { request != nil },
                                                  set: { if !$0 { request = nil } })) {
                if let req = request {
                    PlayerHost(request: req, app: session, backdropSize: "original")
                        .environment(session)
                }
            }
    }

    private func startIfReady() async {
        guard !started, let store = session.libraryStore else { return }
        let candidates = Self.heaviestFirst(store.movies)
        guard !candidates.isEmpty else { return }     // library still loading — the task re-runs
        started = true
        let item = candidates[min(index, candidates.count - 1)]
        guard let source = item.sources.best else { return }
        print("[autoPlay] \(item.title) — \(Self.describe(source))")
        if runsMemoryTimeline {
            await runMemoryTimeline(item: item, source: source)
            return
        }
        request = PlaybackRequest(item: item, source: source, resumeAt: nil,
                                  label: item.title,
                                  contentKey: WatchKey.content(forMovie: item),
                                  episode: nil, fromStart: true)
    }

    /// idle → playing → dismissed, sampling the footprint throughout. The last phase is the whole
    /// point: if it settles back near the idle figure the memory is playback working set and the
    /// device is simply full; if it stays high, the player is not giving it back.
    private func runMemoryTimeline(item: MediaItem, source: MediaSource) async {
        await sample("idle", seconds: 20, every: 5)

        request = PlaybackRequest(item: item, source: source, resumeAt: nil,
                                  label: item.title,
                                  contentKey: WatchKey.content(forMovie: item),
                                  episode: nil, fromStart: true)
        await sample("playing", seconds: 60, every: 10)

        request = nil                       // dismisses the cover → PlayerView.onDisappear → teardown
        print("[mem] player dismissed")
        await sample("after-exit", seconds: 45, every: 5)
        print("[mem] done")
    }

    private func sample(_ phase: String, seconds: Int, every: Int) async {
        for t in stride(from: 0, through: seconds, by: every) {
            if t > 0 { try? await Task.sleep(for: .seconds(every)) }
            print(String(format: "[mem] %-11@ +%3ds  %6.0f MB", phase as NSString, t,
                         Self.footprintMB()))
        }
    }

    /// `phys_footprint`, in MB — the figure jetsam uses, not `resident_size`, which counts pages
    /// the kernel does not hold the app responsible for.
    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size
                                           / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1024 / 1024
    }

    /// Hardest to decode first: 2160p over anything else, then HEVC over AVC. The reported stutter
    /// is specific to big HEVC remuxes, so a harness that grabbed an arbitrary title would often
    /// measure the one class of file that was never the problem.
    static func heaviestFirst(_ movies: [MediaItem]) -> [MediaItem] {
        movies.filter { $0.sources.best != nil }.sorted { a, b in
            let (x, y) = (weight(a), weight(b))
            return x == y ? a.title < b.title : x > y
        }
    }

    private static func weight(_ item: MediaItem) -> Int {
        guard let parsed = item.sources.best?.parsed else { return 0 }
        let res = parsed.resolution?.lowercased() ?? ""
        let codec = parsed.videoCodec?.lowercased() ?? ""
        let isHEVC = codec.contains("265") || codec.contains("hevc")
        return (res.contains("2160") || res.contains("4k") ? 2 : 0) + (isHEVC ? 1 : 0)
    }

    private static func describe(_ s: MediaSource) -> String {
        [s.parsed.resolution, s.parsed.videoCodec, s.parsed.source]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
#endif
