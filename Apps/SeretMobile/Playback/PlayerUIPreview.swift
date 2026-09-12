#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// DEBUG-only visual harness for the player's subtitle surfaces, mirroring SeretTV's
/// `PlayerUIPreview`.
///
/// Reaching the real sheet means signing in to Real-Debrid and playing something, and RD throttles
/// its device-code endpoint hard enough that re-authenticating a simulator is not a thing to do
/// casually — so this boots straight to the sheet with a `PlayerModel` driven through the actual
/// download → attach → select path on a stub engine.
///
/// Launch with `-uiPreview <target>`:
///   - `playbacksheet`   — the playback sheet after Hebrew has been asked for and attached
///   - `subtitlebrowser` — the ranked search browser
///
///     xcrun simctl launch <udid> com.solomons.seret.mobile -uiPreview playbacksheet
///
/// Not compiled into release builds.
struct PlayerUIPreview: View {
    let target: String
    @State private var driver = MobileSubtitlePreviewDriver()

    var body: some View {
        Group {
            switch target {
            case "subtitlebrowser":
                // Tinted here because in the app the browser is pushed INSIDE the settings sheet,
                // which sets the gold tint — an untinted harness screenshot would show system blue
                // and misrepresent it.
                NavigationStack { MobileSubtitleBrowser(model: driver.model) }
                    .tint(Theme.Palette.gold)
                    .task { await driver.primeAndSearch() }
            default:
                PlayerSettingsSheet(model: driver.model)
                    .task { await driver.primeWithTracks() }
            }
        }
        // RootView sets this app-wide; the harness bypasses RootView, so without it these
        // screenshots render light and misrepresent how the sheet actually looks.
        .preferredColorScheme(.dark)
    }
}

/// Drives a `PlayerModel` wired to a canned subtitle provider and a stub engine.
@MainActor
@Observable
final class MobileSubtitlePreviewDriver {
    let engine = MobilePreviewEngine()
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
                            recordProgress: { _, _, _, _ in },
                            subtitles: MobilePreviewSubtitleProvider())
    }

    /// Play, then ask for Hebrew exactly as a tap on the chip does — so the sheet shows the real
    /// outcome of the whole path, not a hand-placed track that flatters it.
    ///
    /// The embedded Hebrew is a `bdpg` bitmap on purpose: that is the shape of the release the
    /// report came from, and the track the language preference used to take the selection back to.
    func primeWithTracks() async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.emit(.time(.init(position: 2480, duration: 7784)))
        engine.audioTracks = [
            MediaTrack(id: "audio/0", kind: .audio, name: "English", language: "en", codec: "a52 "),
            MediaTrack(id: "audio/1", kind: .audio, name: "Français", language: "fr", codec: "a52 "),
        ]
        engine.subtitleTracks = [
            MediaTrack(id: "spu/0", kind: .subtitle, name: "English SDH", language: "en", codec: "subt"),
            MediaTrack(id: "spu/1", kind: .subtitle, name: "Français", language: "fr", codec: "subt"),
            MediaTrack(id: "spu/2", kind: .subtitle, name: "עברית", language: "he", codec: "bdpg"),
        ]
        engine.emit(.tracksChanged)
        try? await Task.sleep(for: .milliseconds(30))
        await model.requestSubtitle(language: "he")
        try? await Task.sleep(for: .milliseconds(30))
    }

    func primeAndSearch() async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.emit(.time(.init(position: 2480, duration: 7784)))
        try? await Task.sleep(for: .milliseconds(30))
        await model.searchSubtitles(language: "he")
    }
}

/// A fixed, ranking-friendly Hebrew set: one exact file-hash match (perfect), one same-resolution
/// BluRay at the wrong rate, one poor CAM rip.
struct MobilePreviewSubtitleProvider: SubtitleProvider {
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
    func download(_ result: SubtitleResult) async throws -> URL {
        URL(fileURLWithPath: "/tmp/he-\(result.fileID).srt")
    }
}

/// A no-op engine that relays emitted events — enough to drive the read-only overlay state, plus
/// the one behaviour the subtitle path genuinely depends on (below).
@MainActor
final class MobilePreviewEngine: VideoPlayerEngine {
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

    func load(url: URL, headers: [String: String], audioLanguage: String?,
              audioTrackID: String?) {}
    func play() {}
    func pause() {}
    func stop() { continuation.finish() }
    func seek(to seconds: Double) {}
    func setRate(_ rate: Double) {}
    func selectAudioTrack(id: String?) {}
    func selectSubtitleTrack(id: String?) {}

    /// Surface a slave the way VLCKit does — named "Track 3", with NO language, and never twice for
    /// the same URL. Both of those are load-bearing: the missing language is why the preference
    /// could not see a downloaded subtitle, and the URL keying is why asking twice used to hang.
    func addExternalSubtitle(url: URL) {
        guard !attachedSubtitleURLs.contains(url) else { return }
        attachedSubtitleURLs.append(url)
        subtitleTracks.append(MediaTrack(id: "ext/\(attachedSubtitleURLs.count)", kind: .subtitle,
                                         name: "Track \(subtitleTracks.count + 1)",
                                         language: nil, isExternal: true, codec: "subt"))
        emit(.tracksChanged)
    }
    private var attachedSubtitleURLs: [URL] = []
}
#endif
