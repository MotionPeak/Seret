import Foundation
@testable import DebridUI
import DebridCore

// MARK: - FakeVideoPlayerEngine

@MainActor
final class FakeVideoPlayerEngine: VideoPlayerEngine {
    private(set) var loadedURL: URL?
    private(set) var seekedTo: Double?
    /// Every seek in order — coalescing tests assert on the full history, not just the last.
    private(set) var seeks: [Double] = []
    private(set) var rateSet: Double = 1
    /// Every volume set in order — re-application tests assert on the full history.
    private(set) var volumesSet: [Int] = []
    private(set) var playCalled = false
    private(set) var stopCalled = false
    private(set) var addedSubtitles: [URL] = []
    /// Every subtitle offset set, in order — reset/re-assert tests assert on the whole history.
    private(set) var subtitleDelays: [Double] = []
    private(set) var selectedSubtitleID: String??
    private(set) var selectedAudioID: String??

    /// The audio language passed at load — asserted by the "no mid-playback switch" tests.
    private(set) var loadedAudioLanguage: String?
    /// The audio TRACK named at load, when the file has been played before.
    private(set) var loadedAudioTrackID: String?
    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []
    /// What the engine reports as the video's frame rate — drives subtitle fps matching.
    var videoFPS: Double?
    func setSubtitleDelay(_ seconds: Double) { subtitleDelays.append(seconds) }

    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    init() {
        var c: AsyncStream<PlaybackEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
    }
    func emit(_ e: PlaybackEvent) { continuation.yield(e) }

    func load(url: URL, headers: [String: String], audioLanguage: String?,
              audioTrackID: String?) {
        loadedURL = url
        loadedAudioLanguage = audioLanguage
        loadedAudioTrackID = audioTrackID
    }
    func play() { playCalled = true }
    func pause() {}
    func stop() { stopCalled = true; continuation.finish() }
    func seek(to seconds: Double) { seekedTo = seconds; seeks.append(seconds) }
    func setRate(_ rate: Double) { rateSet = rate }
    func setVolume(_ percent: Int) { volumesSet.append(percent) }
    func selectAudioTrack(id: String?) { selectedAudioID = id }
    func selectSubtitleTrack(id: String?) { selectedSubtitleID = id }
    /// Forget what was last selected, so a test can prove a second pass does NOT re-issue it.
    func clearSubtitleSelection() { selectedSubtitleID = nil }
    /// When true, `addExternalSubtitle` records the URL but does NOT surface a track — the test
    /// drives the track list itself, which is how VLCKit really behaves: the slave arrives later,
    /// and other tracks can finish parsing in the meantime.
    var deferSlaveAttach = false

    func addExternalSubtitle(url: URL) {
        addedSubtitles.append(url)
        guard !deferSlaveAttach else { return }
        // Simulate VLCKit surfacing the external sub as a new, generically-named slave track.
        subtitleTracks.append(MediaTrack(id: "ext/\(addedSubtitles.count)", kind: .subtitle,
                                         name: "Track \(subtitleTracks.count + 1)", language: nil,
                                         isExternal: true))
    }
}

// MARK: - FakeTrackPreferences

@MainActor
final class FakeTrackPreferences: TrackPreferenceStoring {
    var preferredAudio: TrackChoice
    var preferredSubtitle: TrackChoice
    /// Per-FILE remembered audio track, keyed by `WatchKey.source`.
    var recordedTrackIDs: [String: String] = [:]
    func audioTrackID(forSource sourceKey: String) -> String? { recordedTrackIDs[sourceKey] }
    func record(audioTrackID: String, forSource sourceKey: String) {
        recordedTrackIDs[sourceKey] = audioTrackID
    }
    init(audio: TrackChoice = .automatic, subtitle: TrackChoice = .automatic) {
        preferredAudio = audio
        preferredSubtitle = subtitle
    }
}

// MARK: - FakeSubtitleProvider

final class FakeSubtitleProvider: SubtitleProvider, @unchecked Sendable {
    var searchResults: [SubtitleResult] = []
    var searchError: Error?
    var downloadError: Error?
    var downloadedURL = URL(fileURLWithPath: "/tmp/sub.srt")
    private(set) var searchedLanguages: [[String]] = []
    private(set) var searchedQueries: [SubtitleQuery] = []

    func search(_ query: SubtitleQuery, languages: [String]) async throws -> [SubtitleResult] {
        searchedLanguages.append(languages)
        searchedQueries.append(query)
        if let searchError { throw searchError }
        return searchResults
    }
    private(set) var downloadedResults: [SubtitleResult] = []

    func download(_ result: SubtitleResult) async throws -> URL {
        downloadedResults.append(result)
        if let downloadError { throw downloadError }
        return downloadedURL
    }
}

// MARK: - Fixture helpers

@MainActor
enum Fixture {
    static func movieSource(_ link: String = "rd://link") -> MediaSource {
        MediaSource(torrentID: "t1", fileID: nil, restrictedLink: link,
                    parsed: ParsedRelease(title: "Dune", resolution: nil))
    }
    /// The `WatchKey.source` of the movie fixture — what a per-file preference is filed under.
    static var sourceKey: String { WatchKey.source(movieSource()) }

    static func movie(sources: [MediaSource]) -> MediaItem {
        MediaItem(id: "m1", kind: .movie, title: "Dune: Part Two", year: 2024,
                  sources: sources, seasons: [], tmdbID: 693134)
    }
    static func request(resumeAt: Double? = nil, sources: [MediaSource]? = nil,
                        fromStart: Bool = false) -> PlaybackRequest {
        let srcs = sources ?? [movieSource()]
        return PlaybackRequest(item: movie(sources: srcs), source: srcs[0],
                               resumeAt: resumeAt, label: "Dune: Part Two", contentKey: "m1",
                               fromStart: fromStart)
    }

    static func episodeSource(_ torrent: String) -> MediaSource {
        MediaSource(torrentID: torrent, fileID: nil, restrictedLink: "rd://\(torrent)",
                    parsed: ParsedRelease(title: "The Show", resolution: nil))
    }
    /// An n-episode show request currently playing the given episode number. Three or more is what
    /// it takes to tell "advanced once" from "advanced twice".
    static func showRequest(episodes: Int, playingEpisode number: Int) -> PlaybackRequest {
        let eps = (1...episodes).map { Episode(season: 1, number: $0, source: episodeSource("e\($0)")) }
        let item = MediaItem(id: "s1", kind: .show, title: "The Show", year: 2023,
                             sources: [], seasons: [Season(number: 1, episodes: eps)], tmdbID: 1399)
        let playing = eps[number - 1]
        return PlaybackRequest(item: item, source: playing.source, resumeAt: nil,
                               label: "The Show — S\(playing.season)·E\(playing.number)",
                               contentKey: WatchKey.content(forShow: item, episode: playing), episode: playing)
    }

    /// A two-episode show (S1E1, S1E2) request currently playing the given episode number.
    static func showRequest(playingEpisode number: Int = 1) -> PlaybackRequest {
        let ep1 = Episode(season: 1, number: 1, source: episodeSource("e1"))
        let ep2 = Episode(season: 1, number: 2, source: episodeSource("e2"))
        let item = MediaItem(id: "s1", kind: .show, title: "The Show", year: 2023,
                             sources: [], seasons: [Season(number: 1, episodes: [ep1, ep2])], tmdbID: 1399)
        let playing = number == 1 ? ep1 : ep2
        return PlaybackRequest(item: item, source: playing.source, resumeAt: nil,
                               label: "The Show — S\(playing.season)·E\(playing.number)",
                               contentKey: WatchKey.content(forShow: item, episode: playing), episode: playing)
    }
}
