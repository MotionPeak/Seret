import SwiftUI
import DebridUI
import DebridCore

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var model = SettingsModel(
        secretStore: KeychainSecretStore(service: "com.solomons.seret.opensubtitles"))

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: 40) {
                Text("Settings").font(.largeTitle.bold()).foregroundStyle(Theme.Palette.textPrimary)
                Text("Signed in to Real‑Debrid.").font(.title3).foregroundStyle(Theme.Palette.textSecondary)

                VStack(alignment: .leading, spacing: 16) {
                    Label("OpenSubtitles account", systemImage: "captions.bubble.fill")
                        .font(.title3.bold()).foregroundStyle(Theme.Palette.gold)
                    Text(model.isConnected
                         ? "Connected as \(model.username). Used to download Hebrew/English subtitles."
                         : "Add your free OpenSubtitles account to download subtitles during playback.")
                        .font(.callout).foregroundStyle(Theme.Palette.textSecondary)
                    TextField("Username", text: $model.username)
                        .textContentType(.username)
                    SecureField("Password", text: $model.password)
                        .textContentType(.password)
                    HStack(spacing: 20) {
                        Button("Save") { model.save() }
                        if model.isConnected {
                            Button("Remove", role: .destructive) { model.remove() }
                        }
                    }
                }
                .frame(maxWidth: 700)
                .padding(40)
                .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: 24))

                Button(role: .destructive) {
                    Task { await session.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right").font(.title3)
                }
            }
            .padding(80)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Settings")
    }
}
