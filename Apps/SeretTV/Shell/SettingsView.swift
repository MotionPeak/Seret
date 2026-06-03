import SwiftUI

/// Account screen (sidebar destination) + Sign Out. Signing out flips `AppSession` to
/// `.signedOut`, which routes `RootView` to a fresh `SignInView`.
struct SettingsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(spacing: 40) {
            Text("Settings")
                .font(.largeTitle.bold())
            Text("Signed in to Real‑Debrid.")
                .font(.title3).foregroundStyle(.secondary)
            Button(role: .destructive) {
                Task { await session.signOut() }
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.title3)
            }
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Settings")
    }
}
