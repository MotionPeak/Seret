import DebridCore
import DebridUI
import SwiftUI

/// Settings → Accounts: each debrid account, what it is signed in as, and its Sign In / Sign Out —
/// plus, with both signed in, where new titles go. `AccountsModel` reads the session; this only
/// draws it.
///
/// "Sign In" for an account that isn't signed in opens the same sign-in screen the app starts on
/// (`SignInView`, minus the provider picker) in a sheet, while the app stays signed in. A sheet
/// closed before the sign-in completes stops its model, so a code approved later can't add the
/// account behind the viewer's back.
struct AccountsSection: View {
    @Environment(AppSession.self) private var session
    /// Built from the session once this is on screen, and held so its TorBox details survive redraws.
    @State private var model: AccountsModel?
    /// The sign-in the sheet is showing. Kept apart from the sheet's flag so `onDismiss` still has it.
    @State private var addingModel: SignInModel?
    @State private var showingSignIn = false
    @State private var confirmingSignOut: DebridProvider?
#if DEBUG
    @Environment(\.uiPreviewStores) private var preview
#endif

    var body: some View {
        content
            .task {
#if DEBUG
                if preview?.accounts != nil { return }
#endif
                if model == nil { model = AccountsModel(session: session) }
                await model?.load()
            }
            .sheet(isPresented: $showingSignIn, onDismiss: finishSignIn) {
                if let addingModel {
                    AddAccountSheet(model: addingModel) { showingSignIn = false }
                }
            }
            .confirmationDialog(signOutTitle, isPresented: signOutDialog, titleVisibility: .visible,
                                presenting: confirmingSignOut) { provider in
                Button("Sign Out", role: .destructive) {
                    Task { await model?.signOut(provider) }
                }
            } message: { _ in
                Text(signOutMessage)
            }
    }

    @ViewBuilder private var content: some View {
#if DEBUG
        if let fixture = preview?.accounts {
            AccountsSectionContent(rows: fixture.rows, addTarget: .constant(fixture.addTarget),
                                   signIn: { _ in }, signOut: { _ in })
        } else {
            live
        }
#else
        live
#endif
    }

    /// Both rows as the session has them — drawn even before `model` exists, so the section never
    /// pops in late (it is the first thing in Settings).
    private var live: some View {
        AccountsSectionContent(
            rows: model?.rows.map(AccountRowFace.init) ?? fallbackRows,
            addTarget: Binding(get: { session.addTarget }, set: { session.addTarget = $0 }),
            signIn: beginSignIn,
            signOut: { confirmingSignOut = $0 })
    }

    private var fallbackRows: [AccountRowFace] {
        DebridProvider.allCases.map {
            AccountRowFace(provider: $0, signedIn: session.accounts[$0] == .signedIn, detail: nil, warning: nil)
        }
    }

    private func beginSignIn(_ provider: DebridProvider) {
        guard let model else { return }
        addingModel = model.signIn(provider)
        showingSignIn = true
    }

    /// The sheet is gone, however it went. Unfinished, its model stops; either way the rows are
    /// read again (a new TorBox account brings its email and plan).
    private func finishSignIn() {
        if let addingModel, addingModel.phase != .signedIn { addingModel.cancel() }
        addingModel = nil
        Task { await model?.load() }
    }

    private var signOutDialog: Binding<Bool> {
        Binding(get: { confirmingSignOut != nil }, set: { if !$0 { confirmingSignOut = nil } })
    }

    private var signOutTitle: String {
        guard let provider = confirmingSignOut else { return "" }
        return "Sign out of \(provider.displayName)?"
    }

    private var signOutMessage: String {
        let others = session.signedInProviders.filter { $0 != confirmingSignOut }
        return others.isEmpty
            ? "You'll go back to the sign-in screen. Your watch history stays."
            : "Its titles leave your library. Your watch history stays."
    }
}

/// One account row as drawn — `AccountsModel.Row`'s fields, in a type a DEBUG harness can build.
struct AccountRowFace: Identifiable, Equatable {
    let provider: DebridProvider
    let signedIn: Bool
    let detail: String?
    let warning: String?
    var id: DebridProvider { provider }

    init(provider: DebridProvider, signedIn: Bool, detail: String?, warning: String?) {
        self.provider = provider
        self.signedIn = signedIn
        self.detail = detail
        self.warning = warning
    }

    init(_ row: AccountsModel.Row) {
        self.init(provider: row.provider, signedIn: row.state == .signedIn, detail: row.detail,
                  warning: row.warning)
    }
}

/// The section itself: a status row and its action for each account, then the add-target choice.
struct AccountsSectionContent: View {
    let rows: [AccountRowFace]
    @Binding var addTarget: DebridProvider
    let signIn: (DebridProvider) -> Void
    let signOut: (DebridProvider) -> Void

    private var signedIn: [DebridProvider] { rows.filter(\.signedIn).map(\.provider) }

    var body: some View {
        GlassSection(title: "Accounts", footer: footer) {
            ForEach(rows) { row in
                if row.signedIn {
                    status(row)
                    GlassButtonRow(title: "Sign Out of \(row.provider.uiName)",
                                   systemImage: "rectangle.portrait.and.arrow.right",
                                   destructive: true) { signOut(row.provider) }
                } else {
                    GlassButtonRow(title: "Sign In to \(row.provider.uiName)",
                                   systemImage: "person.crop.circle.badge.plus") { signIn(row.provider) }
                }
            }
            // Where new titles go only means something with two accounts to choose between.
            if signedIn.count > 1 {
                GlassPickerRow(title: "Add new titles to", selection: $addTarget) {
                    ForEach(signedIn, id: \.self) { Text($0.uiName).tag($0) }
                }
            }
        }
    }

    private func status(_ row: AccountRowFace) -> some View {
        GlassRow {
            Image(systemName: "checkmark.seal.fill")
                .frame(width: 24)
                .foregroundStyle(Theme.Palette.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.provider.uiName)
                Text(row.detail ?? "Signed in")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let warning = row.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: String {
        signedIn.count > 1
            ? "Titles from both accounts appear together. New titles you add go to the account chosen above."
            : DebridCopy.addAccountHint(signedIn: signedIn)
    }
}

/// The sign-in screen for one more account, in a sheet. Closes itself once the account is in.
private struct AddAccountSheet: View {
    let model: SignInModel
    let close: () -> Void

    var body: some View {
        NavigationStack {
            SignInView(model: model)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: close)
                    }
                }
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .signedIn { close() }
        }
        .tint(Theme.Palette.focus)
        .preferredColorScheme(.dark)
    }
}

extension DebridProvider {
    /// The display name with a non-breaking hyphen, so "Real‑Debrid" never wraps at its hyphen.
    var uiName: String { displayName.replacingOccurrences(of: "-", with: "\u{2011}") }
}
