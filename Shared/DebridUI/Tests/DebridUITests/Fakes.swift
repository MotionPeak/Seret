import Foundation
@testable import DebridUI
import DebridCore

// MARK: - FakeVideoPlayerEngine

@MainActor
final class FakeVideoPlayerEngine: VideoPlayerEngine, EventCountingEngineForTesting {
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
    /// What the engine answers when asked for the time directly, as opposed to the position the
    /// model last received from an event. Nil models an engine that cannot answer.
    var preciseTime: Double?
    func setSubtitleDelay(_ seconds: Double) { subtitleDelays.append(seconds) }

    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    init() {
        var c: AsyncStream<PlaybackEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
    }
    /// Every event handed to the model, counted so `waitForIdleForTesting` can wait until the
    /// model has HANDLED them rather than sleeping for a fixed 20ms and hoping.
    private(set) var yieldedEventCount = 0
    func emit(_ e: PlaybackEvent) { yieldedEventCount += 1; continuation.yield(e) }

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
        // libvlc keys a playback slave by URL: one it already holds is not added again, and NO new
        // track appears. Modelled, because the app's attach handshake waits for a newcomer — and
        // a wait that can never end is exactly how a second ask for an already-attached language
        // timed out into "not found".
        let known = addedSubtitles.contains(url)
        addedSubtitles.append(url)
        guard !deferSlaveAttach, !known else { return }
        // Simulate VLCKit surfacing the external sub as a new, generically-named slave track.
        slaveCount += 1
        subtitleTracks.append(MediaTrack(id: "ext/\(slaveCount)", kind: .subtitle,
                                         name: "Track \(subtitleTracks.count + 1)", language: nil,
                                         isExternal: true))
    }
    private var slaveCount = 0
}

// MARK: - FakeTrackPreferences

@MainActor
final class FakeTrackPreferences: TrackPreferenceStoring {
    var preferredAudio: TrackChoice
    var preferredSubtitle: TrackChoice
    /// Per-FILE remembered audio track, keyed by `WatchKey.source`.
    var recordedTrackIDs: [String: String] = [:]
    /// Per-FILE, per-SUBTITLE remembered offset, keyed `"<sourceKey>|<subtitle file name>"`.
    var recordedSubtitleDelays: [String: Double] = [:]
    func subtitleDelay(forSource sourceKey: String, subtitle: String) -> Double? {
        recordedSubtitleDelays["\(sourceKey)|\(subtitle)"]
    }
    func record(subtitleDelay: Double, forSource sourceKey: String, subtitle: String) {
        let key = "\(sourceKey)|\(subtitle)"
        if subtitleDelay == 0 { recordedSubtitleDelays[key] = nil }
        else { recordedSubtitleDelays[key] = subtitleDelay }
    }

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
    /// Unique per provider instance, because the file is REAL and the suites run in parallel.
    ///
    /// Every test in this package searches with `fileID: 1`, so a name keyed by the file id alone
    /// was one shared file on disk for the whole package: one test wrote its subtitle text while
    /// another read it back through `prepareSubtitle`, and the model under test got a stranger's
    /// cues. That is what made the auto-sync suite fail a different assertion on every other run.
    private let instanceID = UUID().uuidString
    lazy var downloadedURL = FileManager.default.temporaryDirectory
        .appending(path: "fake-sub-\(instanceID).srt")
    private(set) var searchedLanguages: [[String]] = []
    private(set) var searchedQueries: [SubtitleQuery] = []

    func search(_ query: SubtitleQuery, languages: [String]) async throws -> [SubtitleResult] {
        searchedLanguages.append(languages)
        searchedQueries.append(query)
        if let searchError { throw searchError }
        return searchResults
    }
    private(set) var downloadedResults: [SubtitleResult] = []

    /// Real SRT text to write at `downloadedURL`, for tests that read the file back (auto-sync
    /// correlates against the cue times, so an empty placeholder file proves nothing).
    var downloadedText: String?

    func download(_ result: SubtitleResult) async throws -> URL {
        downloadedResults.append(result)
        if let downloadError { throw downloadError }
        if let downloadedText {
            let url = FileManager.default.temporaryDirectory
                .appending(path: "fake-sub-\(instanceID)-\(result.fileID).srt")
            try? Data(downloadedText.utf8).write(to: url)
            return url
        }
        return downloadedURL
    }
}

// MARK: - FakeAudioProbe

@MainActor
final class FakeAudioProbe: AudioLoudnessProbing {
    /// Builds the window it is ASKED for. A fake that returned a fixed array regardless would
    /// describe a different part of the film than the cues it is matched against, and "measured a
    /// 420s offset" would be the fixture talking, not the code.
    private let generate: (_ from: Double, _ seconds: Double) -> (mix: [Float], centre: [Float])
    private(set) var requests: [(url: URL, from: Double, seconds: Double)] = []
    private(set) var cancelled = false

    init(generate: @escaping (_ from: Double, _ seconds: Double) -> (mix: [Float], centre: [Float])) {
        self.generate = generate
    }
    /// Loudness only, no centre channel — the stereo/unknown-layout path.
    convenience init(loudnessOnly: @escaping (_ from: Double, _ seconds: Double) -> [Float]) {
        self.init { from, seconds in (loudnessOnly(from, seconds), []) }
    }
    /// A probe that decodes nothing — a dead link, a container the decoder will not open.
    static var silent: FakeAudioProbe { FakeAudioProbe { _, _ in ([], []) } }

    /// Dialogue at these absolute times, each `length` long, in the CENTRE channel — plus, when
    /// asked, loud wide effects BETWEEN the lines. That combination is the one that defeated a
    /// loudness envelope on a real film: the loudest moments are the ones with no subtitle.
    static func speaking(at times: [Double], length: Double = 3,
                         effectsBetween: Bool = false) -> FakeAudioProbe {
        FakeAudioProbe { from, seconds in
            let frames = Int(seconds / 0.1)
            var centre = [Float](repeating: 0.01, count: frames)
            var mix = [Float](repeating: 0.02, count: frames)
            for t in times {
                let first = Int((t - from) / 0.1)
                let last = first + Int(length / 0.1)
                guard first < frames, last > 0 else { continue }
                for f in max(0, first)..<min(last, frames) {
                    centre[f] = 0.30                     // quiet dialogue, centred
                    mix[f] = 0.33
                }
            }
            if effectsBetween {
                for f in 0..<frames where centre[f] < 0.1 {
                    centre[f] = 0.40                     // loud, and everywhere
                    mix[f] = 2.40
                }
            }
            return (mix, centre)
        }
    }

    func loudness(url: URL, from startSeconds: Double, seconds: Double) async -> LoudnessWindow? {
        requests.append((url, startSeconds, seconds))
        let (mix, centre) = generate(startSeconds, seconds)
        guard !mix.isEmpty else { return nil }
        return LoudnessWindow(frames: mix, centre: centre, startSeconds: startSeconds)
    }
    func cancel() { cancelled = true }
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
