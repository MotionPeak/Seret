import DebridCore
import DebridUI
import SwiftUI

/// tvOS "Who's Watching?" — pick a profile (or add one). Shown by RootView when more than one
/// profile exists and this device hasn't resolved a selection.
struct WhoIsWatchingScreen: View {
    @Environment(AppSession.self) private var session
    @State private var addingName = ""
    @State private var showingAdd = false

    private var profiles: [ProfileDTO] { session.activeProfiles?.roster ?? [] }

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: 60) {
                Text("Who's Watching?")
                    .font(.system(size: 56, weight: .heavy))
                    .foregroundStyle(Theme.Palette.textPrimary)
                HStack(spacing: 50) {
                    ForEach(profiles) { p in
                        Button { session.selectProfile(p.id) } label: { ProfileAvatar(profile: p) }
                            .buttonStyle(.card)
                    }
                    Button { showingAdd = true } label: { AddProfileTile() }
                        .buttonStyle(.card)
                }
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

/// Circular monogram avatar in the profile's color.
private struct ProfileAvatar: View {
    let profile: ProfileDTO
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.Palette.color(for: profile.colorTag))
                    .frame(width: 200, height: 200)
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.system(size: 84, weight: .bold)).foregroundStyle(.black)
            }
            Text(profile.name).font(.title3).foregroundStyle(Theme.Palette.textPrimary)
        }
    }
}

private struct AddProfileTile: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().strokeBorder(Theme.Palette.textSecondary, lineWidth: 3)
                    .frame(width: 200, height: 200)
                Image(systemName: "plus").font(.system(size: 72, weight: .bold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Text("Add Profile").font(.title3).foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
