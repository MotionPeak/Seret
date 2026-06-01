# DebridCore Foundation & Real-Debrid Auth — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `DebridCore` Swift package with a tested async `HTTPClient` and a working Real-Debrid OAuth2 **device-code** sign-in (acquire token → refresh → store securely).

**Architecture:** Pure, UI-free SPM package, testable with `swift test` (no simulator). A small async `HTTPClient` over `URLSession`, mocked in tests via a custom `URLProtocol`. `RealDebridAuthClient` implements RD's device-code endpoints as discrete, individually-testable calls. Tokens persist behind a `TokenStore` protocol — `KeychainTokenStore` in production, `InMemoryTokenStore` in tests. A `RealDebridSession` actor owns the token lifecycle (validity + transparent refresh). No third-party dependencies.

**Tech Stack:** Swift 6.3 (Swift 6 language mode), Swift Package Manager, async/await, Swift Testing, `URLSession`, `Security` (Keychain).

**Plan 1 of 5** (see `docs/superpowers/specs/2026-06-02-seret-design.md` §3). Produces: `DebridCore` can authenticate to Real-Debrid and keep a valid token.

---

## File Structure

| File | Responsibility |
|---|---|
| `Packages/DebridCore/Package.swift` | Package manifest; `DebridCore` library + test target |
| `Sources/DebridCore/Networking/HTTPError.swift` | Typed networking error |
| `Sources/DebridCore/Networking/HTTPClient.swift` | Async GET/POST over URLSession, JSON decode, error mapping |
| `Sources/DebridCore/RealDebrid/RealDebridAuthModels.swift` | `RDDeviceCode`, `RDDeviceCredentials`, `RDToken` |
| `Sources/DebridCore/RealDebrid/RealDebridAuthClient.swift` | Device-code endpoints (start, poll, token, refresh) |
| `Sources/DebridCore/RealDebrid/TokenStore.swift` | `TokenStore` protocol + `StoredCredentials` + `InMemoryTokenStore` |
| `Sources/DebridCore/RealDebrid/KeychainTokenStore.swift` | Keychain-backed `TokenStore` |
| `Sources/DebridCore/RealDebrid/RealDebridSession.swift` | Actor: token validity + transparent refresh |
| `Tests/DebridCoreTests/Support/MockURLProtocol.swift` | Stubs network responses for tests |
| `Tests/DebridCoreTests/HTTPClientTests.swift` | HTTPClient behavior |
| `Tests/DebridCoreTests/RealDebridAuthClientTests.swift` | Device-flow endpoint decoding + pending handling |
| `Tests/DebridCoreTests/TokenStoreTests.swift` | In-memory store round-trip |
| `Tests/DebridCoreTests/RealDebridSessionTests.swift` | Refresh-on-expiry lifecycle |

---

## Task 1: Create the DebridCore package

**Files:**
- Create: `Packages/DebridCore/Package.swift`
- Create: `Packages/DebridCore/Sources/DebridCore/DebridCore.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/SmokeTests.swift`

- [ ] **Step 1: Write the manifest**

`Packages/DebridCore/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DebridCore",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "DebridCore", targets: ["DebridCore"]),
    ],
    targets: [
        .target(name: "DebridCore"),
        .testTarget(name: "DebridCoreTests", dependencies: ["DebridCore"]),
    ]
)
```

- [ ] **Step 2: Add a placeholder source + a smoke test**

`Sources/DebridCore/DebridCore.swift`:
```swift
/// Marker for the DebridCore module. Real types live in subfolders.
public enum DebridCore {
    public static let name = "DebridCore"
}
```

`Tests/DebridCoreTests/SmokeTests.swift`:
```swift
import Testing
@testable import DebridCore

@Test func moduleLoads() {
    #expect(DebridCore.name == "DebridCore")
}
```

- [ ] **Step 3: Run the test suite to confirm the harness works**

Run: `swift test --package-path Packages/DebridCore`
Expected: builds, 1 test passes.

- [ ] **Step 4: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): scaffold DebridCore package"
```

---

## Task 2: HTTPClient + HTTPError

**Files:**
- Create: `Sources/DebridCore/Networking/HTTPError.swift`
- Create: `Sources/DebridCore/Networking/HTTPClient.swift`
- Create: `Tests/DebridCoreTests/Support/MockURLProtocol.swift`
- Create: `Tests/DebridCoreTests/HTTPClientTests.swift`

- [ ] **Step 1: Write the test support — MockURLProtocol**

`Tests/DebridCoreTests/Support/MockURLProtocol.swift`:
```swift
import Foundation

/// Intercepts requests on a dedicated URLSession and returns canned responses.
/// Tests that use it must run serialized (see @Suite(.serialized)).
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func stub(status: Int, json: String) {
        handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

extension URLSession {
    /// A session whose traffic is served by MockURLProtocol.
    static var mock: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
```

- [ ] **Step 2: Write the failing test**

`Tests/DebridCoreTests/HTTPClientTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

@Suite(.serialized)
struct HTTPClientTests {
    struct Probe: Decodable, Equatable { let value: Int }

    @Test func getDecodesJSON() async throws {
        MockURLProtocol.stub(status: 200, json: #"{"value":42}"#)
        let client = HTTPClient(session: .mock)
        let out: Probe = try await client.get(URL(string: "https://example.com/x")!)
        #expect(out == Probe(value: 42))
    }

    @Test func nonSuccessStatusThrowsStatusError() async throws {
        MockURLProtocol.stub(status: 503, json: #"{"error":"down"}"#)
        let client = HTTPClient(session: .mock)
        await #expect(throws: HTTPError.self) {
            let _: Probe = try await client.get(URL(string: "https://example.com/x")!)
        }
    }

    @Test func postEncodesForm() async throws {
        let body = HTTPClient.encodeForm(["a": "1", "b": "x y"])
        #expect(body.contains("a=1"))
        #expect(body.contains("b=x%20y"))
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter HTTPClientTests`
Expected: FAIL — `HTTPClient` / `HTTPError` not defined.

- [ ] **Step 4: Implement HTTPError**

`Sources/DebridCore/Networking/HTTPError.swift`:
```swift
import Foundation

public enum HTTPError: Error, Equatable, Sendable {
    case transport(String)
    case status(code: Int, body: String)
    case decoding(String)
}
```

- [ ] **Step 5: Implement HTTPClient**

`Sources/DebridCore/Networking/HTTPClient.swift`:
```swift
import Foundation

public struct HTTPClient: Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    public func get<T: Decodable>(_ url: URL, headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        return try await send(request)
    }

    public func post<T: Decodable>(_ url: URL, form: [String: String], headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = Data(Self.encodeForm(form).utf8)
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HTTPError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError.status(code: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HTTPError.decoding(String(describing: error))
        }
    }

    /// `application/x-www-form-urlencoded` body builder. Percent-encodes keys and values.
    public static func encodeForm(_ form: [String: String]) -> String {
        form.map { key, value in
            "\(percentEncode(key))=\(percentEncode(value))"
        }
        .sorted()
        .joined(separator: "&")
    }

    private static func percentEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter HTTPClientTests`
Expected: PASS (3 tests). Note `b=x%20y` — space encodes to `%20`.

- [ ] **Step 7: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): add async HTTPClient with typed errors"
```

---

## Task 3: Real-Debrid auth models + device-code client

**Files:**
- Create: `Sources/DebridCore/RealDebrid/RealDebridAuthModels.swift`
- Create: `Sources/DebridCore/RealDebrid/RealDebridAuthClient.swift`
- Create: `Tests/DebridCoreTests/RealDebridAuthClientTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/DebridCoreTests/RealDebridAuthClientTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

@Suite(.serialized)
struct RealDebridAuthClientTests {
    @Test func startDeviceCodeDecodes() async throws {
        MockURLProtocol.stub(status: 200, json: #"""
        {"device_code":"DC","user_code":"LF2NKTKX","interval":5,
         "expires_in":1800,"verification_url":"https://real-debrid.com/device"}
        """#)
        let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
        let code = try await client.startDeviceCode()
        #expect(code.userCode == "LF2NKTKX")
        #expect(code.interval == 5)
        #expect(code.verificationURL == "https://real-debrid.com/device")
    }

    @Test func pollCredentialsReturnsNilWhilePending() async throws {
        MockURLProtocol.stub(status: 400, json: #"{"error":"authorization_pending"}"#)
        let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
        let creds = try await client.pollCredentials(deviceCode: "DC")
        #expect(creds == nil)
    }

    @Test func pollCredentialsReturnsCredentialsWhenAuthorized() async throws {
        MockURLProtocol.stub(status: 200, json: #"{"client_id":"CID","client_secret":"CSECRET"}"#)
        let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
        let creds = try await client.pollCredentials(deviceCode: "DC")
        #expect(creds?.clientID == "CID")
        #expect(creds?.clientSecret == "CSECRET")
    }

    @Test func requestTokenDecodes() async throws {
        MockURLProtocol.stub(status: 200, json: #"""
        {"access_token":"AT","expires_in":3600,"token_type":"Bearer","refresh_token":"RT"}
        """#)
        let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
        let token = try await client.requestToken(
            deviceCode: "DC",
            credentials: .init(clientID: "CID", clientSecret: "CSECRET"))
        #expect(token.accessToken == "AT")
        #expect(token.refreshToken == "RT")
        #expect(token.expiresIn == 3600)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter RealDebridAuthClientTests`
Expected: FAIL — models/client not defined.

- [ ] **Step 3: Implement the models**

`Sources/DebridCore/RealDebrid/RealDebridAuthModels.swift`:
```swift
import Foundation

public struct RDDeviceCode: Decodable, Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let interval: Int
    public let expiresIn: Int
    public let verificationURL: String

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case interval
        case expiresIn = "expires_in"
        case verificationURL = "verification_url"
    }
}

public struct RDDeviceCredentials: Codable, Sendable, Equatable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }
}

public struct RDToken: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int
    public let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}
```

- [ ] **Step 4: Implement the client**

`Sources/DebridCore/RealDebrid/RealDebridAuthClient.swift`:
```swift
import Foundation

/// Real-Debrid OAuth2 device-code flow using the public open-source client id
/// (`X245A4XAIBGVM`) — no client secret required to start. See spec §5.2.
public struct RealDebridAuthClient: Sendable {
    public static let openSourceClientID = "X245A4XAIBGVM"

    private static let base = URL(string: "https://api.real-debrid.com")!
    private static let grantType = "http://oauth.net/grant_type/device/1.0"

    private let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public func startDeviceCode(clientID: String = openSourceClientID) async throws -> RDDeviceCode {
        var comps = URLComponents(
            url: Self.base.appending(path: "/oauth/v2/device/code"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "new_credentials", value: "yes"),
        ]
        return try await http.get(comps.url!)
    }

    /// One poll attempt. Returns credentials once authorized; `nil` while pending.
    public func pollCredentials(deviceCode: String,
                                clientID: String = openSourceClientID) async throws -> RDDeviceCredentials? {
        var comps = URLComponents(
            url: Self.base.appending(path: "/oauth/v2/device/credentials"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "code", value: deviceCode),
        ]
        do {
            let credentials: RDDeviceCredentials = try await http.get(comps.url!)
            return credentials
        } catch let HTTPError.status(code, _) where code == 400 || code == 403 {
            return nil  // authorization_pending
        }
    }

    public func requestToken(deviceCode: String,
                             credentials: RDDeviceCredentials) async throws -> RDToken {
        try await http.post(
            Self.base.appending(path: "/oauth/v2/token"),
            form: [
                "client_id": credentials.clientID,
                "client_secret": credentials.clientSecret,
                "code": deviceCode,
                "grant_type": Self.grantType,
            ])
    }

    public func refresh(token: RDToken,
                        credentials: RDDeviceCredentials) async throws -> RDToken {
        try await http.post(
            Self.base.appending(path: "/oauth/v2/token"),
            form: [
                "client_id": credentials.clientID,
                "client_secret": credentials.clientSecret,
                "code": token.refreshToken,
                "grant_type": Self.grantType,
            ])
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter RealDebridAuthClientTests`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): Real-Debrid device-code auth client"
```

---

## Task 4: TokenStore + Keychain storage

**Files:**
- Create: `Sources/DebridCore/RealDebrid/TokenStore.swift`
- Create: `Sources/DebridCore/RealDebrid/KeychainTokenStore.swift`
- Create: `Tests/DebridCoreTests/TokenStoreTests.swift`

- [ ] **Step 1: Write the failing test** (in-memory store is the unit-tested one; Keychain is verified manually on-device)

`Tests/DebridCoreTests/TokenStoreTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

struct TokenStoreTests {
    private func sample() -> StoredCredentials {
        StoredCredentials(
            token: RDToken(accessToken: "AT", refreshToken: "RT", expiresIn: 3600, tokenType: "Bearer"),
            deviceCredentials: RDDeviceCredentials(clientID: "CID", clientSecret: "CSECRET"),
            obtainedAt: Date(timeIntervalSince1970: 1_000_000))
    }

    @Test func savesAndLoads() throws {
        let store = InMemoryTokenStore()
        #expect(try store.load() == nil)
        try store.save(sample())
        #expect(try store.load() == sample())
    }

    @Test func clearsCredentials() throws {
        let store = InMemoryTokenStore()
        try store.save(sample())
        try store.clear()
        #expect(try store.load() == nil)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter TokenStoreTests`
Expected: FAIL — `TokenStore` / `StoredCredentials` / `InMemoryTokenStore` not defined.

- [ ] **Step 3: Implement the protocol + model + in-memory store**

`Sources/DebridCore/RealDebrid/TokenStore.swift`:
```swift
import Foundation

/// Everything needed to make and refresh authenticated RD calls.
public struct StoredCredentials: Codable, Sendable, Equatable {
    public var token: RDToken
    public var deviceCredentials: RDDeviceCredentials
    public var obtainedAt: Date

    public init(token: RDToken, deviceCredentials: RDDeviceCredentials, obtainedAt: Date) {
        self.token = token
        self.deviceCredentials = deviceCredentials
        self.obtainedAt = obtainedAt
    }
}

public protocol TokenStore: Sendable {
    func load() throws -> StoredCredentials?
    func save(_ credentials: StoredCredentials) throws
    func clear() throws
}

/// Test/double implementation. Thread-safe.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: StoredCredentials?

    public init() {}

    public func load() throws -> StoredCredentials? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
    public func save(_ credentials: StoredCredentials) throws {
        lock.lock(); defer { lock.unlock() }
        stored = credentials
    }
    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}
```

- [ ] **Step 4: Implement the Keychain store**

`Sources/DebridCore/RealDebrid/KeychainTokenStore.swift`:
```swift
import Foundation
import Security

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

/// Stores the credentials JSON blob as a generic-password Keychain item.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "com.solomons.seret.realdebrid",
                account: String = "credentials") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() throws -> StoredCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return try JSONDecoder().decode(StoredCredentials.self, from: data)
    }

    public func save(_ credentials: StoredCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else {
            guard updateStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(updateStatus) }
        }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter TokenStoreTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): TokenStore protocol + Keychain & in-memory stores"
```

---

## Task 5: RealDebridSession — token lifecycle with transparent refresh

**Files:**
- Create: `Sources/DebridCore/RealDebrid/RealDebridSession.swift`
- Create: `Tests/DebridCoreTests/RealDebridSessionTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/DebridCoreTests/RealDebridSessionTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

@Suite(.serialized)
struct RealDebridSessionTests {
    private func creds(expiresIn: Int, obtainedAt: Date) -> StoredCredentials {
        StoredCredentials(
            token: RDToken(accessToken: "AT-OLD", refreshToken: "RT", expiresIn: expiresIn, tokenType: "Bearer"),
            deviceCredentials: RDDeviceCredentials(clientID: "CID", clientSecret: "CSECRET"),
            obtainedAt: obtainedAt)
    }

    @Test func returnsNotSignedInWhenEmpty() async throws {
        let session = RealDebridSession(
            auth: RealDebridAuthClient(http: HTTPClient(session: .mock)),
            store: InMemoryTokenStore())
        await #expect(throws: RealDebridSessionError.notSignedIn) {
            _ = try await session.validAccessToken()
        }
    }

    @Test func returnsCachedTokenWhenStillValid() async throws {
        let store = InMemoryTokenStore()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        try store.save(creds(expiresIn: 3600, obtainedAt: t0))
        let session = RealDebridSession(
            auth: RealDebridAuthClient(http: HTTPClient(session: .mock)),
            store: store,
            now: { t0.addingTimeInterval(60) })  // only 1 min elapsed
        let token = try await session.validAccessToken()
        #expect(token == "AT-OLD")
    }

    @Test func refreshesWhenExpired() async throws {
        let store = InMemoryTokenStore()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        try store.save(creds(expiresIn: 3600, obtainedAt: t0))
        MockURLProtocol.stub(status: 200, json: #"""
        {"access_token":"AT-NEW","expires_in":3600,"token_type":"Bearer","refresh_token":"RT2"}
        """#)
        let session = RealDebridSession(
            auth: RealDebridAuthClient(http: HTTPClient(session: .mock)),
            store: store,
            now: { t0.addingTimeInterval(3600) })  // fully elapsed → expired
        let token = try await session.validAccessToken()
        #expect(token == "AT-NEW")
        #expect(try store.load()?.token.refreshToken == "RT2")  // persisted
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter RealDebridSessionTests`
Expected: FAIL — `RealDebridSession` / `RealDebridSessionError` not defined.

- [ ] **Step 3: Implement the session actor**

`Sources/DebridCore/RealDebrid/RealDebridSession.swift`:
```swift
import Foundation

public enum RealDebridSessionError: Error, Equatable {
    case notSignedIn
}

/// Owns the RD credential lifecycle: serves a valid access token, refreshing
/// transparently when the current one is within `refreshSkew` of expiry.
public actor RealDebridSession {
    private let auth: RealDebridAuthClient
    private let store: TokenStore
    private let now: @Sendable () -> Date
    private let refreshSkew: TimeInterval

    private var cached: StoredCredentials?

    public init(auth: RealDebridAuthClient = .init(),
                store: TokenStore,
                now: @escaping @Sendable () -> Date = { Date() },
                refreshSkew: TimeInterval = 60) {
        self.auth = auth
        self.store = store
        self.now = now
        self.refreshSkew = refreshSkew
    }

    /// Persist a freshly completed device-code login.
    public func establish(token: RDToken, deviceCredentials: RDDeviceCredentials) throws {
        let creds = StoredCredentials(token: token, deviceCredentials: deviceCredentials, obtainedAt: now())
        try store.save(creds)
        cached = creds
    }

    public func validAccessToken() async throws -> String {
        guard let creds = try currentCredentials() else { throw RealDebridSessionError.notSignedIn }
        guard isExpired(creds) else { return creds.token.accessToken }

        let refreshed = try await auth.refresh(token: creds.token, credentials: creds.deviceCredentials)
        let updated = StoredCredentials(token: refreshed,
                                        deviceCredentials: creds.deviceCredentials,
                                        obtainedAt: now())
        try store.save(updated)
        cached = updated
        return refreshed.accessToken
    }

    public func signOut() throws {
        try store.clear()
        cached = nil
    }

    private func currentCredentials() throws -> StoredCredentials? {
        if let cached { return cached }
        cached = try store.load()
        return cached
    }

    private func isExpired(_ creds: StoredCredentials) -> Bool {
        let expiry = creds.obtainedAt.addingTimeInterval(TimeInterval(creds.token.expiresIn) - refreshSkew)
        return now() >= expiry
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter RealDebridSessionTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full suite**

Run: `swift test --package-path Packages/DebridCore`
Expected: all tests pass (smoke + HTTPClient + auth client + token store + session).

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): RealDebridSession with transparent token refresh"
```

---

## Done when

- [ ] `swift test --package-path Packages/DebridCore` is green.
- [ ] `DebridCore` exposes: `HTTPClient`, `RealDebridAuthClient` (start/poll/requestToken/refresh), `TokenStore` (+ Keychain & in-memory), `RealDebridSession.validAccessToken()`.
- [ ] No secrets or tokens are logged anywhere.
- [ ] All work committed.

**Next:** Plan 2 — RD resources (`/torrents`, `/torrents/info`, `/unrestrict/link`) + Metadata (`FilenameParser` + TMDB) + library grouping.
