import DebridCore
import DebridUI
import SwiftUI

/// iOS "Who's Watching?" — shown on every launch. Centered, animated profile picker.
struct WhoIsWatchingScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var showingAdd = false
    @State private var selectingID: String?
    @State private var appeared = false
    /// Called after a profile is picked — lets a modal presentation (Settings → Manage Profiles)
    /// dismiss itself. The launch gate uses the default no-op (it disappears on its own).
    var onPicked: () -> Void = {}

    private var profiles: [ProfileDTO] { session.activeProfiles?.roster ?? [] }
    private var isPad: Bool { hSize == .regular }
    private var diameter: CGFloat { isPad ? 150 : 104 }
    private var spacing: CGFloat { isPad ? 52 : 30 }

    var body: some View {
        ZStack {
            Theme.Palette.canvas.ignoresSafeArea()
            VStack(spacing: isPad ? 64 : 44) {
                Text("Who's Watching?")
                    .font(.system(size: isPad ? 52 : 32, weight: .heavy))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .opacity(appeared ? 1 : 0)

                HStack(spacing: spacing) {
                    ForEach(profiles) { p in
                        avatarButton(p)
                    }
                    Button { showingAdd = true } label: { AddTile(diameter: diameter) }
                        .buttonStyle(PressableStyle())
                        .opacity(selectingID == nil ? 1 : 0)
                }
                .frame(maxWidth: .infinity)   // centers the row
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appeared = true } }
        .fullScreenCover(isPresented: $showingAdd) {
            AddProfileScreen().environment(session)
        }
    }

    private func avatarButton(_ p: ProfileDTO) -> some View {
        let isSelecting = selectingID == p.id
        let dimmed = selectingID != nil && !isSelecting
        return Button {
            withAnimation(.easeInOut(duration: 0.4)) {
                selectingID = p.id
            } completion: {
                session.selectProfile(p.id); onPicked()
            }
        } label: {
            Avatar(profile: p, diameter: diameter)
        }
        .buttonStyle(PressableStyle())
        .scaleEffect(isSelecting ? 1.35 : (appeared ? 1 : 0.85))
        .opacity(dimmed ? 0 : (appeared ? 1 : 0))
    }
}

/// Press-down spring scale — gives the tap a tactile feel.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct Avatar: View {
    let profile: ProfileDTO
    let diameter: CGFloat
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.Palette.color(for: profile.colorTag))
                    .frame(width: diameter, height: diameter)
                    .shadow(color: Theme.Palette.color(for: profile.colorTag).opacity(0.5), radius: 14, y: 4)
                Text(profile.avatar.isEmpty ? ProfileAvatars.fallback : profile.avatar)
                    .font(.system(size: diameter * 0.5))
            }
            Text(profile.name).font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }
}

private struct AddTile: View {
    let diameter: CGFloat
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().strokeBorder(Theme.Palette.textSecondary, lineWidth: 2)
                    .frame(width: diameter, height: diameter)
                Image(systemName: "plus").font(.system(size: diameter * 0.34, weight: .bold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Text("Add").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
