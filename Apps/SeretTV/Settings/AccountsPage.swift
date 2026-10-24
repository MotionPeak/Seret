import DebridCore
import DebridUI
import SwiftUI

/// Settings → Accounts: one section per debrid provider — what it is signed in as, and Sign In /
/// Sign Out — then, with both signed in, where new titles go. Pushed from the Settings root.
///
/// Signing in to a second account opens the sign-in screen as a PUSHED page (`AddAccountSignInPage`)
/// — never a cover, which on tvOS swallows Menu — and comes back here when it lands.
struct AccountsPage: View {
    @State private var accounts: AccountsModel
    /// The add-an-account flow on screen, vended by `AccountsModel.signIn(_:)`. Nil = not pushed.
    @State private var signingIn: SignInModel?

    init(session: AppSession) {
        _accounts = State(initialValue: AccountsModel(session: session))
    }

    var body: some View {
        AccountsContent(
            rows: accounts.rows.map(AccountsContent.Row.init),
            showsAddTargetPicker: accounts.showsAddTargetPicker,
            addTarget: Binding(get: { accounts.addTarget }, set: { accounts.addTarget = $0 }),
            onSignIn: { provider in signingIn = accounts.signIn(provider) },
            onSignOut: { provider in
                Task {
                    await accounts.signOut(provider)
                    await accounts.load()
                }
            })
            // The model does not refresh itself: on every visit (including the pop back from a
            // sign-in page), and again when a sign-in from here lands — see below.
            .task { await accounts.load() }
            .navigationDestination(isPresented: Binding(
                get: { signingIn != nil },
                set: { if !$0 { signingIn = nil } })) {
                if let model = signingIn {
                    AddAccountSignInPage(model: model) {
                        signingIn = nil
                        Task { await accounts.load() }
                    }
                }
            }
    }
}

/// The signed-out screen's sign-in UI, pushed from Accounts to add one more account while the app
/// stays signed in. Pops itself when the sign-in lands.
struct AddAccountSignInPage: View {
    let model: SignInModel
    let onSignedIn: () -> Void

    var body: some View {
        SignInView(model: model)
            .onChange(of: model.phase) { _, phase in
                if phase == .signedIn { onSignedIn() }
            }
            // Backed out with Menu before finishing: stop the flow for good. Otherwise a code
            // approved later in a browser — or a key check still in flight — could still add the
            // account after the viewer walked away from it.
            .onDisappear {
                if model.phase != .signedIn { model.cancel() }
            }
    }
}

/// What the Accounts page draws — split from `AccountsPage` so the `-uiPreview accounts` harness
/// can show both accounts signed in (with a plan line and a warning) without a session.
struct AccountsContent: View {
    struct Row: Identifiable, Equatable {
        let provider: DebridProvider
        let isSignedIn: Bool
        let detail: String?
        let warning: String?
        var id: DebridProvider { provider }

        init(provider: DebridProvider, isSignedIn: Bool, detail: String? = nil, warning: String? = nil) {
            self.provider = provider
            self.isSignedIn = isSignedIn
            self.detail = detail
            self.warning = warning
        }

        init(_ row: AccountsModel.Row) {
            self.init(provider: row.provider, isSignedIn: row.state == .signedIn,
                      detail: row.detail, warning: row.warning)
        }
    }

    let rows: [Row]
    let showsAddTargetPicker: Bool
    @Binding var addTarget: DebridProvider
    let onSignIn: (DebridProvider) -> Void
    let onSignOut: (DebridProvider) -> Void
    @State private var help = SettingsHelp()

    var body: some View {
        SettingsPageLayout(title: "Accounts", clearsSideMenu: true) {
            AccountsHelpPane(help: help)
        } rows: {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                section(row, first: index == 0)
            }
            if showsAddTargetPicker { addTargetPicker }
        }
        .environment(help)
    }

    private var signedInCount: Int { rows.filter(\.isSignedIn).count }

    // MARK: - A provider

    /// Two rows in every state, at the same places, and the second is ONE view whose words change:
    /// signing in or out never swaps the row in focus for another (a vanished focused row re-homes
    /// focus somewhere unexpected — `reference-tvos-lazy-focus-traps`).
    @ViewBuilder private func section(_ row: Row, first: Bool) -> some View {
        SettingsSectionHeader(title: row.provider.displayName, first: first)
        // Not a control — there to say what this account is. Pressing it does nothing.
        SettingsRow(title: "Status", value: statusValue(row), help: statusHelp(row)) {}
        if let warning = row.warning {
            SettingsFootnote(text: warning, isError: true)
        }
        SettingsRow(title: row.isSignedIn ? "Sign Out" : "Sign In",
                    destructive: row.isSignedIn,
                    help: row.isSignedIn ? signOutHelp(row) : signInHelp(row)) {
            if row.isSignedIn { onSignOut(row.provider) } else { onSignIn(row.provider) }
        }
    }

    private func statusValue(_ row: Row) -> String {
        guard row.isSignedIn else { return "Not signed in" }
        return row.detail.flatMap { $0.isEmpty ? nil : $0 } ?? "Signed in"
    }

    private func statusHelp(_ row: Row) -> SettingsHelpContent {
        let name = row.provider.displayName
        if let warning = row.warning {
            return SettingsHelpContent(icon: "exclamationmark.triangle.fill", title: name,
                                       text: warning, isError: true)
        }
        let text = row.isSignedIn
            ? "Seret streams directly from your \(name) account."
            : "Not signed in on this Apple TV. Sign in to stream from \(name) too."
        return SettingsHelpContent(icon: "person.badge.key.fill", title: name, text: text)
    }

    private func signOutHelp(_ row: Row) -> SettingsHelpContent {
        let name = row.provider.displayName
        let text = signedInCount > 1
            ? "Removes \(name) from this Apple TV. Its titles leave your library; your watch history stays."
            : "Removes \(name) from this Apple TV. It's your only account, so you'll need to sign in again to watch."
        return SettingsHelpContent(icon: "rectangle.portrait.and.arrow.right", title: "Sign out of \(name)",
                                   text: text)
    }

    private func signInHelp(_ row: Row) -> SettingsHelpContent {
        let text: String
        switch row.provider {
        case .realDebrid:
            text = "Shows a code to enter at real‑debrid.com/device, or paste a Real‑Debrid token."
        case .torBox:
            text = "Shows a code to enter at tor.box/link, or paste a TorBox API key."
        }
        return SettingsHelpContent(icon: "person.badge.plus", title: "Sign in to \(row.provider.displayName)",
                                   text: text)
    }

    // MARK: - Add target

    @ViewBuilder private var addTargetPicker: some View {
        SettingsSectionHeader(title: "Add new titles to")
        ForEach(rows.filter(\.isSignedIn)) { row in
            // Press to choose, as every choice in Settings is — a focus glide changes nothing.
            Button {
                addTarget = row.provider
            } label: {
                SettingsRowLabel(title: row.provider.displayName,
                                 accessory: .check(row.provider == addTarget))
            }
            .buttonStyle(SettingsRowStyle())
            .reportsSettingsHelp(SettingsHelpContent(
                icon: "plus.circle.fill", title: "Add new titles to",
                text: "Titles you add from Search go to \(row.provider.displayName). "
                    + "Both accounts' titles stay in your library."))
        }
    }
}

/// The page's pane, reading the focused row's help itself, so a focus move redraws the pane alone.
private struct AccountsHelpPane: View {
    let help: SettingsHelp

    var body: some View {
        SettingsHelpPane(content: help.current)
    }
}
