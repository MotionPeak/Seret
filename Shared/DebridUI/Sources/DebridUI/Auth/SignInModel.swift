import DebridCore
import Foundation
import Observation

/// Drives the device-code sign-in as an observable phase machine. The long wait is
/// a single `await flow.awaitSignIn(_:)`, so the whole flow cancels cleanly when the
/// view disappears. No RD/networking logic here — it delegates to `AuthFlow`.
@MainActor
@Observable
public final class SignInModel {
    public enum Phase: Equatable {
        case idle
        case requestingCode
        case awaitingAuthorization(RDDeviceCode)
        case validatingToken
        case signedIn
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    /// Bumped by `retry()`; drives the view's `.task(id:)` so a retry restarts the run.
    public private(set) var attempt = 0

    private let flow: AuthFlow
    private let onSignedIn: () -> Void
    private let now: () -> Date
    private var cachedCode: RDDeviceCode?
    private var codeObtainedAt: Date?

    init(flow: AuthFlow, onSignedIn: @escaping () -> Void, now: @escaping () -> Date = { Date() }) {
        self.flow = flow
        self.onSignedIn = onSignedIn
        self.now = now
    }

    /// Run the full flow once. Reuses a still-valid device code on retry so repeated
    /// attempts don't re-hit RD's throttled `device/code` endpoint.
    public func run() async {
        do {
            let code = try await currentOrFreshCode()
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

    /// Reuse the cached code while it has at least one poll interval left; otherwise mint a new one.
    private func currentOrFreshCode() async throws -> RDDeviceCode {
        if let cachedCode, let codeObtainedAt {
            let margin = Double(max(1, cachedCode.interval))
            if now().timeIntervalSince(codeObtainedAt) < Double(cachedCode.expiresIn) - margin {
                return cachedCode
            }
        }
        phase = .requestingCode
        let code = try await flow.begin()
        cachedCode = code
        codeObtainedAt = now()
        return code
    }

    public func retry() { attempt += 1 }

    /// Sign in with a pasted personal API token instead of the device-code flow.
    public func signInWithToken(_ token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        phase = .validatingToken
        do {
            try await flow.signIn(token: trimmed)
            phase = .signedIn
            onSignedIn()
        } catch is CancellationError {
            // View disappeared mid-validation — leave state untouched.
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    /// User-facing message. Never interpolates the raw error (no token/secret leakage).
    static func message(for error: Error) -> String {
        switch error {
        case TokenSignInError.invalidToken:
            return "That token wasn't accepted by Real\u{2011}Debrid. Check it and try again."
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
