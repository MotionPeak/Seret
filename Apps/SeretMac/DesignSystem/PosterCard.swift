import SwiftUI

/// A fixed-width poster card: art, a watched ✓ or progress line, a truncating title and a caption
/// below. The width never changes — grids and rails depend on that for their column math.
struct PosterCard: View {
    static let posterSize = CGSize(width: PosterGridLayout.cardWidth, height: 225)

    let title: String
    let caption: String
    let posterURL: URL?
    var badge: WatchBadge = .none
    /// Forces the hover look on — harness only, so the raised/rimmed state can be screenshotted
    /// without a pointer.
    var highlighted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            poster
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .frame(width: Self.posterSize.width, alignment: .leading)
        .posterHover(highlighted: highlighted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var poster: some View {
        RemoteImage(url: posterURL)
            .frame(width: Self.posterSize.width, height: Self.posterSize.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(alignment: .topTrailing) { watchedMark }
            .overlay(alignment: .bottom) { progressLine }
    }

    @ViewBuilder private var watchedMark: some View {
        if badge == .watched {
            ZStack {
                Circle().fill(Color.black.opacity(0.6))
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.Palette.gold)
            }
            .frame(width: 22, height: 22)
            .padding(8)
        }
    }

    @ViewBuilder private var progressLine: some View {
        if case let .progress(fraction) = badge {
            GoldProgressBar(fraction: fraction)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }

    private var accessibilityLabel: String {
        switch badge {
        case .none: title
        case .watched: "\(title), watched"
        case .progress(let fraction): "\(title), \(Int((fraction * 100).rounded())) percent watched"
        }
    }
}

/// A hook for M2's pointer tilt + glare — `.posterHover` call sites never change when that lands.
enum PosterHoverStyle { case lift }

extension View {
    /// Hover treatment for a poster card: a small lift + a gold rim and glow around the poster art.
    /// Reduce Motion drops the lift and keeps only the rim/glow (a cross-fade, no movement).
    func posterHover(style: PosterHoverStyle = .lift, highlighted: Bool = false) -> some View {
        modifier(PosterHover(style: style, highlighted: highlighted))
    }
}

private struct PosterHover: ViewModifier {
    let style: PosterHoverStyle
    let highlighted: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { hovering || highlighted }
    private var lifted: Bool { active && !reduceMotion }

    func body(content: Content) -> some View {
        content
            .offset(y: lifted ? -6 : 0)
            .scaleEffect(lifted ? 1.03 : 1)
            .overlay(alignment: .top) { rim }
            .shadow(color: active ? Color.black.opacity(0.5) : .clear, radius: active ? 20 : 0, y: 10)
            .animation(Theme.Motion.quick, value: active)
            .onHover { hovering = $0 }
    }

    @ViewBuilder private var rim: some View {
        if active {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.gold.opacity(0.75), lineWidth: 1.5)
                .frame(width: PosterCard.posterSize.width, height: PosterCard.posterSize.height)
                .goldGlow(18, opacity: 0.28)
        }
    }
}
