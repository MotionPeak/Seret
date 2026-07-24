import Testing
import Foundation
import DebridCore
@testable import DebridUI

@Suite struct TraktScrobblerTests {
    actor Recorder: TraktScrobbleAPI {
        struct Call: Equatable { let action: ScrobbleAction; let ref: TraktMediaRef; let progress: Double }
        private(set) var calls: [Call] = []
        var fail = false
        func scrobble(_ action: ScrobbleAction, ref: TraktMediaRef, progress: Double) async throws {
            if fail { throw HTTPError.status(code: 429, body: "") }
            calls.append(.init(action: action, ref: ref, progress: progress))
        }
        func setFail(_ v: Bool) { fail = v }
    }

    @Test func startThenStopSendsBoth() async throws {
        let rec = Recorder()
        let s = TraktScrobbler(api: rec, ref: .movie(tmdb: 27205))
        await s.start(fraction: 0.1)
        await s.stop(fraction: 0.9)
        #expect(await rec.calls == [
            .init(action: .start, ref: .movie(tmdb: 27205), progress: 10),
            .init(action: .stop, ref: .movie(tmdb: 27205), progress: 90)
        ])
    }

    @Test func failuresAreSwallowed() async throws {
        let rec = Recorder(); await rec.setFail(true)
        let s = TraktScrobbler(api: rec, ref: .movie(tmdb: 1))
        await s.start(fraction: 0.1)     // must not throw
        #expect(await rec.calls.isEmpty)
    }

    @Test func duplicateStartCoalesced() async throws {
        let rec = Recorder()
        let s = TraktScrobbler(api: rec, ref: .movie(tmdb: 1))
        await s.start(fraction: 0.1)
        await s.start(fraction: 0.1)     // already playing → no second start
        #expect(await rec.calls.count == 1)
    }

    @Test func pauseOnlyWhenPlaying() async throws {
        let rec = Recorder()
        let s = TraktScrobbler(api: rec, ref: .movie(tmdb: 1))
        await s.pause(fraction: 0.2)     // not playing yet → ignored
        #expect(await rec.calls.isEmpty)
        await s.start(fraction: 0.1)
        await s.pause(fraction: 0.2)
        #expect(await rec.calls.map(\.action) == [.start, .pause])
    }

    /// A controllable monotonic clock so heartbeat throttling is deterministic.
    final class Clock: @unchecked Sendable {
        var t: Double = 0
        func read() -> Double { t }
    }

    @Test func heartbeatThrottledToInterval() async throws {
        let rec = Recorder(); let clock = Clock()
        let s = TraktScrobbler(api: rec, ref: .movie(tmdb: 1), heartbeatInterval: 60,
                               now: { clock.read() })
        await s.start(fraction: 0.1)
        // PlayerModel ticks ~1s apart: none of these should scrobble.
        for i in 1...59 { clock.t = Double(i); await s.heartbeat(fraction: 0.2) }
        #expect(await rec.calls.map(\.action) == [.start])
        // Crossing the interval sends exactly one pause.
        clock.t = 60; await s.heartbeat(fraction: 0.3)
        #expect(await rec.calls.map(\.action) == [.start, .pause])
        // ...and the window resets.
        clock.t = 61; await s.heartbeat(fraction: 0.31)
        #expect(await rec.calls.map(\.action) == [.start, .pause])
        clock.t = 120; await s.heartbeat(fraction: 0.5)
        #expect(await rec.calls.map(\.action) == [.start, .pause, .pause])
    }

    @Test func heartbeatIgnoredWhenNotPlaying() async throws {
        let rec = Recorder(); let clock = Clock()
        let s = TraktScrobbler(api: rec, ref: .movie(tmdb: 1), heartbeatInterval: 60,
                               now: { clock.read() })
        clock.t = 1000
        await s.heartbeat(fraction: 0.3)      // never started
        #expect(await rec.calls.isEmpty)
    }
}
