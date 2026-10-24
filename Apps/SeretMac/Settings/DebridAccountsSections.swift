import DebridCore
import DebridUI
import SwiftUI

/// One debrid account as Settings → Accounts draws it — `AccountsModel.Row`'s fields, in a type a
/// DEBUG harness can build without a session.
struct AccountRowFace: Identifiable, Equatable {
    let provider: DebridProvider
    let signedIn: Bool
    let detail: String?
    let warning: String?
    var id: DebridProvider { provider }

    init(provider: DebridProvider, signedIn: Bool, detail: String? = nil, warning: String? = nil) {
        self.provider = provider
        self.signedIn = signedIn
        self.detail = detail
        self.warning = warning
    }

    init(_ row: AccountsModel.Row) {
        self.init(provider: row.provider, signedIn: row.state == .signedIn, detail: row.detail, warning: row.warning)
    }
}

/// The debrid accounts' sections of the Accounts tab: a section per provider with what it is
/// signed in as and its Sign In… / Sign Out…, then — with both signed in — where new titles go.
/// Pure: the Accounts tab owns the model, the sheet and the confirmation.
struct DebridAccountsSections: View {
    let rows: [AccountRowFace]
    /// Sign In… only while the app itself is signed in. Signed out, the main window's own sign-in is
    /// the way in — two device-code flows at once would only trip Real-Debrid's throttle.
    let canAddAccounts: Bool
    @Binding var addTarget: DebridProvider
    let signIn: (DebridProvider) -> Void
    let signOut: (DebridProvider) -> Void

    private var signedIn: [DebridProvider] { rows.filter(\.signedIn).map(\.provider) }

    var body: some View {
        ForEach(rows) { row in
            Section {
                LabeledContent("Account") { status(row) }
                if let warning = row.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if row.signedIn {
                    Button("Sign Out…", role: .destructive) { signOut(row.provider) }
                } else if canAddAccounts {
                    Button("Sign In…") { signIn(row.provider) }
                }
            } header: {
                Text(row.provider.displayName)
            } footer: {
                if row.provider == rows.last?.provider, signedIn.count == 1, canAddAccounts {
                    Text(DebridCopy.addAccountHint(signedIn: signedIn))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        // Where new titles go only means something with two accounts to choose between.
        if signedIn.count > 1 {
            Section {
                Picker("Add new titles to", selection: $addTarget) {
                    ForEach(signedIn, id: \.self) { Text($0.displayName).tag($0) }
                }
            } footer: {
                Text("Titles from both accounts appear together. Titles you add go to the account chosen here.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func status(_ row: AccountRowFace) -> some View {
        if row.signedIn {
            VStack(alignment: .trailing, spacing: 2) {
                Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                if let detail = row.detail {
                    Text(detail)
                        .font(.footnote).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        } else {
            Text("Not signed in").foregroundStyle(.secondary)
        }
    }
}

/// Settings → Accounts' "Sign In…": the sign-in card for one more account, in a sheet. Closes
/// itself once the account is in; Cancel (or Esc) closes it unfinished.
struct AddAccountSheet: View {
    let model: SignInModel
    let close: () -> Void

    var body: some View {
        SignInView(model: model, style: .sheet, onCancel: close)
            .onChange(of: model.phase) { _, phase in
                if phase == .signedIn { close() }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.Palette.gold)
    }
}
