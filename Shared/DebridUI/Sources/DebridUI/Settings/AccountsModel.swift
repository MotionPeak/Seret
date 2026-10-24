import DebridCore
import Foundation
import Observation

/// Settings → Accounts: one row per debrid provider, what each is signed in as, and the controls
/// that act on them. It reads sign-in state from `AppSession` (the source of truth) and adds only
/// what the session does not know — TorBox's plan, fetched once by `load()`.
///
/// Per-account failures are surfaced here, not on the library screen, when both accounts are
/// signed in: a Free-plan or rejected TorBox key shows as a warning on its row while the other
/// account keeps working.
@MainActor @Observable
public final class AccountsModel {

    public struct Row: Identifiable, Equatable {
        public let provider: DebridProvider
        public let state: AccountState
        /// "email · Plan" for a signed-in TorBox account whose user fetch succeeded.
        public let detail: String?
        public let warning: String?
        public var id: DebridProvider { provider }
    }

    static let paidPlanWarning = "TorBox's API needs a paid plan."
    static let rejectedKeyWarning = "TorBox didn't accept the saved key. Sign in again."

    private let session: AppSession
    private let torBoxUser: @Sendable () async throws -> TorBoxUser
    private var torBoxDetail: String?
    private var torBoxWarning: String?

    public init(session: AppSession, torBoxUser: @escaping @Sendable () async throws -> TorBoxUser) {
        self.session = session
        self.torBoxUser = torBoxUser
    }

    /// Fetches the TorBox user through the session's own TorBox client.
    public convenience init(session: AppSession) {
        self.init(session: session, torBoxUser: { [session] in
            try await Self.fetchTorBoxUser(from: session)
        })
    }

    /// `TorBoxSessionError.notSignedIn` when the session has no TorBox client.
    static func fetchTorBoxUser(from session: AppSession) async throws -> TorBoxUser {
        let client = await MainActor.run { session.debrid?.client(for: .torBox) as? TorBoxClient }
        guard let client else { throw TorBoxSessionError.notSignedIn }
        return try await client.user()
    }

    /// Always both providers, Real-Debrid first. A signed-out account carries no detail or warning.
    public var rows: [Row] {
        DebridProvider.allCases.map { provider in
            let state = session.accounts[provider] ?? .signedOut
            let live = provider == .torBox && state == .signedIn
            return Row(provider: provider, state: state,
                       detail: live ? torBoxDetail : nil,
                       warning: live ? torBoxWarning : nil)
        }
    }

    /// Choosing where new titles go only means something with two accounts to choose between.
    public var showsAddTargetPicker: Bool { session.signedInProviders.count > 1 }

    public var addTarget: DebridProvider {
        get { session.addTarget }
        set { session.addTarget = newValue }
    }

    /// Fetches the TorBox account's plan when TorBox is signed in. A failure that says nothing about
    /// the account (offline, rate-limited, a 5xx) leaves the row as it was, with no detail.
    public func load() async {
        guard session.accounts[.torBox] == .signedIn else {
            clearTorBox()
            return
        }
        do {
            let user = try await torBoxUser()
            torBoxDetail = [user.email, user.planName].compactMap { $0 }.joined(separator: " · ")
            torBoxWarning = user.isPaid ? nil : Self.paidPlanWarning
        } catch {
            torBoxDetail = nil
            torBoxWarning = Self.warning(for: error)
        }
    }

    public func signOut(_ provider: DebridProvider) async {
        await session.signOut(of: provider)
        if provider == .torBox { clearTorBox() }
    }

    public func signIn(_ provider: DebridProvider) -> SignInModel {
        session.beginSignIn(to: provider)
    }

    private func clearTorBox() {
        torBoxDetail = nil
        torBoxWarning = nil
    }

    private static func warning(for error: any Error) -> String? {
        if let torBox = error as? TorBoxError {
            if torBox.isPlanRestricted { return paidPlanWarning }
            if torBox.isAuthRejection || torBox == .notSignedIn { return rejectedKeyWarning }
            return nil
        }
        if error is TorBoxSessionError { return rejectedKeyWarning }
        return nil
    }
}
