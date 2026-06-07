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
            ScrollView {
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

                VStack(alignment: .leading, spacing: 16) {
                    Label("Subtitles", systemImage: "textformat.size")
                        .font(.title3.bold()).foregroundStyle(Theme.Palette.gold)
                    Text("Applies to every movie and show. Takes effect on the next playback.")
                        .font(.callout).foregroundStyle(Theme.Palette.textSecondary)
                    Picker("Size", selection: subtitleSize) {
                        ForEach(SubtitlePreferences.Size.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    Picker("Font", selection: subtitleFont) {
                        ForEach(SubtitlePreferences.Font.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    Picker("Color", selection: subtitleColor) {
                        ForEach(SubtitlePreferences.Color.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                }
                .frame(maxWidth: 900)

                Button(role: .destructive) {
                    Task { await session.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right").font(.title3)
                }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 80)
                .padding(.top, 20)
                .padding(.bottom, 80)
            }
        }
    }

    // Bindings into the shared, persisted subtitle preferences.
    private var subtitleSize: Binding<SubtitlePreferences.Size> {
        Binding(get: { session.subtitleSettings.preferences.size },
                set: { session.subtitleSettings.preferences.size = $0 })
    }
    private var subtitleFont: Binding<SubtitlePreferences.Font> {
        Binding(get: { session.subtitleSettings.preferences.font },
                set: { session.subtitleSettings.preferences.font = $0 })
    }
    private var subtitleColor: Binding<SubtitlePreferences.Color> {
        Binding(get: { session.subtitleSettings.preferences.color },
                set: { session.subtitleSettings.preferences.color = $0 })
    }
}
