import Testing
import Foundation
@testable import DebridCore

@Suite struct PlaybackModelTests {
    @Test func statesAndEventsAreEquatable() {
        #expect(PlaybackState.failed("boom") == .failed("boom"))
        #expect(PlaybackState.playing != .paused)
        #expect(PlaybackEvent.time(PlaybackTime(position: 10, duration: 100))
                == .time(PlaybackTime(position: 10, duration: 100)))
        #expect(PlaybackEvent.state(.ended) != .state(.playing))
    }

    @Test func mediaTrackCarriesIdentityKindLanguage() {
        let track = MediaTrack(id: "a1", kind: .audio, name: "English", language: "en")
        #expect(track.id == "a1")
        #expect(track.kind == .audio)
        #expect(track.name == "English")
        #expect(track.language == "en")
    }
}
