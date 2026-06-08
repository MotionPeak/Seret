import DebridCore
import DebridUI
import SwiftUI

/// iOS "Who's Watching?" — pick a profile (or add one). Shown by RootView when more than one
/// profile exists and this device hasn't resolved a selection.
struct WhoIsWatchingScreen: View {
    @Environment(AppSession.self) private var session
    @State private var addingName = ""
    @State private var showingAdd = false

    private var profiles: [ProfileDTO] { session.activeProfiles?.roster ?? [] }
    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 28)]

    var body: some View {
        ZStack {
            Theme.Palette.canvas.ignoresSafeArea()
            VStack(spacing: 40) {
                Text("Who's Watching?")
                    .font(Theme.Typo.titleXL())
                    .foregroundStyle(Theme.Palette.textPrimary)
                LazyVGrid(columns: columns, spacing: 28) {
                    ForEach(profiles) { p in
                        Button { session.selectProfile(p.id) } label: { ProfileAvatar(profile: p) }
                            .buttonStyle(.plain)
                    }
                    Button { showingAdd = true } label: { AddProfileTile() }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
            }
        }
        .alert("New Profile", isPresented: $showingAdd) {
            TextField("Name", text: $addingName)
            Button("Create") {
                let name = addingName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task { await session.createProfile(name: name, colorTag: "gold"); addingName = "" }
            }
            Button("Cancel", role: .cancel) { addingName = "" }
        }
    }
}

private struct ProfileAvatar: View {
    let profile: ProfileDTO
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.Palette.color(for: profile.colorTag)).frame(width: 110, height: 110)
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.system(size: 46, weight: .bold)).foregroundStyle(.black)
            }
            Text(profile.name).font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textPrimary)
        }
    }
}

private struct AddProfileTile: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().strokeBorder(Theme.Palette.textSecondary, lineWidth: 2).frame(width: 110, height: 110)
                Image(systemName: "plus").font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Text("Add").font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
