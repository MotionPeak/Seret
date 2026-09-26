import SwiftUI

/// A landscape card for the Continue Watching rail and downloads: 264×148 art, a gold progress
/// line along its bottom edge, then a title + caption below. No tilt (it is landscape art, not a
/// poster) — hover is a lift + rim + glow + a centred play glyph.
struct LandscapeCard: View {
    static let artSize = CGSize(width: 264, height: 148)

    let title: String
    let caption: String
    let imageURL: URL?
    var fraction: Double = 0
    /// Forces the hover look on — harness only.
    var highlighted: Bool = false

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { hovering || highlighted }
    private var lifted: Bool { active && !reduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            art
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: Self.artSize.width, alignment: .leading)
        .onHover { hovering = $0 }
    }

    private var art: some View {
        RemoteImage(url: imageURL)
            .frame(width: Self.artSize.width, height: Self.artSize.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay { rim }
            .overlay { playGlyph }
            .overlay(alignment: .bottom) { progress }
            // Shadow only while active (a resting card in a scrolling rail carries none).
            .background {
                if active {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(.black)
                        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
                }
            }
            .scaleEffect(lifted ? 1.02 : 1)
            .offset(y: lifted ? -4 : 0)
            .animation(Theme.Motion.quick, value: active)
    }

    @ViewBuilder private var rim: some View {
        if active {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.gold.opacity(0.75), lineWidth: 1.5)
                .goldGlow(16, opacity: 0.26)
        }
    }

    @ViewBuilder private var playGlyph: some View {
        if active {
            Circle().fill(Color.black.opacity(0.55))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
        }
    }

    @ViewBuilder private var progress: some View {
        if fraction > 0 {
            GoldProgressBar(fraction: fraction)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
    }
}
