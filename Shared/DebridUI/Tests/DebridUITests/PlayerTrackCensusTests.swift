import Testing
import Foundation
@testable import DebridUI
import DebridCore

@MainActor
@Suite struct PlayerTrackCensusTests {
    final class Recorded: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [(MediaSource, [MediaTrack])] = []
        func add(_ source: MediaSource, _ tracks: [MediaTrack]) { lock.lock(); calls.append((source, tracks)); lock.unlock() }
        var all: [(MediaSource, [MediaTrack])] { lock.lock(); defer { lock.unlock() }; return calls }
    }

    private func model(_ engine: FakeVideoPlayerEngine, recorded: Recorded) -> PlayerModel {
        PlayerModel(request: Fixture.request(sources: [Fixture.movieSource()]), engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _, _ in }, subtitles: nil,
                    recordTracks: { source, tracks in recorded.add(source, tracks) })
    }

    @Test func theFilesOwnTracksAreRecordedOncePerChange() async {
        let engine = FakeVideoPlayerEngine()
        engine.audioTracks = [MediaTrack(id: "audio/1", kind: .audio, name: "English", language: "en", codec: "a52 ")]
        engine.subtitleTracks = [MediaTrack(id: "spu/3", kind: .subtitle, name: "עברית", language: "he", codec: "subt")]
        let recorded = Recorded()
        let m = model(engine, recorded: recorded)
        m.start()
        engine.emit(.tracksChanged)
        engine.emit(.tracksChanged)
        await m.waitForIdleForTesting()
        #expect(await hebrewEventually { recorded.all.count == 1 })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(recorded.all.count == 1)
        #expect(recorded.all.first?.0 == Fixture.movieSource())
        #expect(recorded.all.first?.1.map(\.id) == ["audio/1", "spu/3"])
    }

    @Test func aDownloadedSubtitleIsNotReportedAsTheFiles() async {
        let engine = FakeVideoPlayerEngine()
        engine.audioTracks = [MediaTrack(id: "audio/1", kind: .audio, name: "English", language: "en")]
        engine.subtitleTracks = [MediaTrack(id: "h/spu/0", kind: .subtitle, name: "Track 1", isExternal: true)]
        let recorded = Recorded()
        let m = model(engine, recorded: recorded)
        m.start()
        engine.emit(.tracksChanged)
        await m.waitForIdleForTesting()
        #expect(await hebrewEventually { recorded.all.count == 1 })
        #expect(recorded.all.first?.1.map(\.id) == ["audio/1"])
    }
}
