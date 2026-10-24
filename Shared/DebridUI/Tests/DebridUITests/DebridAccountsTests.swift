import Testing
import Foundation
import DebridCore
@testable import DebridUI

/// Two debrid accounts: who counts as signed in at launch, which errors really mean "sign in
/// again", and where new titles go. Getting the reauthentication rule wrong signs a viewer out of
/// a perfectly good account; getting the launch rule wrong hides one account behind the other.
@Suite struct DebridAccountsTests {
    private enum Transport: Error { case offline }

    // MARK: Launch

    @Test func launchSignedInIfEitherHasCredentials() {
        let torBoxOnly = DebridAccounts.launchDecision([
            .realDebrid: .failure(RealDebridSessionError.notSignedIn),
            .torBox: .success(()),
        ])
        #expect(torBoxOnly == .signedIn([.torBox]))

        let both = DebridAccounts.launchDecision([.realDebrid: .success(()), .torBox: .success(())])
        #expect(both == .signedIn([.realDebrid, .torBox]))
    }

    @Test func launchSignedOutWhenBothMissing() {
        let decision = DebridAccounts.launchDecision([
            .realDebrid: .failure(RealDebridSessionError.notSignedIn),
            .torBox: .failure(TorBoxSessionError.notSignedIn),
        ])
        #expect(decision == .signedOut)
        #expect(DebridAccounts.launchDecision([:]) == .signedOut)
    }

    /// Offline with stored credentials was always meant to stay optimistically signed in.
    @Test func offlineWithCredentialsStaysSignedIn() {
        let decision = DebridAccounts.launchDecision([
            .realDebrid: .failure(URLError(.notConnectedToInternet)),
            .torBox: .failure(TorBoxSessionError.notSignedIn),
        ])
        #expect(decision == .signedIn([.realDebrid]))
    }

    // MARK: Reauthentication

    /// A Free-plan key is a valid key: TorBox only refuses its API. Signing out over it would loop
    /// the viewer through a sign-in that succeeds every time.
    @Test func freePlanIsNotReauthentication() {
        let freePlan = TorBoxError.api(code: "PLAN_RESTRICTED_FEATURE",
                                       detail: "This feature needs a paid plan.", status: 403)
        #expect(!DebridAccounts.mustReauthenticate(after: freePlan))
        #expect(DebridAccounts.launchDecision([.torBox: .failure(freePlan)]) == .signedIn([.torBox]))
    }

    @Test func badTokenIsReauthentication() {
        for code in ["BAD_TOKEN", "NO_AUTH", "AUTH_ERROR"] {
            #expect(DebridAccounts.mustReauthenticate(after: TorBoxError.api(code: code, detail: "", status: 401)),
                    "\(code) must mean sign in again")
        }
        #expect(DebridAccounts.mustReauthenticate(after: TorBoxSessionError.notSignedIn))
        #expect(DebridAccounts.mustReauthenticate(after: TorBoxError.notSignedIn))
    }

    /// A 401/403 without TorBox's envelope came from something in front of TorBox (a CDN, a
    /// captive portal), not from TorBox judging the key. Only the envelope's codes say the key is bad.
    @Test func nonEnvelope403IsNotReauthentication() {
        for status in [401, 403] {
            let bare = TorBoxError.api(code: "HTTP_\(status)", detail: "", status: status)
            #expect(!DebridAccounts.mustReauthenticate(after: bare), "bare \(status) must not sign out")
        }
    }

    /// TorBox locks a key out for ~300 s on a 429 — a bad moment, not a bad key.
    @Test func torBoxRateLimitIsNotReauthentication() {
        #expect(!DebridAccounts.mustReauthenticate(after: TorBoxError.rateLimited(retryAfter: 300)))
    }

    // MARK: Add target

    @Test func addTargetFallsBackWhenStoredNotSignedIn() {
        #expect(DebridAccounts.effectiveAddTarget(stored: .torBox, signedIn: [.realDebrid]) == .realDebrid)
        #expect(DebridAccounts.effectiveAddTarget(stored: .realDebrid, signedIn: [.torBox]) == .torBox)
        #expect(DebridAccounts.effectiveAddTarget(stored: .torBox, signedIn: [.realDebrid, .torBox]) == .torBox)
        #expect(DebridAccounts.effectiveAddTarget(stored: nil, signedIn: [.torBox, .realDebrid]) == .realDebrid)
        #expect(DebridAccounts.effectiveAddTarget(stored: nil, signedIn: [.torBox]) == .torBox)
        #expect(DebridAccounts.effectiveAddTarget(stored: .realDebrid, signedIn: []) == nil)
    }
}

/// `AppSession`'s account bookkeeping, driven through the thin `composesFullStack: false` seam:
/// the debrid composition (clients, composite, stream source, add + download services) is real,
/// and the library is a recording fake built over the real composite, but the SwiftData
/// containers, notification permission and TMDB stack that a full sign-in builds are skipped —
/// they would write into the test runner's real Application Support and `UNUserNotificationCenter`
/// traps outside an app bundle.
///
/// A class so `deinit` can drop each test's throwaway `UserDefaults` domain.
@MainActor
@Suite final class AppSessionAccountsTests {
    private let suiteName = "AppSessionAccountsTests.\(UUID().uuidString)"
    /// Every library the session built, in order, with the providers its composite held.
    private var libraries: [(library: RecordingLibrary, providers: [DebridProvider])] = []

    deinit { UserDefaults().removePersistentDomain(forName: suiteName) }

    private func makeSession(rd rdToken: String?, torBox tbKey: String?,
                             storedTarget: DebridProvider? = nil) async throws
        -> (AppSession, RealDebridSession, TorBoxSession) {
        let rd = RealDebridSession(store: InMemoryTokenStore())
        if let rdToken { try await rd.establishStaticToken(rdToken) }
        let tb = TorBoxSession(store: InMemorySecretStore())
        if let tbKey { try await tb.establish(key: tbKey) }
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        if let storedTarget { defaults.set(storedTarget.rawValue, forKey: "debrid.addTarget") }
        let session = AppSession(realDebrid: rd, torBox: tb, defaults: defaults, composesFullStack: false,
                                 libraryForTest: { [weak self] debrid in
                                     let library = RecordingLibrary()
                                     let providers = (debrid as? CompositeDebridClient)?.providers ?? []
                                     self?.libraries.append((library, providers))
                                     return library
                                 })
        return (session, rd, tb)
    }

    /// Nothing remounts on a rebuild — state stays `.signedIn` and every screen's load task is keyed
    /// on something that does not change — so the session must load the rebuilt library itself,
    /// or the viewer is left looking at skeletons.
    @Test func aRebuildLoadsTheNewLibrary() async throws {
        let (session, _, _) = try await makeSession(rd: "rd-token", torBox: "tb-key")
        await session.resolve()
        #expect(libraries.count == 1)

        await session.signOut(of: .realDebrid)
        await session.rebuildLoad?.value

        #expect(libraries.count == 2)
        #expect(libraries.last?.providers == [.torBox])
        #expect(libraries.last?.library.refreshes == 1)
        #expect(session.libraryStore?.state == .empty)   // answered, not stuck on .loading
    }

    /// Adding a second account rebuilds too.
    @Test func signingInToASecondAccountLoadsTheNewLibrary() async throws {
        let (session, _, tb) = try await makeSession(rd: "rd-token", torBox: nil)
        await session.resolve()
        try await tb.establish(key: "tb-key")

        session.markSignedIn(.torBox)
        await session.rebuildLoad?.value

        #expect(libraries.last?.providers == [.realDebrid, .torBox])
        #expect(libraries.last?.library.refreshes == 1)
    }

    /// An Add page left open (tvOS keeps one alive in Find's stack) while Settings changes the
    /// target must add to the NEW target, so the vended services resolve the session's current
    /// ones on every call.
    @Test func vendedAddServicesFollowTheCurrentTarget() async throws {
        let (session, _, _) = try await makeSession(rd: "rd-token", torBox: "tb-key")
        await session.resolve()
        let add = session.vendedAddService
        let search = session.vendedStreamSource
        #expect((await add.current() as? DebridAddService)?.client.provider == .realDebrid)
        #expect(await search.current() is AggregateStreamSource)

        session.addTarget = .torBox

        #expect((await add.current() as? DebridAddService)?.client.provider == .torBox)
        #expect(await search.current() is TorBoxCachedStreamSource)

        await session.signOut()
        #expect(await add.current() == nil)
        #expect(await search.current() == nil)
    }

    @Test func signOutOfOneKeepsTheOther() async throws {
        let (session, rd, _) = try await makeSession(rd: "rd-token", torBox: "tb-key")
        await session.resolve()
        #expect(session.accounts == [.realDebrid: .signedIn, .torBox: .signedIn])
        #expect(session.addTarget == .realDebrid)
        #expect(session.debrid?.providers == [.realDebrid, .torBox])

        await session.signOut(of: .realDebrid)

        #expect(session.accounts[.torBox] == .signedIn)
        #expect(session.accounts[.realDebrid] == .signedOut)
        #expect(session.state == .signedIn)
        #expect(session.addTarget == .torBox)
        // The rebuilt stack no longer asks Real-Debrid, so its titles leave on the next refresh.
        #expect(session.debrid?.providers == [.torBox])
        #expect(session.debrid?.provider == .torBox)
        #expect(session.streamSource is TorBoxCachedStreamSource)
        // …and its credentials are really gone.
        await #expect(throws: RealDebridSessionError.self) { _ = try await rd.validAccessToken() }
    }

    @Test func signOutOfTheLastAccountSignsOut() async throws {
        let (session, _, tb) = try await makeSession(rd: nil, torBox: "tb-key")
        await session.resolve()
        #expect(session.accounts == [.realDebrid: .signedOut, .torBox: .signedIn])
        #expect(session.state == .signedIn)

        await session.signOut(of: .torBox)

        #expect(session.state == .signedOut)
        #expect(session.debrid == nil)
        #expect(session.signInModel != nil)
        #expect(await !tb.isSignedIn)
    }

    @Test func resolveWithNoCredentialsSignsOut() async throws {
        let (session, _, _) = try await makeSession(rd: nil, torBox: nil)
        await session.resolve()
        #expect(session.state == .signedOut)
        #expect(session.accounts == [.realDebrid: .signedOut, .torBox: .signedOut])
    }

    /// A stored target that is not signed in falls back, without overwriting the stored choice.
    @Test func storedTargetNotSignedInFallsBack() async throws {
        let (session, _, _) = try await makeSession(rd: "rd-token", torBox: nil, storedTarget: .torBox)
        await session.resolve()
        #expect(session.addTarget == .realDebrid)
        #expect(session.debrid?.provider == .realDebrid)
        #expect(session.streamSource is AggregateStreamSource)
    }

    @Test func settingTheAddTargetPersistsAndRebuildsTheAddStack() async throws {
        let (session, _, _) = try await makeSession(rd: "rd-token", torBox: "tb-key")
        await session.resolve()
        #expect(session.streamSource is AggregateStreamSource)

        session.addTarget = .torBox

        #expect(session.addTarget == .torBox)
        #expect(session.defaults.string(forKey: "debrid.addTarget") == "torBox")
        #expect(session.debrid?.provider == .torBox)
        #expect(session.debrid?.providers == [.realDebrid, .torBox])
        #expect(session.streamSource is TorBoxCachedStreamSource)
        #expect(session.state == .signedIn)
    }

    @Test func signOutOfEverythingClearsBothAccounts() async throws {
        let (session, rd, tb) = try await makeSession(rd: "rd-token", torBox: "tb-key")
        await session.resolve()

        await session.signOut()

        #expect(session.state == .signedOut)
        #expect(session.accounts == [.realDebrid: .signedOut, .torBox: .signedOut])
        #expect(await !tb.isSignedIn)
        await #expect(throws: RealDebridSessionError.self) { _ = try await rd.validAccessToken() }
    }
}

/// Records refreshes; answers with nothing.
private final class RecordingLibrary: LibraryProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _refreshes = 0
    var refreshes: Int { lock.withLock { _refreshes } }
    func loadCached() -> [MediaItem]? { nil }
    func refresh() async throws -> [MediaItem] {
        lock.withLock { _refreshes += 1 }
        return []
    }
    func remove(_ item: MediaItem) async throws {}
    func removeVersion(_ item: MediaItem, source: MediaSource) async throws {}
}
