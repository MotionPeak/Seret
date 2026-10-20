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

#if DEBUG
    /// The `-uiPreview profiles` harness's roster (the unsigned preview session has none).
    var previewRoster: [ProfileDTO]?
    private var profiles: [ProfileDTO] { previewRoster ?? session.activeProfiles?.roster ?? [] }
#else
    private var profiles: [ProfileDTO] { session.activeProfiles?.roster ?? [] }
#endif

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: 60) {
                Text("Who's Watching?")
                    .displayTitle()
                    .foregroundStyle(Theme.Palette.textPrimary)

                HStack(spacing: 64) {
                    ForEach(profiles) { p in
                        Button { pick(p.id) } label: { ProfileAvatar(profile: p, focused: focusedID == p.id) }
                            .buttonStyle(BareButtonStyle())   // no system focus platter — the scale is our cue
                            .focusEffectDisabled()
                            .focused($focusedID, equals: p.id)
                            .scaleEffect(selectingID == p.id ? 1.3 : (focusedID == p.id ? Theme.Anim.heroFocusScale : 1))
                            .opacity(selectingID != nil && selectingID != p.id ? 0 : 1)
                            .animation(Theme.Anim.heroSpring, value: focusedID)
                    }
                    Button { showingAdd = true } label: { AddProfileTile(focused: focusedID == "add") }
                        .buttonStyle(BareButtonStyle())
                        .focusEffectDisabled()
                        .focused($focusedID, equals: "add")
                        .scaleEffect(focusedID == "add" ? Theme.Anim.heroFocusScale : 1)
                        .opacity(selectingID == nil ? 1 : 0)
                        .animation(Theme.Anim.heroSpring, value: focusedID)
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

/// Circular generated avatar in the profile's color.
struct ProfileAvatar: View {
    let profile: ProfileDTO
    /// Focus draws the white ring every other focused card has, outside the circle.
    var focused = false
    var body: some View {
        VStack(spacing: 18) {
            AvatarCircle(token: profile.avatar, diameter: 200, colorTag: profile.colorTag)
                .padding(8)
                .overlay(Circle().strokeBorder(Theme.Palette.focus, lineWidth: 4).opacity(focused ? 1 : 0))
                .liftShadow(focused)
            Text(profile.name).cardTitle()
                .foregroundStyle(focused ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
        }
        .animation(Theme.Anim.focus, value: focused)
    }
}

struct AddProfileTile: View {
    var focused = false
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(focused ? Theme.Palette.focus : Theme.Palette.glassFaint)
                Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 2).opacity(focused ? 0 : 1)
                Image(systemName: "plus").font(.system(size: 72, weight: .bold))
                    .foregroundStyle(focused ? Theme.Palette.onFocus : Theme.Palette.textSecondary)
            }
            .frame(width: 200, height: 200)
            .padding(8)
            .liftShadow(focused)
            Text("Add Profile").cardTitle()
                .foregroundStyle(focused ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
        }
        .animation(Theme.Anim.focus, value: focused)
    }
}
