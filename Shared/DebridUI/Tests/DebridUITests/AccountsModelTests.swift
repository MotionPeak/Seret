import Testing
import Foundation
import DebridCore
@testable import DebridUI

/// Settings → Accounts: one row per provider, the TorBox row's plan detail and warnings, the
/// add-target picker, and per-account sign-out. Driven through `AppSession`'s
/// `composesFullStack: false` seam (the debrid layer is real, the SwiftData stack is skipped).
///
/// A class so `deinit` can drop each test's throwaway `UserDefaults` domain.
@MainActor
@Suite final class AccountsModelTests {
    private let suiteName = "AccountsModelTests.\(UUID().uuidString)"
    deinit { UserDefaults().removePersistentDomain(forName: suiteName) }

    private enum Transport: Error { case offline }

    private func makeSession(rd: Bool, torBox: Bool) async throws -> AppSession {
        let rdSession = RealDebridSession(store: InMemoryTokenStore())
        if rd { try await rdSession.establishStaticToken("rd-token") }
        let tbSession = TorBoxSession(store: InMemorySecretStore())
        if torBox { try await tbSession.establish(key: "tb-key") }
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let session = AppSession(realDebrid: rdSession, torBox: tbSession, defaults: defaults,
                                 composesFullStack: false)
        await session.resolve()
        return session
    }

    /// `TorBoxUser` is decode-only, so a fixture is JSON.
    nonisolated private static func user(plan: Int, email: String?) -> TorBoxUser {
        let emailField = email.map { #","email":"\#($0)""# } ?? ""
        return try! JSONDecoder().decode(TorBoxUser.self, from: Data(#"{"plan":\#(plan)\#(emailField)}"#.utf8))
    }

    private func row(_ model: AccountsModel, _ provider: DebridProvider) throws -> AccountsModel.Row {
        try #require(model.rows.first { $0.provider == provider })
    }

    @Test func freePlanRowWarns() async throws {
        let session = try await makeSession(rd: false, torBox: true)
        let model = AccountsModel(session: session, torBoxUser: { Self.user(plan: 0, email: "me@example.com") })
        await model.load()
        let torBox = try row(model, .torBox)
        #expect(torBox.state == .signedIn)
        #expect(torBox.warning == "TorBox's API needs a paid plan.")
    }

    @Test func paidPlanRowShowsEmailAndPlan() async throws {
        let session = try await makeSession(rd: true, torBox: true)
        let model = AccountsModel(session: session, torBoxUser: { Self.user(plan: 2, email: "me@example.com") })
        await model.load()
        #expect(model.rows.map(\.provider) == [.realDebrid, .torBox])
        let torBox = try row(model, .torBox)
        #expect(torBox.detail == "me@example.com · Pro")
        #expect(torBox.warning == nil)
        #expect(try row(model, .realDebrid).detail == nil)
    }

    @Test func missingEmailShowsJustThePlan() async throws {
        let session = try await makeSession(rd: false, torBox: true)
        let model = AccountsModel(session: session, torBoxUser: { Self.user(plan: 1, email: nil) })
        await model.load()
        #expect(try row(model, .torBox).detail == "Essential")
    }

    @Test func pickerOnlyWhenBothSignedIn() async throws {
        let both = try await makeSession(rd: true, torBox: true)
        #expect(AccountsModel(session: both, torBoxUser: { throw Transport.offline }).showsAddTargetPicker)

        let rdOnly = try await makeSession(rd: true, torBox: false)
        let model = AccountsModel(session: rdOnly, torBoxUser: { throw Transport.offline })
        #expect(!model.showsAddTargetPicker)
        #expect(model.rows.map(\.state) == [.signedIn, .signedOut])
    }

    @Test func addTargetForwardsToTheSession() async throws {
        let session = try await makeSession(rd: true, torBox: true)
        let model = AccountsModel(session: session, torBoxUser: { throw Transport.offline })
        #expect(model.addTarget == .realDebrid)
        model.addTarget = .torBox
        #expect(session.addTarget == .torBox)
        #expect(model.addTarget == .torBox)
    }

    @Test func userFetchFailureLeavesRowWithoutDetail() async throws {
        let session = try await makeSession(rd: true, torBox: true)
        for failure in [Transport.offline as any Error,
                        TorBoxError.rateLimited(retryAfter: 300),
                        TorBoxError.api(code: "HTTP_503", detail: "down", status: 503)] {
            let model = AccountsModel(session: session, torBoxUser: { throw failure })
            await model.load()
            let torBox = try row(model, .torBox)
            #expect(torBox.state == .signedIn)
            #expect(torBox.detail == nil)
            #expect(torBox.warning == nil)
        }
    }

    @Test func planRestrictedErrorWarns() async throws {
        let session = try await makeSession(rd: true, torBox: true)
        let model = AccountsModel(session: session, torBoxUser: {
            throw TorBoxError.api(code: "PLAN_RESTRICTED_FEATURE", detail: "no", status: 403)
        })
        await model.load()
        let torBox = try row(model, .torBox)
        #expect(torBox.warning == "TorBox's API needs a paid plan.")
        #expect(torBox.detail == nil)
        #expect(torBox.state == .signedIn)
    }

    @Test func rejectedKeyWarnsToSignInAgain() async throws {
        let session = try await makeSession(rd: true, torBox: true)
        for failure in [TorBoxError.api(code: "BAD_TOKEN", detail: "bad", status: 401) as any Error,
                        TorBoxSessionError.notSignedIn] {
            let model = AccountsModel(session: session, torBoxUser: { throw failure })
            await model.load()
            #expect(try row(model, .torBox).warning == "TorBox didn't accept the saved key. Sign in again.")
        }
    }

    @Test func loadWhileSignedOutDoesNotFetch() async throws {
        let session = try await makeSession(rd: true, torBox: false)
        let fetches = Counter()
        let model = AccountsModel(session: session, torBoxUser: { fetches.bump(); return Self.user(plan: 2, email: nil) })
        await model.load()
        #expect(fetches.count == 0)
        #expect(try row(model, .torBox).detail == nil)
    }

    @Test func signOutClearsThatRowsDetailAndFlipsTheTarget() async throws {
        let session = try await makeSession(rd: true, torBox: true)
        session.addTarget = .torBox
        let model = AccountsModel(session: session, torBoxUser: { Self.user(plan: 2, email: "me@example.com") })
        await model.load()
        #expect(try row(model, .torBox).detail != nil)

        await model.signOut(.torBox)
        let torBox = try row(model, .torBox)
        #expect(torBox.state == .signedOut)
        #expect(torBox.detail == nil)
        #expect(model.addTarget == .realDebrid)
        #expect(!model.showsAddTargetPicker)
        #expect(try row(model, .realDebrid).state == .signedIn)
    }

    @Test func signInHandsBackTheSessionsFlow() async throws {
        let session = try await makeSession(rd: true, torBox: false)
        let model = AccountsModel(session: session, torBoxUser: { throw Transport.offline })
        #expect(model.signIn(.torBox).provider == .torBox)
    }

    @Test func conveniencePathFailsWithNotSignedInWhenNoTorBoxClient() async throws {
        let session = try await makeSession(rd: true, torBox: false)
        let model = AccountsModel(session: session)
        await model.load()   // signed out: nothing fetched, no warning
        #expect(try row(model, .torBox).warning == nil)
        await #expect(throws: TorBoxSessionError.notSignedIn) {
            _ = try await AccountsModel.fetchTorBoxUser(from: session)
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
