import DebridCore
import DebridUI
import SwiftUI

/// tvOS "Who's Watching?" — shown on every launch. Pick a profile (or add one). Centered box.
struct WhoIsWatchingScreen: View {
    @Environment(AppSession.self) private var session
    @State private var showingAdd = false
    @State private var selectingID: String?
    @FocusState private var focusedID: String?
    /// Called after a profile is picked — lets a modal presentation (Settings → Manage Profiles)
    /// dismiss itself. The launch gate uses the default no-op (it disappears on its own).
    var onPicked: () -> Void = {}

    private var profiles: [ProfileDTO] { session.activeProfiles?.roster ?? [] }

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: 60) {
                Text("Who's Watching?")
                    .font(.system(size: 64, weight: .heavy))
                    .foregroundStyle(Theme.Palette.textPrimary)

                HStack(spacing: 64) {
                    ForEach(profiles) { p in
                        Button { pick(p.id) } label: { ProfileAvatar(profile: p) }
                            .buttonStyle(.plain)
                            .focused($focusedID, equals: p.id)
                            .scaleEffect(selectingID == p.id ? 1.3 : (focusedID == p.id ? 1.12 : 1))
                            .opacity(selectingID != nil && selectingID != p.id ? 0 : 1)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: focusedID)
                    }
                    Button { showingAdd = true } label: { AddProfileTile() }
                        .buttonStyle(.plain)
                        .focused($focusedID, equals: "add")
                        .scaleEffect(focusedID == "add" ? 1.12 : 1)
                        .opacity(selectingID == nil ? 1 : 0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: focusedID)
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

    private func pick(_ id: String) {
        withAnimation(.easeInOut(duration: 0.4)) {
            selectingID = id
        } completion: {
            session.selectProfile(id); onPicked()
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
