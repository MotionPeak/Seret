import Testing
import Foundation
@testable import DebridCore

@MainActor
final class MockPlayerEngine: VideoPlayerEngine {
    private(set) var loaded: (url: URL, headers: [String: String])?
    private(set) var didPlay = false
    private(set) var didPause = false
    private(set) var didStop = false
    private(set) var seekedTo: Double?
    private(set) var selectedAudioID: String?
    private(set) var selectedSubtitleID: String?
    private(set) var externalSubtitle: URL?
    private(set) var rate: Double?
    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []

    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    init() {
        var c: AsyncStream<PlaybackEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
    }

    func load(url: URL, headers: [String: String]) { loaded = (url, headers) }
    func play() { didPlay = true; continuation.yield(.state(.playing)) }
    func pause() { didPause = true }
    func stop() { didStop = true; continuation.finish() }
    func seek(to seconds: Double) { seekedTo = seconds }
    func setRate(_ rate: Double) { self.rate = rate }
    func selectAudioTrack(id: String?) { selectedAudioID = id }
    func selectSubtitleTrack(id: String?) { selectedSubtitleID = id }
    func addExternalSubtitle(url: URL) { externalSubtitle = url }
}

@Suite @MainActor struct VideoPlayerEngineTests {
    @Test func conformerRecordsControlCallsAndEmitsEvents() async {
        let engine = MockPlayerEngine()
        engine.subtitleTracks = [MediaTrack(id: "s1", kind: .subtitle, name: "Hebrew", language: "he")]

        engine.load(url: URL(string: "https://rd/x.mkv")!, headers: ["Authorization": "Bearer T"])
        engine.seek(to: 42)
        engine.selectSubtitleTrack(id: "s1")
        engine.addExternalSubtitle(url: URL(fileURLWithPath: "/tmp/x.srt"))
        engine.play()

        #expect(engine.loaded?.url.absoluteString == "https://rd/x.mkv")
        #expect(engine.loaded?.headers["Authorization"] == "Bearer T")
        #expect(engine.seekedTo == 42)
        #expect(engine.selectedSubtitleID == "s1")
        #expect(engine.externalSubtitle?.path == "/tmp/x.srt")
        #expect(engine.subtitleTracks.first?.language == "he")
        #expect(engine.didPlay == true)

        // the protocol's event stream delivers what the engine emitted (buffered before consumption)
        var first: PlaybackEvent?
        for await event in engine.events { first = event; break }
        #expect(first == .state(.playing))
    }
}
