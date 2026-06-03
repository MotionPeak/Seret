import SwiftUI

/// Account placeholder + Sign Out. Signing out flips `AppSession` back to `.signedOut`,
/// which routes `RootView` to a fresh `SignInView`.
struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 40) {
            Text("Settings")
                .font(.largeTitle.bold())
            Text("Signed in to Real‑Debrid.")
                .font(.title3).foregroundStyle(.secondary)
            Button(role: .destructive) {
                Task {
                    // Dismiss the sheet first, then sign out — so the signed-out state
                    // flip doesn't tear down this sheet's presenter mid-dismiss.
                    dismiss()
                    await session.signOut()
                }
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.title3)
            }
            Button("Done") { dismiss() }
                .font(.title3)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
