import SwiftUI

/// Placeholder signed-in screen. The real library lands in Plan 7b.
struct HomeStubView: View {
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 96)).foregroundStyle(.green)
            Text("Signed in ✓")
                .font(.largeTitle.bold())
            Text("Your library lands here in 7b.")
                .font(.title3).foregroundStyle(.secondary)
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape").font(.title3)
            }
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }
}
