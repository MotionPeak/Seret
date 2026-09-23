import DebridUI
import SwiftUI

/// The Settings window (⌘,). M1 carries what the app cannot do without: seeing that Real-Debrid is
/// signed in, and signing out. Letterboxd, OpenSubtitles, Playback and Profiles arrive in M5.
struct SettingsRoot: View {
    var body: some View {
        TabView {
            Tab("Accounts", systemImage: "person.crop.circle") { AccountsSettings() }
            Tab("About", systemImage: "info.circle") { AboutSettings() }
        }
        .frame(width: 560, height: 340)
        .preferredColorScheme(.dark)
    }
}

private struct AccountsSettings: View {
    @Environment(AppSession.self) private var session
    @State private var confirmingSignOut = false

    var body: some View {
        Form {
            Section("Real-Debrid") {
                LabeledContent("Account") {
                    if session.state == .signedIn {
                        Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Text("Not signed in").foregroundStyle(.secondary)
                    }
                }
                if session.state == .signedIn {
                    Button("Sign Out…", role: .destructive) { confirmingSignOut = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Sign out of Real-Debrid on this Mac?", isPresented: $confirmingSignOut) {
            Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
        } message: {
            Text("Your library and watch history stay; you'll sign in again with a code or a token.")
        }
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            SeretMark().frame(width: 64)
            Wordmark(hebrewSize: 34)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
