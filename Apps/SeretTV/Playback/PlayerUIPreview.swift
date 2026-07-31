#if DEBUG
import SwiftUI
import DebridUI
import DebridCore

/// DEBUG-only visual harnesses for player overlays. The tvOS simulator accepts no reliable
/// synthesized input, so the live player screen can't be driven there; these boot straight to a
/// target view so its layout can be screenshot-verified.
///
/// Launch with `-uiPreview <target>`, where target is:
///   - `scrubbar`  — the transport bar in each of its states
///   - `settings`  — the playback settings panel with grouped subtitle tracks
///   - `subtitles` — the full subtitle browser with ranked, badged results
///
/// Not compiled into release builds.
struct PlayerUIPreview: View {
    let target: String

    var body: some View {
        switch target {
        case "settings":   SettingsPanelPreview()
        case "subtitles":  SubtitleBrowserPreview()
        case "inputprobe": InputProbePreview()
        default:           ScrubBarPreview()
        }
    }
}

// MARK: - Scrub bar

/// Boots straight to `ScrubBar` in each of its states so its layout can be screenshot-verified.
private struct ScrubBarPreview: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 90) {
                labelled("At rest — 3pt hairline, play-dot handle") { m in }
                labelled("Buffering — inline spinner") { m in m.driveBuffering() }
                labelled("Paused — pause affordance at rest") { m in m.drivePaused() }
                labelled("Scrubbing — slab, thick track, play-mark handle, floating time") { m in
                    m.driveScrubbing()
                }
            }
            .padding(.horizontal, 90)
        }
    }

    private func labelled(_ title: String,
                          drive: @escaping (PreviewDriver) -> Void) -> some View {
        PreviewBarRow(title: title, drive: drive)
    }
}

/// One driven bar plus its caption.
private struct PreviewBarRow: View {
    let title: String
    let drive: (PreviewDriver) -> Void
    @State private var driver = PreviewDriver()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.callout).foregroundStyle(Theme.Palette.textSecondary)
            ScrubBar(model: driver.model, buffering: driver.buffering)
        }
        .task { await driver.prime(); drive(driver) }
    }
}

/// Builds a `PlayerModel` on a stub engine and drives it into a target state for the harness.
@MainActor
@Observable
final class PreviewDriver {
    let engine = PreviewEngine()
    let model: PlayerModel
    private(set) var buffering = false

    init() {
        let source = MediaSource(torrentID: "t", fileID: nil, restrictedLink: "rd://x",
                                 parsed: ParsedRelease(title: "Dune Part Two"))
        let item = MediaItem(id: "m", kind: .movie, title: "Dune: Part Two", year: 2024,
                             sources: [source], seasons: [], tmdbID: 693134)
        let request = PlaybackRequest(item: item, source: source, resumeAt: nil,
                                      label: "Dune: Part Two", contentKey: "m")
        model = PlayerModel(request: request, engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _ in }, subtitles: nil)
    }

    /// Bring the model to a live, rendered, playing state at ~41 minutes of a 2h9m film.
    func prime() async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.emit(.time(.init(position: 2480, duration: 7784)))
        engine.emit(.time(.init(position: 2481, duration: 7784)))
        try? await Task.sleep(for: .milliseconds(50))
    }

    func driveBuffering() { buffering = true }

    func drivePaused() {
        engine.emit(.state(.paused))
    }

    func driveScrubbing() {
        model.beginScrub()
        model.updateScrub(by: 1600)   // glide the target well ahead of the playhead
    }
}

// MARK: - Input probe

/// Mounts a bare `PlayerInputSurface` over black with the probe HUD on top — no sign-in, no stream,
/// no library. That matters: it makes the remote-input question answerable on a signed-out device
/// or a fresh simulator, and it isolates the surface from every other thing that could swallow
/// input. Launch with `-uiPreview inputprobe -inputHUD`.
private struct InputProbePreview: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerInputSurface(
                isActive: true,
                onTouchDown: {}, onTouchUp: {},
                onScrubBegan: {}, onScrubMoved: { _ in },
                onScrubEnded: {}, onScrubCancelled: {},
                onSkip: { _ in }, onSelect: {}, onUp: {}, onDown: {},
                onScanBegan: { _ in }, onScanEnded: {}
            )
            .ignoresSafeArea()
            InputProbeHUD()
        }
    }
}

// MARK: - Subtitle panel + browser

/// The playback settings panel with muxed tracks grouped apart from downloaded ones.
private struct SettingsPanelPreview: View {
    @State private var driver = SubtitlePreviewDriver()
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SettingsPanel(model: driver.model, onSearchSubtitles: {}, onClose: {})
        }
        .task { await driver.primeWithTracks() }
    }
}

/// The full subtitle browser with ranked, badged Hebrew results (an exact hash match sorts first).
private struct SubtitleBrowserPreview: View {
    @State private var driver = SubtitlePreviewDriver()
    var body: some View {
        SubtitleBrowser(model: driver.model, onClose: {})
            .task { await driver.primeAndSearch() }
    }
}

/// Drives a `PlayerModel` wired to a canned subtitle provider for the panel/browser harnesses.
@MainActor
@Observable
final class SubtitlePreviewDriver {
    let engine = PreviewEngine()
    let model: PlayerModel

    init() {
        let source = MediaSource(torrentID: "t", fileID: nil, restrictedLink: "rd://x",
                                 parsed: ParsedRelease(title: "Dune Part Two", year: 2024,
                                                       resolution: "2160p", source: "WEB-DL",
                                                       videoCodec: "H265", releaseGroup: "FLUX"))
        let item = MediaItem(id: "m", kind: .movie, title: "Dune: Part Two", year: 2024,
                             sources: [source], seasons: [], tmdbID: 693134)
        let request = PlaybackRequest(item: item, source: source, resumeAt: nil,
                                      label: "Dune: Part Two", contentKey: "m")
        model = PlayerModel(request: request, engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _ in }, subtitles: PreviewSubtitleProvider())
    }

    /// Play, then run a Hebrew search so the browser shows ranked rows.
    func primeAndSearch() async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.emit(.time(.init(position: 2480, duration: 7784)))
        try? await Task.sleep(for: .milliseconds(30))
        await model.searchSubtitles(language: "he")
    }

    /// Play, then surface a mix of embedded and downloaded tracks so the panel shows both groups.
    func primeWithTracks() async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.emit(.time(.init(position: 2480, duration: 7784)))
        engine.subtitleTracks = [
            MediaTrack(id: "spu/0", kind: .subtitle, name: "English SDH", language: "en"),
            MediaTrack(id: "spu/1", kind: .subtitle, name: "Français", language: "fr"),
            MediaTrack(id: "ext/1", kind: .subtitle, name: "Hebrew", language: "he", isExternal: true),
        ]
        engine.emit(.tracksChanged)
        try? await Task.sleep(for: .milliseconds(30))
    }
}

/// A subtitle provider that returns a fixed, ranking-friendly Hebrew set for the harness — one exact
/// file-hash match (perfect), one same-resolution BluRay (uncertain source), one poor CAM rip.
struct PreviewSubtitleProvider: SubtitleProvider {
    func search(_ query: SubtitleQuery, languages: [String]) async throws -> [SubtitleResult] {
        [
            SubtitleResult(fileID: 1, language: "he",
                           release: "Dune.Part.Two.2024.2160p.WEB-DL.H265-FLUX",
                           downloadCount: 240, fps: 23.976, moviehashMatch: true, uploader: "syncer"),
            SubtitleResult(fileID: 2, language: "he",
                           release: "Dune.Part.Two.2024.1080p.BluRay.x264-SPARKS",
                           downloadCount: 91_500, fps: 25.0, hearingImpaired: true, uploader: "subber"),
            SubtitleResult(fileID: 3, language: "he",
                           release: "Dune2.CAM.HEBSUB", downloadCount: 4_200, uploader: "anon"),
        ]
    }
    func download(_ result: SubtitleResult) async throws -> URL { URL(fileURLWithPath: "/tmp/he.srt") }
}

// MARK: - Stub engine

/// A no-op engine that just relays emitted events — enough to drive the read-only overlay state.
@MainActor
final class PreviewEngine: VideoPlayerEngine {
    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []
    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    init() {
        var c: AsyncStream<PlaybackEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
    }
    func emit(_ event: PlaybackEvent) { continuation.yield(event) }

    func load(url: URL, headers: [String: String]) {}
    func play() {}
    func pause() {}
    func stop() { continuation.finish() }
    func seek(to seconds: Double) {}
    func setRate(_ rate: Double) {}
    func selectAudioTrack(id: String?) {}
    func selectSubtitleTrack(id: String?) {}
    func addExternalSubtitle(url: URL) {}
}
#endif
