import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// Syncing a subtitle to a line the viewer can hear.
///
/// The measurement a person can make that the machine cannot is "that line was spoken NOW". It is
/// only worth anything if the press can be timestamped accurately, which is why the engine is asked
/// for the time rather than the once-a-second tick being trusted.
@MainActor
@Suite struct PlayerManualSyncTests {

    private func model(engine: FakeVideoPlayerEngine = FakeVideoPlayerEngine()) -> PlayerModel {
        PlayerModel(request: Fixture.request(sources: [Fixture.movieSource()]), engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _ in }, subtitles: FakeSubtitleProvider())
    }

    @Test func theEnginesOwnClockIsPreferredToTheTick() {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine: engine)
        m.position = 120                 // the once-a-second tick
        engine.preciseTime = 120.64      // where the film actually is

        #expect(m.preciseNow == 120.64)
    }

    @Test func theTickIsTheFallbackWhenTheEngineCannotAnswer() {
        let engine = FakeVideoPlayerEngine()
        let m = model(engine: engine)
        m.position = 120
        engine.preciseTime = nil

        #expect(m.preciseNow == 120)
    }
}
