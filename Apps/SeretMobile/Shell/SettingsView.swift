import DebridCore
import DebridUI
import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var model = SettingsModel(
        secretStore: KeychainSecretStore(service: "com.solomons.seret.opensubtitles"))

    var body: some View {
        Form {
            Section("Account") {
                Label("Signed in to Real‑Debrid", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.Palette.textPrimary)
                Button(role: .destructive) {
                    Task { await session.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .listRowBackground(Theme.Palette.surface1)

            Section {
                Text(model.isConnected
                     ? "Connected as \(model.username). Used to download Hebrew/English subtitles."
                     : "Add your free OpenSubtitles account to download subtitles during playback.")
                    .font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
                TextField("Username", text: $model.username)
                    .textContentType(.username).autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField("Password", text: $model.password).textContentType(.password)
                HStack {
                    Button("Save") { model.save() }
                    Spacer()
                    if model.isConnected {
                        Button("Remove", role: .destructive) { model.remove() }
                    }
                }
            } header: {
                Text("OpenSubtitles").foregroundStyle(Theme.Palette.gold)
            }
            .listRowBackground(Theme.Palette.surface1)

            Section {
                LabeledContent("Version", value: appVersion)
                    .foregroundStyle(Theme.Palette.textSecondary)
            } footer: {
                HStack(spacing: Theme.Space.sm) {
                    SeretMark(glow: false).frame(width: 16)
                    Text("Seret").font(Theme.Typo.label()).foregroundStyle(Theme.Palette.textTertiary)
                }
                .frame(maxWidth: .infinity).padding(.top, Theme.Space.lg)
            }
            .listRowBackground(Theme.Palette.surface1)
        }
        .scrollContentBackground(.hidden)
        .background(CanvasBackground())
        .tint(Theme.Palette.gold)
        .navigationTitle("Settings")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
