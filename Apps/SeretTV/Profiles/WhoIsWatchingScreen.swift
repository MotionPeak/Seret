import DebridCore
import DebridUI
import SwiftUI

/// tvOS "Who's Watching?" — shown on every launch. Pick a profile (or add one). Centered box.
struct WhoIsWatchingScreen: View {
    @Environment(AppSession.self) private var session
    @State private var showingAdd = false
    /// Called after a profile is picked — lets a modal presentation (Settings → Manage Profiles)
    /// dismiss itself. The launch gate uses the default no-op (it disappears on its own).
    var onPicked: () -> Void = {}

    private var profiles: [ProfileDTO] { session.activeProfiles?.roster ?? [] }

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: 54) {
                Text("Who's Watching?")
                    .font(.system(size: 56, weight: .heavy))
                    .foregroundStyle(Theme.Palette.textPrimary)

                HStack(spacing: 56) {
                    ForEach(profiles) { p in
                        Button { session.selectProfile(p.id); onPicked() } label: { ProfileAvatar(profile: p) }
                            .buttonStyle(.card)
                    }
                    Button { showingAdd = true } label: { AddProfileTile() }
                        .buttonStyle(.card)
                }
                .frame(maxWidth: .infinity)   // centers the row of avatars
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(60)
        }
        .fullScreenCover(isPresented: $showingAdd) {
            AddProfileScreen().environment(session)
        }
    }
}

/// Circular emoji avatar in the profile's color.
struct ProfileAvatar: View {
    let profile: ProfileDTO
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.Palette.color(for: profile.colorTag))
                    .frame(width: 200, height: 200)
                Text(profile.avatar.isEmpty ? ProfileAvatars.fallback : profile.avatar)
                    .font(.system(size: 110))
            }
            Text(profile.name).font(.title3).foregroundStyle(Theme.Palette.textPrimary)
        }
    }
}

struct AddProfileTile: View {
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
