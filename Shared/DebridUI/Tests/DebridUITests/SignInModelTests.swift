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
}
