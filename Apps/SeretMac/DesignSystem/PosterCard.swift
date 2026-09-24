import SwiftUI

/// The extra badges a poster can carry, beyond the watched ✓/progress line every card already
/// shows. Pure data so a caller (a library item vs. a TMDB hit) can build one without any view
/// code knowing the difference.
struct PosterDecor: Equatable {
    /// Top-trailing "in your library" disc — only shown when `badge` is not already `.watched`
    /// (the watched ✓ takes precedence in that corner).
    var owned = false
    /// Top-trailing red "CAM" capsule — takes precedence over both the watched ✓ and the owned disc.
    var cam = false
    /// Top-leading gold bookmark ribbon.
    var onWatchlist = false
    /// Whether a `.watched` badge also dims the art (Home/Browse/Search); My Library keeps its
    /// ✓-only look and leaves this false.
    var dimsWatched = false
    /// The franchise rail's 1-based position disc, top-leading. nil elsewhere.
    var number: Int?
    /// The franchise rail's current film: a 2 pt gold ring around the poster, always on (not a
    /// hover state) — `TitleRails.FranchiseRail` also strips its quick actions and makes Open a
    /// no-op, so this ring is the only thing marking it out.
    var isCurrent = false

    init(owned: Bool = false, cam: Bool = false, onWatchlist: Bool = false, dimsWatched: Bool = false,
        number: Int? = nil, isCurrent: Bool = false) {
        self.owned = owned
        self.cam = cam
        self.onWatchlist = onWatchlist
        self.dimsWatched = dimsWatched
        self.number = number
        self.isCurrent = isCurrent
    }
}

/// A fixed-width poster card: art, badges, a truncating title and a caption below. The width never
/// changes — grids and rails depend on that for their column math.
///
/// Everything the pointer touches — the art, the gold rim, the glare, the badges — is one
/// transformed unit: the tilt/scale/lift below is applied to `poster` (art + every overlay) as a
/// whole, AFTER those overlays are composed onto it, never to a plate sized separately from them.
/// An earlier bug sized an overlay after `.scaleEffect` instead, and the rim visibly drifted off
/// the art's edge on hover — this ordering is what keeps that from happening again.
struct PosterCard: View {
    static let posterSize = CGSize(width: PosterGridLayout.cardWidth, height: 225)

    let title: String
    let caption: String
    let posterURL: URL?
    var badge: WatchBadge = .none
    /// Forces the hover look on — harness only, so the raised/rimmed state can be screenshotted
    /// without a pointer.
    var highlighted: Bool = false
    /// The pointer's position over the poster, in the poster's own unit space (0...1 on each axis).
    /// `nil` = not hovered — no tilt, no glare.
    var pointer: UnitPoint? = nil
    var decor: PosterDecor = PosterDecor()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            poster
                .posterHover(highlighted: highlighted, pointer: pointer)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var poster: some View {
        RemoteImage(url: posterURL)
            .frame(width: Self.posterSize.width, height: Self.posterSize.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay { watchedDim }
            .overlay(alignment: .topTrailing) { trailingBadge }
            .overlay(alignment: .topLeading) { leadingBadge }
            .overlay(alignment: .bottom) { progressLine }
            .overlay { currentRing }
    }

    /// The number disc takes precedence — a franchise tile is never also on the watchlist ribbon's
    /// path in practice, and the disc is the one that matters there.
    @ViewBuilder private var leadingBadge: some View {
        if let number = decor.number {
            numberDisc(number)
        } else {
            watchlistRibbon
        }
    }

    private func numberDisc(_ number: Int) -> some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.6))
            Text("\(number)")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
        .padding(8)
    }

    @ViewBuilder private var currentRing: some View {
        if decor.isCurrent {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.gold, lineWidth: 2)
        }
    }

    /// Watched + owned + CAM share the top-trailing corner: CAM outranks the owned disc, which
    /// outranks the ✓ (Decision 11's stated order — top-trailing = watched ✓ › owned › CAM reads
    /// bottom-to-top as "shown if nothing above it applies", so CAM is drawn last/on top).
    @ViewBuilder private var trailingBadge: some View {
        if decor.cam {
            camBadge
        } else if decor.owned, badge != .watched {
            ownedBadge
        } else if badge == .watched {
            watchedMark
        }
    }

    private var watchedMark: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.6))
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.Palette.gold)
        }
        .frame(width: 22, height: 22)
        .padding(8)
    }

    private var ownedBadge: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.6))
            Image(systemName: "square.stack.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
        .padding(8)
    }

    private var camBadge: some View {
        Text("CAM")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.red.opacity(0.85), in: Capsule())
            .padding(8)
    }

    @ViewBuilder private var watchlistRibbon: some View {
        if decor.onWatchlist {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.Palette.gold)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                .frame(width: 16, height: 24)
                .padding(.leading, 10)
        }
    }

    @ViewBuilder private var watchedDim: some View {
        if badge == .watched, decor.dimsWatched {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color.black.opacity(0.45))
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

/// The loading stand-in for a `PosterCard` / `LandscapeCard`: the art as a shimmer, then a title
/// and a caption line laid out with the cards' own fonts (hidden text under the shimmer bars), so
/// a skeleton is exactly as tall as what replaces it and nothing below jumps when it lands. A
/// single 12 pt bar was ~30 pt shorter than a titled, captioned card.
struct CardSkeleton: View {
    var artSize: CGSize = PosterCard.posterSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShimmerView().frame(width: artSize.width, height: artSize.height)
            Text(verbatim: "Title")
                .font(.system(size: 13, weight: .semibold))
                .hidden()
                .overlay(alignment: .leading) { ShimmerView(cornerRadius: 4).frame(width: 110, height: 12) }
            Text(verbatim: "2024")
                .font(.system(size: 11))
                .hidden()
                .overlay(alignment: .leading) { ShimmerView(cornerRadius: 4).frame(width: 36, height: 9) }
        }
        .accessibilityHidden(true)
    }
}

/// A hook for the pointer tilt + glare style.
enum PosterHoverStyle { case lift }

extension View {
    /// Hover treatment for a poster card: a small lift + a gold rim and glow around the poster art,
    /// plus — when a `pointer` is given — the tilt-toward-the-pointer and glare from mockup 3.
    /// Reduce Motion drops the lift, tilt and glare and keeps only the rim/glow (a cross-fade, no
    /// movement).
    func posterHover(style: PosterHoverStyle = .lift, highlighted: Bool = false,
                     pointer: UnitPoint? = nil) -> some View {
        modifier(PosterHover(style: style, highlighted: highlighted, pointer: pointer))
    }
}

private struct PosterHover: ViewModifier {
    let style: PosterHoverStyle
    let highlighted: Bool
    var pointer: UnitPoint? = nil
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { hovering || highlighted || pointer != nil }
    private var lifted: Bool { active && !reduceMotion }
    private var tilting: Bool { pointer != nil && !reduceMotion }

    private var tilt: PosterTilt {
        guard let pointer, !reduceMotion else { return .flat }
        let size = PosterCard.posterSize
        return PosterTilt(location: CGPoint(x: pointer.x * size.width, y: pointer.y * size.height), in: size)
    }

    func body(content: Content) -> some View {
        content
            .overlay { rim }
            .overlay { glare }
            // A card at rest carries no shadow and no 3D transform at all: a grid scrolls dozens
            // of them, and a (clear) shadow or a perspective matrix on each one is render work
            // on every frame. The shadow lives on a backing shape that exists only while active,
            // and the tilt is ONE rotation about the combined pitch/yaw axis, a no-op at rest.
            .background {
                if active {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(.black)
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                }
            }
            .rotation3DEffect(.degrees(tilting ? tilt.magnitude : 0),
                              axis: tilting ? tilt.axis : (x: 1, y: 0, z: 0), perspective: 0.6)
            .scaleEffect(lifted ? 1.05 : 1)
            .offset(y: lifted ? -6 : 0)
            .animation(Theme.Motion.quick, value: active)
            .onHover { hovering = $0 }
    }

    @ViewBuilder private var rim: some View {
        if active {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.gold.opacity(0.75), lineWidth: 1.5)
                .goldGlow(18, opacity: 0.28)
        }
    }

    @ViewBuilder private var glare: some View {
        if tilting {
            RadialGradient(colors: [Color.white.opacity(0.34), .clear], center: tilt.glare,
                           startRadius: 0, endRadius: 0.58 * PosterCard.posterSize.height)
                .blendMode(.overlay)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }
}
