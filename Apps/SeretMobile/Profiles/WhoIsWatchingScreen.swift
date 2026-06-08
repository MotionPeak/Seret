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
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 28)]

    var body: some View {
        ZStack {
            Theme.Palette.canvas.ignoresSafeArea()
            VStack(spacing: 36) {
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
                .fixedSize(horizontal: true, vertical: false)   // size to content so it centers
                HStack(spacing: 16) {
                    Text("\(profiles.count) profile\(profiles.count == 1 ? "" : "s") · store: \(session.profileStoreMode)")
                        .font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
                    Button("Reload") { Task { await session.reloadProfiles() } }
                        .font(.footnote).tint(Theme.Palette.gold)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
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
