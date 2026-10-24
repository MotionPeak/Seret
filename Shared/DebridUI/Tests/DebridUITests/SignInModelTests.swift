import Testing
import Foundation
import DebridCore
@testable import DebridUI

private func makeDeviceCode() -> RDDeviceCode {
    let json = #"""
    {"device_code":"DC","user_code":"WXYZ-1234","interval":5,
     "expires_in":1800,"verification_url":"https://real-debrid.com/device"}
    """#
    return try! JSONDecoder().decode(RDDeviceCode.self, from: Data(json.utf8))
}

@MainActor
final class FakeAuthFlow: AuthFlow {
    var beginError: Error?
    var signInError: Error?
    private(set) var beginCalls = 0
    private(set) var awaitCalls = 0

    func begin() async throws -> RDDeviceCode {
        beginCalls += 1
        if let beginError { throw beginError }
        return makeDeviceCode()
    }

    func awaitSignIn(_ code: RDDeviceCode) async throws {
        awaitCalls += 1
        if let signInError { throw signInError }
    }

    var tokenSignInError: Error?
    private(set) var tokenCalls = 0
    private(set) var lastToken: String?
    func signIn(token: String) async throws {
        tokenCalls += 1
        lastToken = token
        if let tokenSignInError { throw tokenSignInError }
    }
}

/// An `AuthFlow` whose `awaitSignIn` waits until `release()`, ignoring cancellation, so a test can
/// finish a "late" sign-in after the model was cancelled.
@MainActor
final class GatedAuthFlow: AuthFlow {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var beginCalls = 0
    private(set) var established = false
    private(set) var waiting = false

    func begin() async throws -> RDDeviceCode { beginCalls += 1; return makeDeviceCode() }
    func awaitSignIn(_ code: RDDeviceCode) async throws {
        waiting = true
        await withCheckedContinuation { continuation = $0 }
        waiting = false
        established = true
    }
    func signIn(token: String) async throws {
        await withCheckedContinuation { continuation = $0 }
        established = true
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
@Suite struct SignInModelTests {
    @Test func happyPathReachesSignedIn() async {
        var signedIn = false
        let fake = FakeAuthFlow()
        let model = SignInModel(flow: fake, onSignedIn: { signedIn = true })
        await model.run()
        #expect(model.phase == .signedIn)
        #expect(signedIn)
        #expect(fake.beginCalls == 1)
        #expect(fake.awaitCalls == 1)
    }

    @Test func failureThenRetrySucceeds() async {
        var signedInCount = 0
        let fake = FakeAuthFlow()
        fake.signInError = HTTPError.transport("offline")
        let model = SignInModel(flow: fake, onSignedIn: { signedInCount += 1 })

        await model.run()
        guard case .failed = model.phase else {
            #expect(Bool(false), "expected .failed, got \(model.phase)")
            return
        }
        #expect(signedInCount == 0)

        fake.signInError = nil
        model.retry()
        await model.run()
        #expect(model.phase == .signedIn)
        #expect(signedInCount == 1)
    }

    @Test func tokenSignInSucceeds() async {
        var signedIn = false
        let fake = FakeAuthFlow()
        let model = SignInModel(flow: fake, onSignedIn: { signedIn = true })
        await model.signInWithToken("  MY-TOKEN  ")
        #expect(model.phase == .signedIn)
        #expect(signedIn)
        #expect(fake.tokenCalls == 1)
        #expect(fake.lastToken == "MY-TOKEN")   // trimmed
    }

    @Test func tokenSignInInvalidShowsFailure() async {
        let fake = FakeAuthFlow()
        fake.tokenSignInError = TokenSignInError.invalidToken
        let model = SignInModel(flow: fake, onSignedIn: {})
        await model.signInWithToken("BAD")
        guard case .failed = model.phase else {
            #expect(Bool(false), "expected .failed, got \(model.phase)"); return
        }
        #expect(fake.tokenCalls == 1)
    }

    @Test func tokenSignInEmptyIsIgnored() async {
        let fake = FakeAuthFlow()
        let model = SignInModel(flow: fake, onSignedIn: {})
        await model.signInWithToken("   ")
        #expect(fake.tokenCalls == 0)
        #expect(model.phase == .idle)
    }

    @Test func retryReusesUnexpiredCode() async {
        let fake = FakeAuthFlow()
        fake.signInError = HTTPError.transport("offline")
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let model = SignInModel(flow: fake, onSignedIn: {}, now: { clock })
        await model.run()                          // begin #1, awaitSignIn fails
        guard case .failed = model.phase else { #expect(Bool(false)); return }
        #expect(fake.beginCalls == 1)

        fake.signInError = nil
        clock = clock.addingTimeInterval(10)       // 10s later; code (expires_in 1800) still valid
        model.retry()
        await model.run()                          // must REUSE the cached code
        #expect(model.phase == .signedIn)
        #expect(fake.beginCalls == 1)              // no new device/code minted
        #expect(fake.awaitCalls == 2)
    }

    @Test func retryAfterExpiryMintsNewCode() async {
        let fake = FakeAuthFlow()
        fake.signInError = HTTPError.transport("offline")
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let model = SignInModel(flow: fake, onSignedIn: {}, now: { clock })
        await model.run()                          // begin #1
        #expect(fake.beginCalls == 1)

        fake.signInError = nil
        clock = clock.addingTimeInterval(2000)     // > 1800 expires_in → expired
        model.retry()
        await model.run()                          // must mint a NEW code
        #expect(model.phase == .signedIn)
        #expect(fake.beginCalls == 2)
    }

    // MARK: - Provider

    @Test func providerIsCarried() {
        let fake = FakeAuthFlow()
        #expect(SignInModel(flow: fake, onSignedIn: {}).provider == .realDebrid)
        #expect(SignInModel(flow: fake, provider: .torBox, onSignedIn: {}).provider == .torBox)
    }

    @Test func torBoxInvalidKeyMessage() async {
        let fake = FakeAuthFlow()
        fake.tokenSignInError = TorBoxAuthError.invalidKey
        let model = SignInModel(flow: fake, provider: .torBox, onSignedIn: {})
        await model.signInWithToken("BAD")
        #expect(model.phase == .failed("That TorBox API key wasn't accepted."))
    }

    @Test func torBoxExpiredMessage() async {
        let fake = FakeAuthFlow()
        fake.signInError = TorBoxAuthError.expired
        let model = SignInModel(flow: fake, provider: .torBox, onSignedIn: {})
        await model.run()
        #expect(model.phase == .failed("The code expired. Try again."))
    }

    @Test func torBoxRateLimitUsesItsUserMessage() async {
        let fake = FakeAuthFlow()
        fake.beginError = TorBoxError.rateLimited(retryAfter: 300)
        let model = SignInModel(flow: fake, provider: .torBox, onSignedIn: {})
        await model.run()
        #expect(model.phase == .failed(TorBoxError.rateLimited(retryAfter: 300).userMessage))
    }

    @Test func otherTorBoxErrorsUseTheirUserMessage() {
        let planError = TorBoxError.api(code: "PLAN_RESTRICTED_FEATURE", detail: "x", status: 403)
        #expect(SignInModel.message(for: planError) == "TorBox's API needs a paid plan.")
        let apiError = TorBoxError.api(code: "SOMETHING", detail: "Server hiccup.", status: 500)
        #expect(SignInModel.message(for: apiError) == "Server hiccup.")
    }

    @Test func torBoxTokenErrorKeepsTorBoxWording() {
        // A TorBox model's pasted-key rejection arrives as TokenSignInError; it must not name Real-Debrid.
        let model = SignInModel(flow: FakeAuthFlow(), provider: .torBox, onSignedIn: {})
        #expect(model.failureMessage(for: TokenSignInError.invalidToken) == "That TorBox API key wasn't accepted.")
        #expect(SignInModel(flow: FakeAuthFlow(), onSignedIn: {}).failureMessage(for: TokenSignInError.invalidToken)
                == SignInModel.message(for: TokenSignInError.invalidToken))
    }

    // MARK: - Cancel

    @Test func aCancelledModelNeverSignsInEvenIfTheFlowLateSucceeds() async {
        var signedIn = 0
        let gate = GatedAuthFlow()
        let model = SignInModel(flow: gate, onSignedIn: { signedIn += 1 })
        let run = Task { await model.run() }
        while !gate.waiting { await Task.yield() }

        model.cancel()
        gate.release()          // the flow finishes anyway, as a throttled network call might
        await run.value

        #expect(signedIn == 0)
        #expect(model.phase != .signedIn)
    }

    @Test func aCancelledTokenSignInNeverSignsIn() async {
        var signedIn = 0
        let gate = GatedAuthFlow()
        let model = SignInModel(flow: gate, provider: .torBox, onSignedIn: { signedIn += 1 })
        let submit = Task { await model.signInWithToken("KEY") }
        while model.phase != .validatingToken { await Task.yield() }

        model.cancel()
        gate.release()
        await submit.value

        #expect(signedIn == 0)
        #expect(model.phase == .idle)   // not stuck on a spinner when the model is shown again
    }

    @Test func aCancelledModelCanBeActivatedAndReusesItsCode() async {
        let gate = GatedAuthFlow()
        var signedIn = 0
        let model = SignInModel(flow: gate, onSignedIn: { signedIn += 1 })
        let first = Task { await model.run() }
        while !gate.waiting { await Task.yield() }
        model.cancel()
        gate.release()
        await first.value
        #expect(gate.beginCalls == 1)

        model.activate()
        let second = Task { await model.run() }
        while !gate.waiting { await Task.yield() }
        gate.release()
        await second.value

        #expect(gate.beginCalls == 1)       // the still-valid code was reused
        #expect(signedIn == 1)
    }

    @Test func aCancelledModelDoesNotRun() async {
        let fake = FakeAuthFlow()
        let model = SignInModel(flow: fake, onSignedIn: {})
        model.cancel()
        await model.run()
        #expect(fake.beginCalls == 0)
    }

    // MARK: - Local storage failures

    @Test func aTorBoxKeyThatCannotBeSavedSaysSo() async {
        let fake = FakeAuthFlow()
        fake.tokenSignInError = TorBoxSessionError.notSignedIn
        let model = SignInModel(flow: fake, provider: .torBox, onSignedIn: {})
        await model.signInWithToken("KEY")
        #expect(model.phase == .failed("Couldn't save the TorBox key on this device."))

        fake.tokenSignInError = KeychainError.unexpectedStatus(-25308)
        await model.signInWithToken("KEY")
        #expect(model.phase == .failed("Couldn't save the TorBox key on this device."))
    }

    @Test func aTorBoxNetworkFailureStillSaysCouldntReach() async {
        let fake = FakeAuthFlow()
        fake.tokenSignInError = HTTPError.transport("offline")
        let model = SignInModel(flow: fake, provider: .torBox, onSignedIn: {})
        await model.signInWithToken("KEY")
        #expect(model.phase == .failed("Couldn't reach TorBox. Check your connection and try again."))
    }

    /// The views key their `.task` on this; attempt alone left a swapped-in model idle forever.
    @Test func theTaskKeyDiffersPerModelAndPerAttempt() {
        let a = SignInModel(flow: FakeAuthFlow(), onSignedIn: {})
        let b = SignInModel(flow: FakeAuthFlow(), provider: .torBox, onSignedIn: {})
        #expect(a.attempt == b.attempt)
        #expect(a.taskKey != b.taskKey)
        let before = a.taskKey
        a.retry()
        #expect(a.taskKey != before)
        #expect(a.taskKey == a.taskKey)
    }
}
