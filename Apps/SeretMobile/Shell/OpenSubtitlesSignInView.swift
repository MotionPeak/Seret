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
        Form {
            Section {
                TextField("Username", text: $model.username)
                    .textContentType(.username).autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $model.password).textContentType(.password)
            } header: {
                Text("OpenSubtitles Account").foregroundStyle(Theme.Palette.gold)
            } footer: {
                Text("Your free OpenSubtitles account is used to download Hebrew/English subtitles during playback.")
                    .font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
            }
            .listRowBackground(Theme.Palette.surface1)

            Section {
                Button {
                    model.save()
                    if model.isConnected { dismiss() }
                } label: {
                    Text("Sign In").frame(maxWidth: .infinity)
                }
                .disabled(!canSubmit)
            } footer: {
                Link("Don’t have an account? Create one at opensubtitles.com",
                     destination: URL(string: "https://www.opensubtitles.com/en/users/sign_up")!)
                    .font(.footnote)
            }
            .listRowBackground(Theme.Palette.surface1)
        }
        .scrollContentBackground(.hidden)
        .background(CanvasBackground())
        .tint(Theme.Palette.gold)
        .navigationTitle("OpenSubtitles")
        .navigationBarTitleDisplayMode(.inline)
    }
}
