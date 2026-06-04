# RD API-token sign-in + device-code reuse — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a throttle-proof "sign in with a Real-Debrid API token" path (secondary to device-code) and make the device-code flow reuse a still-valid code on retry.

**Architecture:** A personal RD token is a static Bearer token. Model it with an `isStatic` flag on `StoredCredentials`; `RealDebridSession.validAccessToken()` returns it directly (never refreshes). The app adds an `AuthFlow.signIn(token:)` seam, a `SignInModel.signInWithToken`, and a token-entry UI on `SignInView`. Separately, `SignInModel` caches the device code and reuses it within its `expiresIn` so retries stop hammering RD's throttled `device/code` endpoint. All RD logic stays in DebridCore (one brain); resource clients are untouched (they authenticate via `AccessTokenProviding`).

**Tech Stack:** Swift 6, Swift Testing (DebridCore, no sim), XCTest-host app target on the tvOS sim, SwiftUI (tvOS 18).

**Reference:** Design spec `docs/superpowers/specs/2026-06-04-rd-token-auth-design.md`. Branch `feat/rd-token-auth` (spec already committed there). tvOS sim is **"Apple TV 4K (3rd generation)"**.

---

## Task 1: `StoredCredentials.isStatic` flag (TDD)

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/RealDebrid/TokenStore.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/StoredCredentialsCodableTests.swift` (new)

- [ ] **Step 1: Write the failing test** (`StoredCredentialsCodableTests.swift`)

```swift
import Testing
import Foundation
@testable import DebridCore

@Suite struct StoredCredentialsCodableTests {
    @Test func decodesLegacyJSONWithoutIsStaticAsFalse() throws {
        // Credentials persisted before the isStatic field existed must still load.
        let json = #"""
        {"token":{"access_token":"AT","refresh_token":"RT","expires_in":3600,"token_type":"Bearer"},
         "deviceCredentials":{"client_id":"CID","client_secret":"CS"},
         "obtainedAt":700000000}
        """#
        let creds = try JSONDecoder().decode(StoredCredentials.self, from: Data(json.utf8))
        #expect(creds.isStatic == false)
        #expect(creds.token.accessToken == "AT")
    }

    @Test func roundTripsIsStaticTrue() throws {
        let original = StoredCredentials(
            token: RDToken(accessToken: "AT", refreshToken: "", expiresIn: 0, tokenType: "Bearer"),
            deviceCredentials: RDDeviceCredentials(clientID: "", clientSecret: ""),
            obtainedAt: Date(timeIntervalSinceReferenceDate: 700_000_000),
            isStatic: true)
        let decoded = try JSONDecoder().decode(StoredCredentials.self,
                                               from: try JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.isStatic == true)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret/Packages/DebridCore && swift test --filter StoredCredentialsCodableTests 2>&1 | tail -15`
Expected: FAIL — `value of type 'StoredCredentials' has no member 'isStatic'` (won't compile).

- [ ] **Step 3: Add `isStatic` to `StoredCredentials`**

Replace the `StoredCredentials` struct in `TokenStore.swift` with:
```swift
/// Everything needed to make and refresh authenticated RD calls.
/// A `isStatic` credential is a personal API token (no refresh, no device creds).
public struct StoredCredentials: Codable, Sendable, Equatable {
    public let token: RDToken
    public let deviceCredentials: RDDeviceCredentials
    public let obtainedAt: Date
    public let isStatic: Bool

    public init(token: RDToken, deviceCredentials: RDDeviceCredentials,
                obtainedAt: Date, isStatic: Bool = false) {
        self.token = token
        self.deviceCredentials = deviceCredentials
        self.obtainedAt = obtainedAt
        self.isStatic = isStatic
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decode(RDToken.self, forKey: .token)
        deviceCredentials = try c.decode(RDDeviceCredentials.self, forKey: .deviceCredentials)
        obtainedAt = try c.decode(Date.self, forKey: .obtainedAt)
        isStatic = try c.decodeIfPresent(Bool.self, forKey: .isStatic) ?? false
    }
}
```
(The memberwise init keeps the existing 3-arg call sites compiling; the custom `init(from:)` makes `isStatic` optional in stored JSON; `encode(to:)` and `CodingKeys` stay synthesized.)

- [ ] **Step 4: Run to verify it passes, then the full package**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret/Packages/DebridCore && swift test --filter StoredCredentialsCodableTests 2>&1 | tail -8` → PASS (2 tests).
Then: `swift test 2>&1 | tail -5` → all green (was 124 → 126).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/RealDebrid/TokenStore.swift \
        Packages/DebridCore/Tests/DebridCoreTests/StoredCredentialsCodableTests.swift
git commit -m "feat(auth): StoredCredentials.isStatic flag (back-compat Codable)"
```

---

## Task 2: `RealDebridSession.establishStaticToken` + no-refresh short-circuit (TDD)

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/RealDebrid/RealDebridSession.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/RealDebridSessionStaticTokenTests.swift` (new)

- [ ] **Step 1: Write the failing test** (nested under `MockTests`)

```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct RealDebridSessionStaticTokenTests {
        init() { MockURLProtocol.handler = nil }

        @Test func staticTokenReturnedWithoutRefresh() async throws {
            // A refresh stub is armed; if validAccessToken refreshed, it would return AT-REFRESHED.
            MockURLProtocol.stub(status: 200, json: #"""
            {"access_token":"AT-REFRESHED","expires_in":3600,"token_type":"Bearer","refresh_token":"RT2"}
            """#)
            let store = InMemoryTokenStore()
            let session = RealDebridSession(
                auth: RealDebridAuthClient(http: HTTPClient(session: .mock)),
                store: store,
                now: { Date(timeIntervalSince1970: 1_000_000) })

            try await session.establishStaticToken("STATIC-TOK")
            let token = try await session.validAccessToken()

            #expect(token == "STATIC-TOK")           // not AT-REFRESHED → no refresh occurred
            #expect(try store.load()?.isStatic == true)
            #expect(try store.load()?.token.accessToken == "STATIC-TOK")
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret/Packages/DebridCore && swift test --filter RealDebridSessionStaticTokenTests 2>&1 | tail -15`
Expected: FAIL — `value of type 'RealDebridSession' has no member 'establishStaticToken'`.

- [ ] **Step 3: Implement in `RealDebridSession.swift`**

Add this method next to `establish(...)`:
```swift
    /// Persist a personal API token (real-debrid.com/apitoken). Static: no refresh token,
    /// no device credentials — `validAccessToken()` returns it as-is and never refreshes.
    public func establishStaticToken(_ token: String) throws {
        let creds = StoredCredentials(
            token: RDToken(accessToken: token, refreshToken: "", expiresIn: 0, tokenType: "Bearer"),
            deviceCredentials: RDDeviceCredentials(clientID: "", clientSecret: ""),
            obtainedAt: now(),
            isStatic: true)
        try store.save(creds)
        cached = creds
    }
```
And add the short-circuit at the top of `validAccessToken()`, immediately after the `guard let creds`:
```swift
    public func validAccessToken() async throws -> String {
        guard let creds = try currentCredentials() else { throw RealDebridSessionError.notSignedIn }
        if creds.isStatic { return creds.token.accessToken }   // personal token: never refresh
        guard isExpired(creds) else { return creds.token.accessToken }
        let refreshed = try await refreshedCredentials(replacing: creds)
        return refreshed.token.accessToken
    }
```

- [ ] **Step 4: Run to verify it passes, then the full package**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret/Packages/DebridCore && swift test --filter RealDebridSessionStaticTokenTests 2>&1 | tail -8` → PASS (1 test).
Then: `swift test 2>&1 | tail -5` → all green (126 → 127).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/RealDebrid/RealDebridSession.swift \
        Packages/DebridCore/Tests/DebridCoreTests/RealDebridSessionStaticTokenTests.swift
git commit -m "feat(auth): RealDebridSession.establishStaticToken (no-refresh static token)"
```

---

## Task 3: `RealDebridAuthClient.validateToken` (TDD)

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/RealDebrid/RealDebridAuthClient.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/RealDebridValidateTokenTests.swift` (new)

- [ ] **Step 1: Write the failing test** (nested under `MockTests`)

```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct RealDebridValidateTokenTests {
        init() { MockURLProtocol.handler = nil }

        @Test func trueWhenUserEndpointReturns200() async throws {
            MockURLProtocol.stub(status: 200, json: #"{"id":123,"username":"neo"}"#)
            let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
            #expect(try await client.validateToken("TOK") == true)
        }

        @Test func falseWhenUnauthorized() async throws {
            MockURLProtocol.stub(status: 401, json: #"{"error":"bad_token"}"#)
            let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
            #expect(try await client.validateToken("TOK") == false)
        }

        @Test func rethrowsOnServerError() async {
            MockURLProtocol.stub(status: 500, json: #"{"error":"server"}"#)
            let client = RealDebridAuthClient(http: HTTPClient(session: .mock))
            await #expect(throws: (any Error).self) {
                _ = try await client.validateToken("TOK")
            }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret/Packages/DebridCore && swift test --filter RealDebridValidateTokenTests 2>&1 | tail -15`
Expected: FAIL — `value of type 'RealDebridAuthClient' has no member 'validateToken'`.

- [ ] **Step 3: Implement in `RealDebridAuthClient.swift`**

Add this method to the struct:
```swift
    /// Confirms a personal API token by calling the authenticated user endpoint.
    /// `true` on success, `false` if RD rejects the token (401/403); other errors rethrow
    /// so callers can distinguish a bad token from a transport failure. Never logs the token.
    public func validateToken(_ token: String) async throws -> Bool {
        struct UserProbe: Decodable { let id: Int }
        let url = Self.base.appending(path: "/rest/1.0/user")
        do {
            let _: UserProbe = try await http.get(url, headers: ["Authorization": "Bearer \(token)"])
            return true
        } catch HTTPError.status(401, _), HTTPError.status(403, _) {
            return false
        }
    }
```

- [ ] **Step 4: Run to verify it passes, then the full package**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret/Packages/DebridCore && swift test --filter RealDebridValidateTokenTests 2>&1 | tail -8` → PASS (3 tests).
Then: `swift test 2>&1 | tail -5` → all green (127 → 130).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/RealDebrid/RealDebridAuthClient.swift \
        Packages/DebridCore/Tests/DebridCoreTests/RealDebridValidateTokenTests.swift
git commit -m "feat(auth): RealDebridAuthClient.validateToken via /rest/1.0/user"
```

---

## Task 4: App token sign-in path — `AuthFlow.signIn` + `SignInModel.signInWithToken` (TDD)

**Files:**
- Modify: `Apps/SeretTV/Auth/AuthFlow.swift` (protocol + `LiveAuthFlow` + `TokenSignInError`)
- Modify: `Apps/SeretTV/Auth/SignInModel.swift` (`.validatingToken`, `signInWithToken`, message)
- Modify: `Apps/SeretTVTests/SignInModelTests.swift` (`FakeAuthFlow.signIn` + 3 tests)

- [ ] **Step 1: Add the seam + error to `AuthFlow.swift`**

Add the method to the protocol and `LiveAuthFlow`, plus the error type:
```swift
/// Thrown when a pasted personal API token is rejected by Real-Debrid.
enum TokenSignInError: Error, Equatable { case invalidToken }
```
In `protocol AuthFlow`, add:
```swift
    /// Validate + persist a personal API token (real-debrid.com/apitoken). No device-code dance.
    func signIn(token: String) async throws
```
In `struct LiveAuthFlow`, add:
```swift
    func signIn(token: String) async throws {
        guard try await auth.validateToken(token) else { throw TokenSignInError.invalidToken }
        try await session.establishStaticToken(token)
    }
```

- [ ] **Step 2: Write the failing `SignInModel` token tests**

In `SignInModelTests.swift`, extend `FakeAuthFlow` with token support (add to the class body):
```swift
    var tokenSignInError: Error?
    private(set) var tokenCalls = 0
    private(set) var lastToken: String?
    func signIn(token: String) async throws {
        tokenCalls += 1
        lastToken = token
        if let tokenSignInError { throw tokenSignInError }
    }
```
Add these tests to `SignInModelTests`:
```swift
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
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodebuild test -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' -only-testing:SeretTVTests/SignInModelTests 2>&1 | tail -20`
Expected: FAIL — `value of type 'SignInModel' has no member 'signInWithToken'`. (If the sim shows `Pseudo Terminal Setup Error 7/6`, STOP and report BLOCKED — pty/sim, not code.)

- [ ] **Step 4: Implement in `SignInModel.swift`**

Add `.validatingToken` to `Phase`:
```swift
    enum Phase: Equatable {
        case idle
        case requestingCode
        case awaitingAuthorization(RDDeviceCode)
        case validatingToken
        case signedIn
        case failed(String)
    }
```
Add the method (next to `run()`):
```swift
    /// Sign in with a pasted personal API token instead of the device-code flow.
    func signInWithToken(_ token: String) async {
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
```
Add a case to `message(for:)` (before `default`):
```swift
        case TokenSignInError.invalidToken:
            return "That token wasn't accepted by Real\u{2011}Debrid. Check it and try again."
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodebuild test -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' -only-testing:SeretTVTests/SignInModelTests 2>&1 | tail -12`
Expected: PASS (existing 2 + new 3 = 5 tests).

- [ ] **Step 6: Commit**

```bash
git add Apps/SeretTV/Auth/AuthFlow.swift Apps/SeretTV/Auth/SignInModel.swift \
        Apps/SeretTVTests/SignInModelTests.swift
git commit -m "feat(auth): token sign-in path (AuthFlow.signIn + SignInModel.signInWithToken)"
```

---

## Task 5: Device-code reuse hardening in `SignInModel` (TDD)

**Files:**
- Modify: `Apps/SeretTV/Auth/SignInModel.swift` (`now` injection + cache + reuse in `run()`)
- Modify: `Apps/SeretTVTests/SignInModelTests.swift` (2 reuse tests)

- [ ] **Step 1: Write the failing reuse tests**

Add to `SignInModelTests`:
```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodebuild test -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' -only-testing:SeretTVTests/SignInModelTests 2>&1 | tail -20`
Expected: FAIL — `SignInModel` has no `now:` parameter (the `init` call with `now:` won't compile).

- [ ] **Step 3: Implement the cache + reuse in `SignInModel.swift`**

Add stored state + the `now` clock. Change the init and add fields:
```swift
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
```
Replace `run()` with the reuse-aware version:
```swift
    /// Run the full flow once. Reuses a still-valid device code on retry so repeated
    /// attempts don't re-hit RD's throttled `device/code` endpoint.
    func run() async {
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
```

- [ ] **Step 4: Run to verify it passes (whole suite)**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodebuild test -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' -only-testing:SeretTVTests/SignInModelTests 2>&1 | tail -12`
Expected: PASS (now 7: 2 original + 3 token + 2 reuse). The original `happyPathReachesSignedIn` / `failureThenRetrySucceeds` still pass (they don't assert `beginCalls` after retry).

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretTV/Auth/SignInModel.swift Apps/SeretTVTests/SignInModelTests.swift
git commit -m "feat(auth): reuse a still-valid device code on retry (stop re-tripping RD throttle)"
```

---

## Task 6: `SignInView` token-entry UI (build-only)

SwiftUI/tvOS — verified by build (no unit test). Adds a "Use a Real-Debrid token instead" path.

**Files:**
- Modify: `Apps/SeretTV/Auth/SignInView.swift`

- [ ] **Step 1: Replace `SignInView.swift` with the token-aware version**

```swift
import DebridCore
import SwiftUI

/// The sign-in screen. Default: device-code. Secondary: paste a personal API token
/// (real-debrid.com/apitoken), which bypasses the throttled device-code endpoint.
struct SignInView: View {
    let model: SignInModel
    @State private var showingTokenEntry = false
    @State private var tokenText = ""

    var body: some View {
        ZStack {
            if showingTokenEntry {
                tokenEntry
            } else {
                switch model.phase {
                case .idle, .requestingCode:
                    ProgressView("Preparing sign‑in…").font(.title2)
                case .awaitingAuthorization(let code):
                    deviceCode(code)
                case .validatingToken:
                    ProgressView("Checking token…").font(.title2)
                case .signedIn:
                    ProgressView("Signing in…").font(.title2)
                case .failed(let message):
                    failure(message)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: model.attempt) { await model.run() }
    }

    private func deviceCode(_ code: RDDeviceCode) -> some View {
        VStack(spacing: 48) {
            Text("Sign in to Real‑Debrid").font(.largeTitle.bold())
            HStack(alignment: .center, spacing: 80) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("On your phone or computer, go to")
                        .font(.title3).foregroundStyle(.secondary)
                    Text(displayURL(code.verificationURL)).font(.title.bold())
                    Text("and enter this code:").font(.title3).foregroundStyle(.secondary)
                    Text(code.userCode)
                        .font(.system(size: 96, weight: .heavy, design: .monospaced))
                }
                if let qr = QRCode.image(from: code.verificationURL) {
                    qr.resizable().interpolation(.none).scaledToFit()
                        .frame(width: 300, height: 300).padding(20)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            Label("Waiting for authorization…", systemImage: "hourglass")
                .font(.title3).foregroundStyle(.secondary)
            Button("Use a Real‑Debrid token instead") { showingTokenEntry = true }
                .font(.title3)
        }
        .padding(80)
    }

    private var tokenEntry: some View {
        VStack(spacing: 28) {
            Text("Sign in with a token").font(.largeTitle.bold())
            Text("Get your token at real‑debrid.com/apitoken, then paste it here.")
                .font(.title3).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 800)
            SecureField("Real‑Debrid API token", text: $tokenText)
                .textContentType(.password)
                .frame(maxWidth: 700)
            if case .validatingToken = model.phase { ProgressView() }
            if case .failed(let message) = model.phase {
                Text(message).font(.callout).foregroundStyle(.orange)
                    .multilineTextAlignment(.center).frame(maxWidth: 700)
            }
            HStack(spacing: 24) {
                Button("Sign In") { Task { await model.signInWithToken(tokenText) } }
                    .disabled(tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Use a code instead") { showingTokenEntry = false }
            }
            .font(.title3)
        }
        .padding(80)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 32) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 72)).foregroundStyle(.yellow)
            Text(message).font(.title2).multilineTextAlignment(.center).frame(maxWidth: 800)
            HStack(spacing: 24) {
                Button("Try Again") { model.retry() }
                Button("Use a Real‑Debrid token instead") { showingTokenEntry = true }
            }
            .font(.title3)
        }
        .padding(80)
    }

    /// "https://real-debrid.com/device" → "real-debrid.com/device".
    private func displayURL(_ raw: String) -> String {
        guard let comps = URLComponents(string: raw), let host = comps.host else { return raw }
        return host + comps.path + (comps.query.map { "?\($0)" } ?? "")
    }
}
```

- [ ] **Step 2: Build**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate && xcodebuild -scheme SeretTV -destination 'generic/platform=tvOS Simulator' build 2>&1 | tail -8`
Expected: `** BUILD SUCCEEDED **`, zero warnings.

- [ ] **Step 3: Commit**

```bash
git add Apps/SeretTV/Auth/SignInView.swift
git commit -m "feat(auth): SignInView — 'use a Real-Debrid token instead' entry"
```

---

## Task 7: Final verification

`AppSession` needs **no change** — it builds `LiveAuthFlow(auth:session:)` (now with `signIn`) and `SignInModel(flow:onSignedIn:)` (`now` defaults). Confirm and run the whole suite.

- [ ] **Step 1: Confirm AppSession is untouched / still compiles the flow**

Run: `git diff main -- Apps/SeretTV/Shell/AppSession.swift` → expect EMPTY (no change needed). (If it doesn't compile because `SignInModel`/`LiveAuthFlow` changed shape, that's a bug — fix the call site minimally.)

- [ ] **Step 2: Full DebridCore suite (no sim)**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret/Packages/DebridCore && swift test 2>&1 | tail -5`
Expected: all green (130).

- [ ] **Step 3: Full app suite (tvOS sim) + zero warnings**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate && xcodebuild test -scheme SeretTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` (app suite now 40: prior 35 + 5 SignInModel), zero warnings. (PTY 7/6 → BLOCKED.)

- [ ] **Step 4: Confirm no secrets/logging regressions**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && grep -rn "print(\|NSLog\|os_log" Apps/SeretTV/Auth Packages/DebridCore/Sources/DebridCore/RealDebrid || echo "no logging added"`
Expected: no token/secret logging.

---

## Self-review notes (completed during planning)

- **Spec coverage:** isStatic flag (§Part A → T1), establishStaticToken + short-circuit (§A → T2), validateToken (§A → T3), AuthFlow.signIn + SignInModel.signInWithToken + message (§B → T4), SignInView token entry (§B → T6), device-code reuse (§C → T5), testing (§Testing → T1–T5 + T7), AppSession unchanged (§Files → T7). All spec sections map to a task.
- **Type consistency:** `establishStaticToken(_:)`, `validateToken(_:) -> Bool`, `signIn(token:)`, `signInWithToken(_:)`, `TokenSignInError.invalidToken`, `Phase.validatingToken`, `now:` init param, `cachedCode`/`codeObtainedAt` — referenced identically across tasks. `HTTPError.status(401, _)` positional match mirrors the existing `pollCredentials` usage.
- **No placeholders:** every code + test + command is concrete.
