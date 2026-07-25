import Testing
import Foundation
@testable import DebridUI
import DebridCore

@MainActor
final class FakeNowPlaying: NowPlayingControlling {
    private(set) var handlers: NowPlayingHandlers?
    private(set) var updates: [NowPlayingInfo] = []
    private(set) var deactivated = false
    func activate(_ handlers: NowPlayingHandlers) { self.handlers = handlers }
    func update(_ info: NowPlayingInfo) { updates.append(info) }
    func deactivate() { deactivated = true }
}

@MainActor
@Suite struct NowPlayingTests {

    private func makeModel(request: PlaybackRequest = Fixture.request(),
                           engine: FakeVideoPlayerEngine,
                           nowPlaying: FakeNowPlaying) -> PlayerModel {
        PlayerModel(request: request, engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _ in }, subtitles: nil,
                    nowPlaying: nowPlaying)
    }

    /// Bring the model to a live, rendered, playing state at `position`.
    private func warmUp(_ model: PlayerModel, _ engine: FakeVideoPlayerEngine,
                        to position: Double) async {
        model.start()
        await model.waitForIdleForTesting()
        engine.emit(.time(.init(position: position, duration: 3600)))
        engine.emit(.time(.init(position: position + 0.5, duration: 3600)))
        await model.waitForIdleForTesting()
    }

    @Test func startRegistersTransportHandlers() async {
        let engine = FakeVideoPlayerEngine(), np = FakeNowPlaying()
        let model = makeModel(engine: engine, nowPlaying: np)
        model.start()
        await model.waitForIdleForTesting()
        #expect(np.handlers != nil)
    }

    @Test func skipForwardFromTheRemoteSeeksTheEngine() async {
        let engine = FakeVideoPlayerEngine(), np = FakeNowPlaying()
        let model = makeModel(engine: engine, nowPlaying: np)
        await warmUp(model, engine, to: 100)

        np.handlers?.skip(10)
        #expect(engine.seeks.last == 110.5)
    }

    @Test func scrubbingFromTheRemoteSeeksToAnAbsolutePosition() async {
        let engine = FakeVideoPlayerEngine(), np = FakeNowPlaying()
        let model = makeModel(engine: engine, nowPlaying: np)
        await warmUp(model, engine, to: 10)

        np.handlers?.seek(1234)
        #expect(engine.seeks.last == 1234)
    }

    @Test func playAndPauseAreDistinctNotAToggle() async {
        // The system surface sends discrete play and pause commands. A toggle does the wrong
        // thing whenever the surface's idea of the state disagrees with ours.
        let engine = FakeVideoPlayerEngine(), np = FakeNowPlaying()
        let model = makeModel(engine: engine, nowPlaying: np)
        await warmUp(model, engine, to: 100)
        #expect(model.phase == .playing)

        np.handlers?.play()                     // already playing → must NOT pause
        await model.waitForIdleForTesting()
        #expect(model.phase == .playing)

        np.handlers?.pause()
        engine.emit(.state(.paused))
        await model.waitForIdleForTesting()
        #expect(model.phase == .paused)
    }

    @Test func playbackStatePushesNowPlayingInfo() async {
        let engine = FakeVideoPlayerEngine(), np = FakeNowPlaying()
        let model = makeModel(engine: engine, nowPlaying: np)
        await warmUp(model, engine, to: 42)

        let last = np.updates.last
        #expect(last?.title == "Dune: Part Two")
        #expect(last?.duration == 3600)
        #expect(last?.position == 42.5)
        #expect(last?.rate == 1)
    }

    @Test func anEpisodeCarriesItsShowNameAndOffersNextTrack() async {
        let engine = FakeVideoPlayerEngine(), np = FakeNowPlaying()
        let model = makeModel(request: Fixture.showRequest(playingEpisode: 1),
                              engine: engine, nowPlaying: np)
        await warmUp(model, engine, to: 5)

        #expect(np.updates.last?.showName == "The Show")
        #expect(np.handlers?.nextTrack != nil)      // E2 exists → the command is offered
    }

    @Test func teardownClearsTheNowPlayingEntry() async {
        let engine = FakeVideoPlayerEngine(), np = FakeNowPlaying()
        let model = makeModel(engine: engine, nowPlaying: np)
        model.start()
        await model.waitForIdleForTesting()
        await model.teardown()
        #expect(np.deactivated == true)
    }
}
