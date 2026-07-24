import DebridCore
import Foundation

public protocol TraktScrobbleAPI: Sendable {
    func scrobble(_ action: ScrobbleAction, ref: TraktMediaRef, progress: Double) async throws
}
extension TraktClient: TraktScrobbleAPI {}

/// Translates player lifecycle into Trakt scrobble calls. All calls best-effort (never throw
/// into playback). One instance per played item; `ref` is fixed for its lifetime.
public actor TraktScrobbler {
    private let api: TraktScrobbleAPI
    private let ref: TraktMediaRef
    private let heartbeatInterval: Double            // seconds between heartbeat scrobbles
    private let now: @Sendable () -> Double           // monotonic seconds
    private enum State { case idle, playing, paused, stopped }
    private var state: State = .idle
    private var lastHeartbeat: Double = -.infinity

    public init(api: TraktScrobbleAPI, ref: TraktMediaRef,
                heartbeatInterval: Double = 60,
                now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.api = api
        self.ref = ref
        self.heartbeatInterval = heartbeatInterval
        self.now = now
    }

    public func start(fraction: Double) async {
        guard state != .playing else { return }
        state = .playing
        lastHeartbeat = now()                          // don't heartbeat right after a start
        await send(.start, fraction)
    }

    public func pause(fraction: Double) async {
        guard state == .playing else { return }
        state = .paused
        await send(.pause, fraction)
    }

    public func stop(fraction: Double) async {
        guard state != .stopped else { return }
        state = .stopped
        await send(.stop, fraction)
    }

    /// Heartbeat: a throttled pause scrobble that leaves a fresh resume point if the app is killed.
    /// PlayerModel calls this every ~1s; it only actually scrobbles every `heartbeatInterval` s.
    /// Keeps the internal state `.playing` so real lifecycle transitions still fire.
    public func heartbeat(fraction: Double) async {
        guard state == .playing else { return }
        let t = now()
        guard t - lastHeartbeat >= heartbeatInterval else { return }
        lastHeartbeat = t
        await send(.pause, fraction)
    }

    private func send(_ action: ScrobbleAction, _ fraction: Double) async {
        let pct = max(0, min(100, fraction * 100))
        try? await api.scrobble(action, ref: ref, progress: pct)
    }
}
