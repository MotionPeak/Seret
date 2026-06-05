import Foundation
@testable import DebridUI
import DebridCore

// MARK: - FakeVideoPlayerEngine

@MainActor
final class FakeVideoPlayerEngine: VideoPlayerEngine {
    private(set) var loadedURL: URL?
    private(set) var seekedTo: Double?
    private(set) var rateSet: Double = 1
    private(set) var playCalled = false
    private(set) var stopCalled = false
    private(set) var addedSubtitles: [URL] = []
    private(set) var selectedSubtitleID: String??

    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []

    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    init() {
        var c: AsyncStream<PlaybackEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
    }
    func emit(_ e: PlaybackEvent) { continuation.yield(e) }

    func load(url: URL, headers: [String: String]) { loadedURL = url }
    func play() { playCalled = true }
    func pause() {}
    func stop() { stopCalled = true; continuation.finish() }
    func seek(to seconds: Double) { seekedTo = seconds }
    func setRate(_ rate: Double) { rateSet = rate }
    func selectAudioTrack(id: String?) {}
    func selectSubtitleTrack(id: String?) { selectedSubtitleID = id }
    func addExternalSubtitle(url: URL) { addedSubtitles.append(url) }
}

// MARK: - FakeSubtitleProvider

final class FakeSubtitleProvider: SubtitleProvider, @unchecked Sendable {
    var searchResults: [SubtitleResult] = []
    var searchError: Error?
    var downloadError: Error?
    var downloadedURL = URL(fileURLWithPath: "/tmp/sub.srt")
    private(set) var searchedLanguages: [[String]] = []

    func search(_ query: SubtitleQuery, languages: [String]) async throws -> [SubtitleResult] {
        searchedLanguages.append(languages)
        if let searchError { throw searchError }
        return searchResults
    }
    func download(_ result: SubtitleResult) async throws -> URL {
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
    static func movie(sources: [MediaSource]) -> MediaItem {
        MediaItem(id: "m1", kind: .movie, title: "Dune: Part Two", year: 2024,
                  sources: sources, seasons: [], tmdbID: 693134)
    }
    static func request(resumeAt: Double? = nil, sources: [MediaSource]? = nil) -> PlaybackRequest {
        let srcs = sources ?? [movieSource()]
        return PlaybackRequest(item: movie(sources: srcs), source: srcs[0],
                               resumeAt: resumeAt, label: "Dune: Part Two", contentKey: "m1")
    }
}
