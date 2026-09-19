import Foundation
import DebridCore

/// Posts one watchlist removal to SeretServer. Injected so the relay is testable without a network.
public typealias WatchlistRemovalPosting =
    @Sendable (_ serverURL: String, _ tmdbID: Int) async throws -> Void

/// Tells Letterboxd about removals made in Seret.
///
/// Writing to Letterboxd needs a real browser — Cloudflare refuses every scripted client, and tvOS
/// has no WebKit at all — so the Apple TV cannot post this itself. SeretServer drives the
/// signed-in browser on the NAS, and this relays to it.
///
/// The pending set comes from the watchlist mirror, not a parallel queue: the mirror already
/// records the removal durably, so a second store could only drift from it. A removal that never
/// gets pushed simply stays pending and is retried the next time the relay runs, which is what
/// makes it survive a server that was switched off.
public struct WatchlistRemovalRelay: Sendable {
    public struct Outcome: Sendable, Equatable {
        public let pushed: Int
        public let failed: Int
        /// The first failure's message, for a screen that has one line to explain itself.
        public let firstError: String?

        public init(pushed: Int, failed: Int, firstError: String? = nil) {
            self.pushed = pushed
            self.failed = failed
            self.firstError = firstError
        }

        public static let idle = Outcome(pushed: 0, failed: 0)
    }

    private let syncer: WatchlistSyncer
    private let settings: @Sendable () -> LetterboxdSettings
    private let post: WatchlistRemovalPosting

    public init(syncer: WatchlistSyncer,
                settings: @escaping @Sendable () -> LetterboxdSettings,
                post: @escaping WatchlistRemovalPosting) {
        self.syncer = syncer
        self.settings = settings
        self.post = post
    }

    /// Pushes every pending removal. Safe to call often — with nothing pending it does nothing.
    ///
    /// Without a server address the removals stay pending rather than being dropped: the owner may
    /// simply not have set one up yet, and a removal they made is still a removal they want.
    @discardableResult
    public func drain() async -> Outcome {
        let address = settings().serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return .idle }

        let pending = await syncer.pendingRemovals()
        guard !pending.isEmpty else { return .idle }

        var pushed = 0
        var failed = 0
        var firstError: String?

        for entry in pending {
            guard let tmdbID = entry.tmdbID else { continue }
            do {
                try await post(address, tmdbID)
                await syncer.markRemovalPushed(slug: entry.slug)
                pushed += 1
            } catch {
                // Left pending on purpose. The next drain tries again, and the film is already
                // gone from the owner's screen either way — the mirror is the truth locally.
                failed += 1
                if firstError == nil { firstError = Self.message(for: error) }
            }
        }

        return Outcome(pushed: pushed, failed: failed, firstError: firstError)
    }

    /// Names the fault in the owner's terms. The server distinguishes a signed-out browser from a
    /// Cloudflare challenge from an unreachable container, and those need three different fixes.
    static func message(for error: any Error) -> String {
        if let letterboxd = error as? LetterboxdError {
            switch letterboxd {
            case .notAuthenticated:
                return "Letterboxd is signed out in the server's browser"
            case .challenged:
                return "Cloudflare is challenging the server's browser"
            case .filmNotFound:
                return "Letterboxd has no film for that id"
            default:
                return "Letterboxd refused the change"
            }
        }
        if (error as? URLError) != nil { return "Couldn't reach your Seret server" }
        return "Couldn't reach your Seret server"
    }
}
