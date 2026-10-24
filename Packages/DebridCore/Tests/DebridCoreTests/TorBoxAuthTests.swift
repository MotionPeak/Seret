import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TorBoxAuthTests {
        init() { MockURLProtocol.handler = nil }

        private func client() -> TorBoxAuthClient { TorBoxAuthClient(http: HTTPClient(session: .mock)) }

        private static func respond(_ r: URLRequest, status: Int = 200, json: String) -> (HTTPURLResponse, Data) {
            (HTTPURLResponse(url: r.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
             Data(json.utf8))
        }

        /// Thread-safe request log; the mock handler runs off the test's task.
        final class Log: @unchecked Sendable {
            private let lock = NSLock()
            private var _requests: [URLRequest] = []
            private var _bodies: [String] = []
            var requests: [URLRequest] { lock.withLock { _requests } }
            var bodies: [String] { lock.withLock { _bodies } }
            func record(_ r: URLRequest) {
                lock.withLock {
                    _requests.append(r)
                    var body = r.httpBody
                    if body == nil, let stream = r.httpBodyStream {
                        stream.open(); defer { stream.close() }
                        var data = Data()
                        var buffer = [UInt8](repeating: 0, count: 1024)
                        while stream.hasBytesAvailable {
                            let n = stream.read(&buffer, maxLength: buffer.count)
                            if n <= 0 { break }
                            data.append(buffer, count: n)
                        }
                        body = data
                    }
                    _bodies.append(String(decoding: body ?? Data(), as: UTF8.self))
                }
            }
        }

        private static let startJSON = """
        {"success":true,"error":null,"detail":"ok","data":{
          "device_code":"DEV123","code":"ABCD-1234",
          "verification_url":"https://torbox.app/link",
          "friendly_verification_url":"torbox.app/link?code=ABCD-1234",
          "interval":5,"expires_at":"2026-10-24T12:10:00Z"}}
        """

        private static func code(expiresAt: Date, interval: Int = 5) -> TorBoxDeviceCode {
            TorBoxDeviceCode(deviceCode: "DEV123", code: "ABCD-1234", verificationURL: "https://torbox.app/link",
                             friendlyVerificationURL: "torbox.app/link", interval: interval, expiresAt: expiresAt)
        }

        private static let pending = #"{"success":false,"error":"ITEM_NOT_FOUND","detail":"Not found","data":null}"#

        // MARK: start

        @Test func startDeviceCodeDecodes() async throws {
            let log = Log()
            MockURLProtocol.handler = { r in log.record(r); return Self.respond(r, json: Self.startJSON) }
            let code = try await client().startDeviceCode()
            #expect(code.deviceCode == "DEV123")
            #expect(code.code == "ABCD-1234")
            #expect(code.verificationURL == "https://torbox.app/link")
            #expect(code.friendlyVerificationURL == "torbox.app/link?code=ABCD-1234")
            #expect(code.interval == 5)
            #expect(code.expiresAt == ISO8601Timestamp.date(from: "2026-10-24T12:10:00Z"))
            let req = try #require(log.requests.first)
            #expect(req.httpMethod == "GET")
            #expect(req.url?.path == "/v1/api/user/auth/device/start")
            #expect(URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.queryItems
                    == [URLQueryItem(name: "app", value: "Seret")])
            #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
        }

        @Test func startDeviceCodeAcceptsFractionalExpiry() async throws {
            MockURLProtocol.handler = { r in
                Self.respond(r, json: Self.startJSON.replacingOccurrences(of: "12:10:00Z", with: "12:10:00.123456Z"))
            }
            let code = try await client().startDeviceCode()
            #expect(code.expiresAt.timeIntervalSince1970 > 1_700_000_000)
        }

        @Test func startDeviceCodeThrowsOnUnparseableExpiry() async {
            MockURLProtocol.handler = { r in
                Self.respond(r, json: Self.startJSON.replacingOccurrences(of: "2026-10-24T12:10:00Z", with: "soon"))
            }
            await #expect(throws: HTTPError.self) { _ = try await client().startDeviceCode() }
        }

        // MARK: poll

        @Test func awaitTokenPollsUntilToken() async throws {
            let log = Log()
            MockURLProtocol.handler = { r in
                log.record(r)
                if log.requests.count < 3 { return Self.respond(r, status: 400, json: Self.pending) }
                return Self.respond(r, json: #"{"success":true,"error":null,"detail":"ok","data":{"access_token":"TBKEY","token_type":"Bearer"}}"#)
            }
            let sleeps = SleepLog()
            let now = Date(timeIntervalSince1970: 1_000)
            let token = try await client().awaitToken(
                for: Self.code(expiresAt: now.addingTimeInterval(600)), now: { now },
                sleep: { await sleeps.add($0) })
            #expect(token == "TBKEY")
            #expect(log.requests.count == 3)
            #expect(await sleeps.all == [.seconds(5), .seconds(5)])
            let req = try #require(log.requests.first)
            #expect(req.httpMethod == "POST")
            #expect(req.url?.path == "/v1/api/user/auth/device/token")
            #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(log.bodies.first?.contains(#""device_code":"DEV123""#) == true)
        }

        @Test func awaitTokenTreatsDeviceCodeNotUsedAsPending() async throws {
            let log = Log()
            MockURLProtocol.handler = { r in
                log.record(r)
                if log.requests.count < 2 {
                    return Self.respond(r, status: 400, json: #"{"success":false,"error":"DEVICE_CODE_NOT_USED","detail":"wait","data":null}"#)
                }
                return Self.respond(r, json: #"{"success":true,"error":null,"detail":"ok","data":{"access_token":"K2","token_type":"Bearer"}}"#)
            }
            let now = Date(timeIntervalSince1970: 1_000)
            let token = try await client().awaitToken(
                for: Self.code(expiresAt: now.addingTimeInterval(600)), now: { now }, sleep: { _ in })
            #expect(token == "K2")
        }

        @Test func awaitTokenExpires() async {
            let log = Log()
            MockURLProtocol.handler = { r in log.record(r); return Self.respond(r, status: 400, json: Self.pending) }
            let clock = Clock0(Date(timeIntervalSince1970: 1_000))
            await #expect(throws: TorBoxAuthError.expired) {
                _ = try await client().awaitToken(
                    for: Self.code(expiresAt: Date(timeIntervalSince1970: 1_012), interval: 5),
                    now: { clock.now },
                    sleep: { d in clock.advance(by: d) })
            }
            // Polls at t=1000, 1005, 1010, 1015 (the last one lands past expiry and is not followed by another sleep).
            #expect(log.requests.count == 4)
        }

        @Test func awaitTokenRethrowsOtherErrors() async {
            MockURLProtocol.handler = { r in
                Self.respond(r, status: 400, json: #"{"success":false,"error":"DEVICE_CODE_USED","detail":"used","data":null}"#)
            }
            let now = Date(timeIntervalSince1970: 1_000)
            await #expect(throws: TorBoxError.api(code: "DEVICE_CODE_USED", detail: "used", status: 400)) {
                _ = try await client().awaitToken(
                    for: Self.code(expiresAt: now.addingTimeInterval(600)), now: { now }, sleep: { _ in })
            }
        }

        // MARK: validate

        @Test func validateReturnsUserAndSendsKey() async throws {
            let log = Log()
            MockURLProtocol.handler = { r in
                log.record(r)
                return Self.respond(r, json: #"{"success":true,"error":null,"detail":"ok","data":{"id":7,"email":"a@b.c","plan":2,"premium_expires_at":null}}"#)
            }
            let user = try await client().validate(key: "MYKEY")
            #expect(user.plan == 2)
            #expect(user.email == "a@b.c")
            let req = try #require(log.requests.first)
            #expect(req.url?.path == "/v1/api/user/me")
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer MYKEY")
        }

        @Test func validateRejectsBadToken() async {
            MockURLProtocol.handler = { r in
                Self.respond(r, status: 403, json: #"{"success":false,"error":"BAD_TOKEN","detail":"bad","data":null}"#)
            }
            await #expect(throws: TorBoxAuthError.invalidKey) { _ = try await client().validate(key: "nope") }
        }

        @Test func validatePassesThroughOtherFailures() async {
            MockURLProtocol.handler = { r in Self.respond(r, status: 429, json: "{}") }
            await #expect(throws: TorBoxError.rateLimited(retryAfter: nil)) {
                _ = try await client().validate(key: "k")
            }
        }
    }
}

/// Collects the durations passed to an injected `sleep`.
actor SleepLog {
    private(set) var all: [Duration] = []
    func add(_ d: Duration) { all.append(d) }
}

/// A controllable clock for the poll loop.
final class Clock0: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ d: Date) { current = d }
    var now: Date { lock.withLock { current } }
    func advance(by d: Duration) {
        let secs = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        lock.withLock { current = current.addingTimeInterval(secs) }
    }
}

@Suite struct TorBoxDeviceCodeTests {
    @Test func asDeviceCodeMapsFields() {
        let now = Date(timeIntervalSince1970: 1_000)
        let code = TorBoxDeviceCode(deviceCode: "DEV", code: "ABCD", verificationURL: "https://torbox.app/link",
                                    friendlyVerificationURL: "torbox.app/link", interval: 5,
                                    expiresAt: now.addingTimeInterval(600))
        let rd = code.asDeviceCode(now: now)
        #expect(rd.deviceCode == "DEV")
        #expect(rd.userCode == "ABCD")
        #expect(rd.verificationURL == "torbox.app/link")
        #expect(rd.interval == 5)
        #expect(rd.expiresIn == 600)
    }

    @Test func asDeviceCodeClampsExpiredToZero() {
        let now = Date(timeIntervalSince1970: 1_000)
        let code = TorBoxDeviceCode(deviceCode: "D", code: "C", verificationURL: "u", friendlyVerificationURL: "f",
                                    interval: 5, expiresAt: now.addingTimeInterval(-30))
        #expect(code.asDeviceCode(now: now).expiresIn == 0)
    }
}

@Suite struct TorBoxSessionTests {
    @Test func sessionRoundTrip() async throws {
        let session = TorBoxSession(store: InMemorySecretStore())
        #expect(await session.isSignedIn == false)
        await #expect(throws: TorBoxSessionError.notSignedIn) { _ = try await session.validAccessToken() }

        try await session.establish(key: "KEY")
        #expect(await session.isSignedIn)
        #expect(try await session.validAccessToken() == "KEY")

        try await session.signOut()
        #expect(await session.isSignedIn == false)
        await #expect(throws: TorBoxSessionError.notSignedIn) { _ = try await session.validAccessToken() }
    }

    @Test func sessionPersistsAcrossInstances() async throws {
        let store = InMemorySecretStore()
        try await TorBoxSession(store: store).establish(key: "KEY")
        #expect(try await TorBoxSession(store: store).validAccessToken() == "KEY")
    }

    @Test func establishTrimsPastedKey() async throws {
        let session = TorBoxSession(store: InMemorySecretStore())
        try await session.establish(key: "  KEY \n")
        #expect(try await session.validAccessToken() == "KEY")
        try await session.establish(key: "   ")
        #expect(await session.isSignedIn == false)
    }
}
