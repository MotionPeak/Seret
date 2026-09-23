import DebridUI
import SwiftUI

/// Loading / buffering / failure state over the picture, plus the player's (temporary — Task 7
/// replaces it with the real top bar) back button. No spinner anywhere: loading is shimmer,
/// buffering is a small glass capsule.
struct PlayerStateOverlays: View {
    let model: PlayerModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            stateLayer
            backButtonLayer
        }
    }

    @ViewBuilder private var stateLayer: some View {
        if case .failed(let message) = model.phase {
            failedPanel(message)
        } else if model.isColdOpen {
            coldOpen
        } else if model.isBuffering, model.hasRenderedFrame {
            bufferingCapsule
        }
    }

    private var coldOpen: some View {
        VStack(spacing: 14) {
            Text(model.label)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Preparing…")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
            ShimmerView(cornerRadius: 1.5).frame(width: 160, height: 3)
        }
        .padding(.horizontal, 40)
    }

    private var bufferingCapsule: some View {
        VStack {
            Text("Buffering…")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .glassEffect(.regular, in: Capsule())
                .padding(.top, 24)
            Spacer()
        }
    }

    private func failedPanel(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("Couldn't Play This")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Retry") { model.retry() }
                    .buttonStyle(GoldButtonStyle())
                if model.canTryAnotherVersion {
                    Button("Try Another Version") { model.tryAnotherVersion() }
                        .buttonStyle(GlassButtonStyle())
                }
                Button("Back", action: onClose)
                    .buttonStyle(GlassButtonStyle())
            }
        }
        .padding(28)
        .frame(width: 420)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var backButtonLayer: some View {
        VStack {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .frame(width: 35, height: 35)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Back (Esc)")
                .padding(.leading, 92)
                .padding(.top, 24)
                Spacer()
            }
            Spacer()
        }
    }
}
