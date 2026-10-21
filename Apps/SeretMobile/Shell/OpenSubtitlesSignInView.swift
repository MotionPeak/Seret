import DebridCore
import DebridUI
import SwiftUI

/// Dedicated OpenSubtitles sign-in screen, reached by a redirect row in Settings.
/// Holds the username/password form; on a successful save it pops back to Settings,
/// where a "Signed in to OpenSubtitles" badge takes its place.
struct OpenSubtitlesSignInView: View {
    @Bindable var model: SettingsModel
    @Environment(\.dismiss) private var dismiss

    private var canSubmit: Bool {
        !model.username.trimmingCharacters(in: .whitespaces).isEmpty && !model.password.isEmpty
    }

    var body: some View {
        GlassFormPage {
            GlassSection(title: "OpenSubtitles account",
                         footer: "Your free OpenSubtitles account is used to download Hebrew/English subtitles during playback.") {
                GlassField(label: "Username", text: $model.username, prompt: "OpenSubtitles username",
                           contentType: .username)
                GlassField(label: "Password", text: $model.password, prompt: "Password", secure: true,
                           contentType: .password)
            }
            Button {
                model.save()
                if model.isConnected { dismiss() }
            } label: {
                Text("Sign In")
            }
            .buttonStyle(PrimaryPillButtonStyle(fullWidth: true))
            .disabled(!canSubmit)
            Link("Don\u{2019}t have an account? Create one at opensubtitles.com",
                 destination: URL(string: "https://www.opensubtitles.com/en/users/sign_up")!)
                .font(.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity)
        }
        .tint(Theme.Palette.focus)
        .navigationTitle("OpenSubtitles")
        .navigationBarTitleDisplayMode(.inline)
    }
}
