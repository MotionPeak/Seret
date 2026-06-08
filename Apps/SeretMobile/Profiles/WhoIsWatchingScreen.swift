import DebridCore
import DebridUI
import SwiftUI

/// iOS "Who's Watching?" — shown on every launch. Pick a profile (or add one).
struct WhoIsWatchingScreen: View {
    @Environment(AppSession.self) private var session
    @State private var showingAdd = false
    /// Called after a profile is picked — lets a modal presentation (Settings → Manage Profiles)
    /// dismiss itself. The launch gate uses the default no-op (it disappears on its own).
    var onPicked: () -> Void = {}

    private var profiles: [ProfileDTO] { session.activeProfiles?.roster ?? [] }
    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 28)]

    var body: some View {
        ZStack {
            Theme.Palette.canvas.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 40) {
                    Text("Who's Watching?")
                        .font(Theme.Typo.titleXL())
                        .foregroundStyle(Theme.Palette.textPrimary)
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(profiles) { p in
                            Button { session.selectProfile(p.id); onPicked() } label: { ProfileAvatar(profile: p) }
                                .buttonStyle(.plain)
                        }
                        Button { showingAdd = true } label: { AddProfileTile() }
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.vertical, 32)
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddProfileScreen().environment(session)
        }
    }
}

private struct ProfileAvatar: View {
    let profile: ProfileDTO
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.Palette.color(for: profile.colorTag)).frame(width: 110, height: 110)
                Text(profile.avatar.isEmpty ? ProfileAvatars.fallback : profile.avatar)
                    .font(.system(size: 56))
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
