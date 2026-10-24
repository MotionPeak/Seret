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

    /// Which debrid account this run signs in. Picks the wording of the messages; the flow does the work.
    public let provider: DebridProvider

    private let flow: AuthFlow
    private let onSignedIn: () -> Void
    private let now: () -> Date
    private var cachedCode: RDDeviceCode?
    private var codeObtainedAt: Date?
    /// Set by `cancel()`: the model stands down until `activate()`. Nothing it started can sign in.
    private var isCancelled = false
    /// Bumped by `cancel()`. A run captures it at the start, so a run that was cancelled can never
    /// publish a result — even if its flow finishes anyway, or the model is re-armed meanwhile.
    private var generation = 0
    private var inFlight: [UUID: Task<Void, Never>] = [:]

    init(flow: AuthFlow, provider: DebridProvider = .realDebrid, onSignedIn: @escaping () -> Void,
         now: @escaping () -> Date = { Date() }) {
        self.flow = flow
        self.provider = provider
        self.onSignedIn = onSignedIn
        self.now = now
    }

    /// Run the full flow once. Reuses a still-valid device code on retry so repeated
    /// attempts don't re-hit RD's throttled `device/code` endpoint.
    public func run() async {
        guard !isCancelled else { return }
        await supervise { [self] in await perform() }
    }

    private func perform() async {
        let generation = self.generation
        do {
            let code = try await currentOrFreshCode()
            guard generation == self.generation else { return }
            phase = .awaitingAuthorization(code)
            try await flow.awaitSignIn(code)
            guard generation == self.generation else { return }
            phase = .signedIn
            onSignedIn()
        } catch is CancellationError {
            // View disappeared mid-wait — leave state untouched, no dangling work.
        } catch {
            guard generation == self.generation else { return }
            phase = .failed(failureMessage(for: error))
        }
    }

    /// Stop this model: cancel its poll / validation and make sure nothing it started can sign in.
    /// The cached device code is kept, so `activate()` + `run()` picks up without a new request.
    public func cancel() {
        isCancelled = true
        generation += 1
        for task in inFlight.values { task.cancel() }
        switch phase {
        case .requestingCode, .validatingToken: phase = .idle
        default: break
        }
    }

    /// Lets a cancelled model run again (the viewer came back to it).
    public func activate() { isCancelled = false }

    /// Runs `work` as a child task that dies with either the caller (view disappears) or `cancel()`.
    private func supervise(_ work: @escaping @MainActor () async -> Void) async {
        let id = UUID()
        let task = Task { await work() }
        inFlight[id] = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        inFlight[id] = nil
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
        guard !trimmed.isEmpty, !isCancelled else { return }
        await supervise { [self] in await validate(token: trimmed) }
    }

    private func validate(token: String) async {
        let generation = self.generation
        phase = .validatingToken
        do {
            try await flow.signIn(token: token)
            guard generation == self.generation else { return }
            phase = .signedIn
            onSignedIn()
        } catch is CancellationError {
            // View disappeared mid-validation — leave state untouched.
        } catch {
            guard generation == self.generation else { return }
            phase = .failed(failureMessage(for: error))
        }
    }

    /// The message for a failure of THIS model's provider.
    func failureMessage(for error: Error) -> String {
        switch (provider, error) {
        case (.torBox, TokenSignInError.invalidToken):
            return Self.message(for: TorBoxAuthError.invalidKey)
        case (.torBox, _) where Self.isTorBoxError(error):
            return Self.message(for: error)
        case (.torBox, is TorBoxSessionError), (.torBox, is KeychainError):
            // The key was fine; this device couldn't keep it. Not a network problem.
            return "Couldn't save the TorBox key on this device."
        case (.torBox, _):
            return "Couldn't reach TorBox. Check your connection and try again."
        default:
            return Self.message(for: error)
        }
    }

    private static func isTorBoxError(_ error: Error) -> Bool {
        error is TorBoxAuthError || error is TorBoxError
    }

    /// User-facing message. Never interpolates the raw error (no token/secret leakage).
    static func message(for error: Error) -> String {
        switch error {
        case TokenSignInError.invalidToken:
            return "That token wasn't accepted by Real\u{2011}Debrid. Check it and try again."
        case TorBoxAuthError.invalidKey:
            return "That TorBox API key wasn't accepted."
        case TorBoxAuthError.expired:
            return "The code expired. Try again."
        case let error as TorBoxError:
            return error.userMessage
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

/// What a sign-in view keys its `.task` on: the model's identity AND its attempt. Keyed on the
/// attempt alone, a view handed a different model (the provider picker) never restarts its run,
/// because both models start at attempt 0.
public struct SignInTaskKey: Hashable, Sendable {
    let model: ObjectIdentifier
    let attempt: Int
}

extension SignInModel {
    public var taskKey: SignInTaskKey { SignInTaskKey(model: ObjectIdentifier(self), attempt: attempt) }
}
