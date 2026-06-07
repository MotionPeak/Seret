import DebridCore
import Foundation
import Observation

/// Resolves a title's trailer to a playable stream URL for both apps. State machine:
/// `idle → resolving → ready(URL)` (playable) or `→ unavailable` (no key / extraction failed →
/// the UI shows nothing inline and the Trailer button deep-links to YouTube using `youTubeKey`).
@MainActor
@Observable
public final class TrailerModel {
    public enum State: Equatable { case idle, resolving, ready(URL), unavailable }

    public private(set) var state: State = .idle
    /// The YouTube key, once resolved — drives the deep-link fallback even when extraction fails.
    public private(set) var youTubeKey: String?

    private let trailers: TrailerProviding
    private let resolver: TrailerStreamResolving
    private let autoplayEnabled: @MainActor () -> Bool

    public init(trailers: TrailerProviding,
                resolver: TrailerStreamResolving,
                autoplayEnabled: @escaping @MainActor () -> Bool) {
        self.trailers = trailers
        self.resolver = resolver
        self.autoplayEnabled = autoplayEnabled
    }

    /// True only when a stream is ready AND the user's autoplay setting is on — gates the muted
    /// backdrop auto-play. (The Trailer button plays regardless of this, full-screen.)
    public var autoplayAllowed: Bool {
        if case .ready = state { return autoplayEnabled() }
        return false
    }

    /// The playable stream URL when ready, else nil.
    public var streamURL: URL? { if case .ready(let u) = state { return u } else { return nil } }

    public func prepare(tmdbID: Int, kind: MediaKind) async {
        state = .resolving
        guard let key = await trailers.trailerKey(tmdbID: tmdbID, kind: kind) else {
            state = .unavailable
            return
        }
        youTubeKey = key
        if let url = await resolver.streamURL(youTubeKey: key) {
            state = .ready(url)
        } else {
            state = .unavailable
        }
    }
}
