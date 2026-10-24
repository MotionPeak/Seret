import DebridCore
import Foundation

/// Whether this device holds a usable sign-in for one debrid provider.
public enum AccountState: Equatable, Sendable { case signedIn, signedOut }

/// What launch makes of every provider's credential probe.
enum LaunchDecision: Equatable, Sendable {
    /// Signed in with these providers, in `DebridProvider.allCases` order.
    case signedIn([DebridProvider])
    case signedOut
}

/// The pure rules behind having two debrid accounts. `AppSession` applies them; keeping them here
/// keeps them testable without composing a whole signed-in stack.
enum DebridAccounts {

    /// Each provider's launch probe → the overall decision.
    ///
    /// A provider counts as signed in when its probe succeeded, or failed for a reason that is not
    /// "these credentials are no good" — offline, rate-limited, the service down. The app is signed
    /// out only when no provider counts.
    static func launchDecision(_ probes: [DebridProvider: Result<Void, any Error>]) -> LaunchDecision {
        let signedIn = DebridProvider.allCases.filter { provider in
            switch probes[provider] {
            case .success?: return true
            case .failure(let error)?: return !mustReauthenticate(after: error)
            case nil: return false
            }
        }
        return signedIn.isEmpty ? .signedOut : .signedIn(signedIn)
    }

    /// Whether a failure means the credentials themselves are no good, so the account must sign in
    /// again.
    ///
    /// Only a few things do: no credentials stored (either provider), Real-Debrid rejecting the
    /// token with a `401`, and TorBox rejecting the key in its own envelope (`BAD_TOKEN`, `NO_AUTH`,
    /// `AUTH_ERROR`). Everything else is the service having a bad moment and the credentials are
    /// still valid:
    /// - Real-Debrid answers a rate limit with a bare `403` (on tvOS sometimes a PERSISTENT one)
    ///   and an outage with a `5xx`. Both used to sign the viewer out.
    /// - A TorBox key on the Free plan is a valid key that TorBox will not serve the API to
    ///   (`PLAN_RESTRICTED_FEATURE`). Signing out over it loops through a sign-in that succeeds.
    /// - A TorBox 401/403 WITHOUT the envelope (`HTTP_401` / `HTTP_403`) came from something in
    ///   front of TorBox, not from TorBox judging the key.
    /// - Transport errors, offline, decode failures.
    static func mustReauthenticate(after error: any Error) -> Bool {
        if error is RealDebridSessionError || error is TorBoxSessionError { return true }
        if let torBox = error as? TorBoxError {
            if case .notSignedIn = torBox { return true }
            return torBox.isAuthRejection
        }
        if case HTTPError.status(let code, _) = error { return code == 401 }
        return false
    }

    /// Where new titles go: the stored choice while that account is signed in; otherwise
    /// Real-Debrid if it is signed in; otherwise the first signed-in account. Nil with none.
    static func effectiveAddTarget(stored: DebridProvider?, signedIn: [DebridProvider]) -> DebridProvider? {
        if let stored, signedIn.contains(stored) { return stored }
        if signedIn.contains(.realDebrid) { return .realDebrid }
        return signedIn.first
    }
}
