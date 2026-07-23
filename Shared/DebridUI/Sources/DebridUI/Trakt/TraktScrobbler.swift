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
    private enum State { case idle, playing, paused, stopped }
    private var state: State = .idle

    public init(api: TraktScrobbleAPI, ref: TraktMediaRef) {
        self.api = api
        self.ref = ref
    }

    public func start(fraction: Double) async {
        guard state != .playing else { return }
        state = .playing
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

    /// Heartbeat: a pause scrobble that leaves a fresh resume point if the app is killed. Keeps
    /// the internal state `.playing` so real lifecycle transitions still fire.
    public func heartbeat(fraction: Double) async {
        guard state == .playing else { return }
        await send(.pause, fraction)
    }

    private func send(_ action: ScrobbleAction, _ fraction: Double) async {
        let pct = max(0, min(100, fraction * 100))
        try? await api.scrobble(action, ref: ref, progress: pct)
    }
}
