import DebridCore
import Observation

/// Drives the device-code sign-in as an observable phase machine. The long wait is
/// a single `await flow.awaitSignIn(_:)`, so the whole flow cancels cleanly when the
/// view disappears. No RD/networking logic here — it delegates to `AuthFlow`.
@MainActor
@Observable
final class SignInModel {
    enum Phase: Equatable {
        case idle
        case requestingCode
        case awaitingAuthorization(RDDeviceCode)
        case signedIn
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Bumped by `retry()`; drives the view's `.task(id:)` so a retry restarts the run.
    private(set) var attempt = 0

    private let flow: AuthFlow
    private let onSignedIn: () -> Void

    init(flow: AuthFlow, onSignedIn: @escaping () -> Void) {
        self.flow = flow
        self.onSignedIn = onSignedIn
    }

    /// Run the full flow once. Safe to call again after `.failed` (retry).
    func run() async {
        phase = .requestingCode
        do {
            let code = try await flow.begin()
            phase = .awaitingAuthorization(code)
            try await flow.awaitSignIn(code)
            phase = .signedIn
            onSignedIn()
        } catch is CancellationError {
            // View disappeared mid-wait — leave state untouched, no dangling work.
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    func retry() { attempt += 1 }

    /// User-facing message. Never interpolates the raw error (no token/secret leakage).
    static func message(for error: Error) -> String {
        switch error {
        case RealDebridAuthError.deviceCodeExpired:
            return "That code expired before you signed in. Try again to get a new one."
        case HTTPError.status(let code, _) where code == 403 || code == 429:
            // Real-Debrid rate-limits device-code generation; a burst of attempts gets a bare 403.
            return "Real\u{2011}Debrid is busy (too many recent attempts). Wait a minute, then try again."
        default:
            return "Couldn't reach Real\u{2011}Debrid. Check your connection and try again."
        }
    }
}
