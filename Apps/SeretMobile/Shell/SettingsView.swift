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
                Label("Signed in to Real‑Debrid", systemImage: "checkmark.seal")
                Button(role: .destructive) {
                    Task { await session.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section {
                Text(model.isConnected
                     ? "Connected as \(model.username). Used to download Hebrew/English subtitles."
                     : "Add your free OpenSubtitles account to download subtitles during playback.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Username", text: $model.username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $model.password)
                    .textContentType(.password)
                HStack {
                    Button("Save") { model.save() }
                    Spacer()
                    if model.isConnected {
                        Button("Remove", role: .destructive) { model.remove() }
                    }
                }
            } header: {
                Text("OpenSubtitles")
            }

            Section {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
