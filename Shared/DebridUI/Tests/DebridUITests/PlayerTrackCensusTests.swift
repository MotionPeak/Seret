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
        await m.waitForIdleForTesting()
        engine.emit(.state(.playing))
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
        await m.waitForIdleForTesting()
        engine.emit(.state(.playing))
        await m.waitForIdleForTesting()
        #expect(await hebrewEventually { recorded.all.count == 1 })
        #expect(recorded.all.first?.1.map(\.id) == ["audio/1"])
    }

    /// Across an episode swap the engine still holds the OUTGOING file until the incoming one is
    /// resolved — seconds on a cold link — while the model already names the incoming source. A
    /// track change in that window (the old input tearing down, or still being parsed) was filed
    /// under the new episode, for good.
    @Test func anOutgoingFilesTracksAreNeverFiledUnderTheIncomingOne() async {
        let engine = FakeVideoPlayerEngine()
        engine.audioTracks = [MediaTrack(id: "audio/1", kind: .audio, name: "English", language: "en", codec: "a52 ")]
        let recorded = Recorded()
        let gate = Gate()
        let m = PlayerModel(request: Fixture.showRequest(episodes: 3, playingEpisode: 1), engine: engine,
                            unrestrict: { _ in
                                await gate.waitIfClosed()
                                return URL(string: "https://cdn/x.mkv")!
                            },
                            recordProgress: { _, _, _, _, _ in }, subtitles: nil,
                            recordTracks: { source, tracks in recorded.add(source, tracks) })
        m.start()
        await m.waitForIdleForTesting()
        engine.emit(.state(.playing))
        await m.waitForIdleForTesting()
        #expect(await hebrewEventually { recorded.all.count == 1 })
        let first = recorded.all.first?.0

        await gate.close()               // hold E2's unrestrict open: the engine stays on E1
        m.playNext()
        await m.waitForIdleWhileLoadIsHeldForTesting()
        engine.emit(.tracksChanged)
        await m.waitForIdleWhileLoadIsHeldForTesting()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(recorded.all.allSatisfy { $0.0 == first })
        await gate.open()

        // The positive control: once E2 is on screen, its own tracks ARE reported — so the silence
        // above was the gate, not a slow pipeline.
        await m.waitForIdleForTesting()
        engine.emit(.state(.playing))
        await m.waitForIdleForTesting()
        #expect(await hebrewEventually { recorded.all.contains { $0.0 != first } })
    }

    /// Loaded but not yet on screen: VLCKit is still discovering the file's streams, and a list
    /// read then can be partial. The census waits for the first frame.
    @Test func theCensusWaitsForTheFirstFrame() async {
        let engine = FakeVideoPlayerEngine()
        engine.audioTracks = [MediaTrack(id: "audio/1", kind: .audio, name: "English", language: "en", codec: "a52 ")]
        let recorded = Recorded()
        let m = model(engine, recorded: recorded)
        m.start()
        await m.waitForIdleForTesting()                  // loaded: the engine holds this source
        engine.emit(.tracksChanged)
        await m.waitForIdleForTesting()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(recorded.all.isEmpty)
        engine.emit(.state(.playing))
        await m.waitForIdleForTesting()
        #expect(await hebrewEventually { recorded.all.count == 1 })
    }

    /// Opens once and stays open; only the swap's load is held.
    actor Gate {
        private var closed = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func close() { closed = true }
        func open() {
            closed = false
            for w in waiters { w.resume() }
            waiters = []
        }
        func waitIfClosed() async {
            guard closed else { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }
}
