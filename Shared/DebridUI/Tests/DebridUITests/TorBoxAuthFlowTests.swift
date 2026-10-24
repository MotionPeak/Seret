import Testing
import Foundation
import DebridCore
@testable import DebridUI

/// A URLProtocol private to these tests (DebridCore's `MockURLProtocol` is not visible here).
private final class TorBoxStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, json) = Self.handler?(request) ?? (500, "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func stubbedClient() -> TorBoxAuthClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [TorBoxStub.self]
    return TorBoxAuthClient(http: HTTPClient(session: URLSession(configuration: config)))
}

private let startJSON = """
{"success":true,"error":null,"detail":"ok","data":{
  "device_code":"DEV123","code":"ABCD-1234","verification_url":"https://torbox.app/link",
  "friendly_verification_url":"torbox.app/link?code=ABCD-1234",
  "interval":5,"expires_at":"2026-10-24T12:10:00Z"}}
"""
private let userJSON = #"{"success":true,"error":null,"detail":"ok","data":{"id":7,"email":"a@b.c","plan":0,"premium_expires_at":null}}"#
private let badKeyJSON = #"{"success":false,"error":"BAD_TOKEN","detail":"bad","data":null}"#

/// The stub's handler is a global, so these tests run one at a time.
@MainActor
@Suite(.serialized) struct TorBoxAuthFlowTests {
    private let t0 = ISO8601Timestamp.date(from: "2026-10-24T12:00:00Z")!

    private func make(store: InMemorySecretStore = InMemorySecretStore()) -> (TorBoxAuthFlow, TorBoxSession) {
        let session = TorBoxSession(store: store)
        return (TorBoxAuthFlow(auth: stubbedClient(), session: session, now: { [t0] in t0 }), session)
    }

    @Test func beginPresentsTheCodeThroughTheSharedSignInUI() async throws {
        TorBoxStub.handler = { _ in (200, startJSON) }
        let (flow, _) = make()
        let code = try await flow.begin()
        #expect(code.userCode == "ABCD-1234")
        #expect(code.verificationURL == "torbox.app/link?code=ABCD-1234")
        #expect(code.expiresIn == 600)
        #expect(code.interval == 5)
    }

    @Test func awaitSignInPollsWithTheKeptCodeThenStoresTheKey() async throws {
        TorBoxStub.handler = { request in
            request.url?.path.hasSuffix("device/start") == true
                ? (200, startJSON)
                : (200, #"{"success":true,"error":null,"detail":"ok","data":{"access_token":"THE-KEY"}}"#)
        }
        let (flow, session) = make()
        let code = try await flow.begin()
        try await flow.awaitSignIn(code)
        #expect(try await session.validAccessToken() == "THE-KEY")
    }

    @Test func awaitSignInWithoutBeginIsRefused() async {
        let (flow, session) = make()
        let stray = RDDeviceCode(deviceCode: "X", userCode: "Y", interval: 5, expiresIn: 60, verificationURL: "u")
        await #expect(throws: TorBoxAuthError.expired) { try await flow.awaitSignIn(stray) }
        #expect(await !session.isSignedIn)
    }

    @Test func aKeyIsValidatedThenStored() async throws {
        TorBoxStub.handler = { _ in (200, userJSON) }
        let (flow, session) = make()
        try await flow.signIn(token: "MYKEY")
        #expect(try await session.validAccessToken() == "MYKEY")
    }

    /// Review focus 2: a Free-plan key (plan 0) must sign in; the plan warning belongs to Settings.
    @Test func aFreePlanKeySignsIn() async throws {
        TorBoxStub.handler = { _ in (200, userJSON) }
        let (flow, session) = make()
        try await flow.signIn(token: "FREEKEY")
        #expect(await session.isSignedIn)
    }

    @Test func aRefusedKeyIsInvalidTokenAndStoresNothing() async {
        TorBoxStub.handler = { _ in (403, badKeyJSON) }
        let (flow, session) = make()
        await #expect(throws: TokenSignInError.invalidToken) { try await flow.signIn(token: "NOPE") }
        #expect(await !session.isSignedIn)
    }

    @Test func aRateLimitedValidationPassesThroughUnchanged() async {
        TorBoxStub.handler = { _ in (429, #"{"success":false,"error":"RATE_LIMIT","detail":"slow","data":null}"#) }
        let (flow, session) = make()
        await #expect(throws: TorBoxError.rateLimited(retryAfter: nil)) { try await flow.signIn(token: "K") }
        #expect(await !session.isSignedIn)
    }
}
