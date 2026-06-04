# Real-Debrid API-token sign-in + device-code reuse — Design

**Date:** 2026-06-04
**Status:** Approved (design); ready for implementation plan.

## Goal

Add a second, throttle-proof way to sign in to Real-Debrid: pasting a **personal API token** (from real-debrid.com/apitoken). Keep the existing device-code flow as the default, and harden it so retries stop tripping RD's rate limit.

## Why

Real-Debrid's edge **durably throttles** the shared open-source device-code client (`X245A4XAIBGVM`) for the tvOS TLS fingerprint: a single device-code request from the Apple TV returns a bare `HTTP 403` even hours after the last attempt (the same request from a Mac/curl — a different fingerprint — returns 200). The device-code sign-in is therefore unreliable on the Apple TV. A personal API token is a **static Bearer token** that bypasses the device-code OAuth dance entirely, so it is immune to this throttle — and it is the natural auth for a personal, single-user app.

## Key decision — model the static token with an `isStatic` flag

A personal token has no refresh token and no client credentials, so it must never go through `RealDebridSession`'s refresh path. Chosen approach (of three considered):

- **A. `isStatic: Bool` flag on `StoredCredentials` (chosen).** Minimal, explicit, back-compatible: existing 3-arg `StoredCredentials` call sites and tests are untouched (the flag defaults to `false`), and Codable decodes old data via `decodeIfPresent ?? false`.
- B. Make `StoredCredentials` an enum (`.oauth` / `.static`) — conceptually cleanest but refactors every accessor + Codable + all existing auth tests. Rejected: too invasive for the gain.
- C. Sentinel encoding (empty device creds + huge `expiresIn`) — no new field but implicit and fragile. Rejected.

## Part A — Brain (DebridCore)

1. **`StoredCredentials`** gains `public let isStatic: Bool`.
   - Add a 4-arg memberwise init with `isStatic: Bool = false` (keeps the existing 3-arg call sites compiling).
   - Codable: decode `isStatic` via `decodeIfPresent(Bool.self, forKey:) ?? false` so previously-persisted credentials still load.

2. **`RealDebridSession`**
   - `establishStaticToken(_ token: String) throws` — persists a static credential:
     `StoredCredentials(token: RDToken(accessToken: token, refreshToken: "", expiresIn: 0, tokenType: "Bearer"), deviceCredentials: RDDeviceCredentials(clientID: "", clientSecret: ""), obtainedAt: now(), isStatic: true)` and updates `cached`.
   - `validAccessToken()` — short-circuit at the top: `if creds.isStatic { return creds.token.accessToken }` **before** the expiry/refresh check. A static token is returned as-is and is never refreshed.
   - `establish(...)`, `signOut()`, refresh logic unchanged. Static credentials clear via the existing `signOut()`.

3. **`RealDebridAuthClient.validateToken(_ token: String) async throws -> Bool`**
   - `GET https://api.real-debrid.com/rest/1.0/user` with header `Authorization: Bearer <token>` (decode a minimal user probe).
   - Returns `true` on success; `false` on `HTTPError.status(401, _)` / `status(403, _)` (token not accepted); **rethrows** any other error (network/transport) so the UI can distinguish "bad token" from "offline".
   - Never logs the token.

## Part B — App: token sign-in (secondary option)

4. **`AuthFlow`** (app seam) gains `func signIn(token: String) async throws`.
   - `LiveAuthFlow`: `guard try await auth.validateToken(token) else { throw TokenSignInError.invalidToken }; try await session.establishStaticToken(token)`.
   - `FakeAuthFlow` (tests) stubs it (configurable success / `invalidToken` / thrown error).
   - New error: `enum TokenSignInError: Error { case invalidToken }` (app-side; mapped to user text in `SignInModel.message(for:)`).

5. **`SignInModel`**
   - `Phase` gains `.validatingToken`.
   - `func signInWithToken(_ token: String) async`: trim input; ignore empty; set `.validatingToken`; `try await flow.signIn(token:)`; on success `phase = .signedIn` + `onSignedIn()`; on `CancellationError` leave state; on other `phase = .failed(message)`.
   - `message(for:)` gains: `TokenSignInError.invalidToken` → "That token wasn't accepted by Real‑Debrid. Check it and try again." Still never interpolates the raw error (no token leakage).

6. **`SignInView`**
   - On the device-code screen **and** the failure screen, add a button **"Use a Real‑Debrid token instead"** that reveals a token-entry sub-view (`@State private var showingTokenEntry`).
   - Token-entry sub-view: a `SecureField` (paste the token; Continuity keyboard), a **Sign In** button → `Task { await model.signInWithToken(text) }`, a hint *"Get your token at real-debrid.com/apitoken"*, and a way back to the code screen. Render `.validatingToken` (spinner) and the invalid-token `.failed` message inline.

## Part C — Device-code reuse hardening

7. **`SignInModel`** caches the obtained device code so retries/relaunches don't mint new ones:
   - Inject `now: @escaping () -> Date = { Date() }` for testable time.
   - Cache `cachedCode: RDDeviceCode?` + `codeObtainedAt: Date?` after a successful `flow.begin()`.
   - In `run()`: if a cached code exists **and** `now() - codeObtainedAt < expiresIn` (minus a small safety margin so there's time to poll), **reuse it** — skip `begin()`, go straight to `awaitingAuthorization(cachedCode)` and re-poll via `awaitSignIn`. Otherwise call `begin()` and cache the fresh code.
   - Net effect: once a code is successfully obtained, "Try Again" and view re-appearances re-poll the **same** code instead of hitting the throttled `device/code` endpoint again. (This does not un-stick an already-active RD cooldown — the first `begin()` must still succeed — but it stops the app from extending/re-tripping it.)

## Error handling

- Invalid/declined token → `.failed("That token wasn't accepted…")`; user can re-enter.
- Network error during validation → the existing "Couldn't reach Real‑Debrid…" message.
- A static token that is later revoked: resource calls (e.g. library load) get a 401 and surface as the existing library-failed state; the user re-enters the token. (`RealDebridSession` does not auto-refresh static tokens by design.)

## Testing

- **DebridCore (Swift Testing, no sim):**
  - `establishStaticToken` + `validAccessToken()` returns the token and performs **no** refresh (assert via a `FakeAuthClient` that records refresh calls / an `InMemoryTokenStore`).
  - `StoredCredentials` Codable round-trips with and without `isStatic` (old-data back-compat).
  - `validateToken` → `true` on mocked 200, `false` on mocked 401/403, rethrows on other (via `MockURLProtocol`, nested under `MockTests`).
- **App (xcodebuild test on the tvOS sim):**
  - `SignInModel.signInWithToken` success → `.signedIn` + `onSignedIn`; invalid token → `.failed`; empty input ignored (via `FakeAuthFlow`).
  - Device-code **reuse**: a cached, unexpired code is reused on retry (no second `begin()`); an expired cached code triggers a fresh `begin()` (FakeAuthFlow counts `begin()` calls; injected `now`).
- **Build-verified:** `SignInView` token-entry UI (no unit test).

## Files

**Modified — DebridCore:** `RealDebrid/TokenStore.swift` (`isStatic`), `RealDebrid/RealDebridSession.swift` (`establishStaticToken` + short-circuit), `RealDebrid/RealDebridAuthClient.swift` (`validateToken`). Tests: `RealDebridSessionTests`, `RealDebridAuthClientTests`, `TokenStore`/Codable test.

**Modified — app:** `Auth/AuthFlow.swift` (`signIn(token:)` + `TokenSignInError`), `Auth/SignInModel.swift` (`.validatingToken`, `signInWithToken`, reuse cache, `now`), `Auth/SignInView.swift` (token-entry UI). Tests: `SignInModelTests`.

**Unchanged:** all resource clients (`TorrentsClient` etc.) — they authenticate via `AccessTokenProviding.validAccessToken()`, which now transparently serves a static token. `AppSession` wiring is unchanged (it already builds `LiveAuthFlow(auth:session:)`).

## Non-goals

- Auto-refresh / rotation of personal API tokens (they are long-lived; on revocation the user re-enters).
- A standalone token-entry screen in Settings (sign-in screen only; once signed in, the token persists in Keychain).
- Fixing RD's device-code throttle itself (out of our control; the token path sidesteps it).

## Security

- The token is stored only in the Keychain (via the existing `KeychainTokenStore` / `StoredCredentials`); never committed, never logged. `SecureField` keeps it off-screen. `message(for:)` never interpolates raw errors.
