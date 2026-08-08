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

/// A frame step — how a paused seek is made visible — makes libvlc announce `.playing` mid-pause.
/// Forwarding that tore down the paused UI on tvOS: the scrub bar hid and swipe-scrub disarmed
/// mid-gesture. Intent wins over what the engine reports.
@Suite struct PlaybackStateReconcileTests {

    @Test func aPlayingReportedWhilePausedIsSuppressed() {
        #expect(PlaybackState.playing.reconciled(playbackRequested: false) == .paused)
    }

    @Test func aPlayingReportedAfterPlayWasRequestedPassesThrough() {
        #expect(PlaybackState.playing.reconciled(playbackRequested: true) == .playing)
    }

    /// Only `.playing` is overridden. Everything else genuinely happens to a paused player — a
    /// paused stream can still buffer, end, or fail, and swallowing those would strand the UI.
    @Test func everyOtherStatePassesThroughWhilePaused() {
        let others: [PlaybackState] = [.idle, .buffering, .paused, .ended, .failed("boom")]
        for state in others {
            #expect(state.reconciled(playbackRequested: false) == state)
            #expect(state.reconciled(playbackRequested: true) == state)
        }
    }
}
