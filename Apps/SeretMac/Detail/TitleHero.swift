import DebridCore
import DebridUI
import SwiftUI

/// The full-bleed backdrop + fade every hero state shares: the real `TitleHero` (once a
/// `DetailStore` exists), `TitleHeroPlaceholder` (before it does) and Home's `HomeHero`. Runs
/// under the floating sidebar — only the copy on top of it clears the sidebar, by
/// `pageLeadingInset`.
///
/// `drifts` runs mockup 3's Ken Burns — a slow 24 s scale + pan, autoreversing — on the image
/// alone (the fades stay put); Reduce Motion drops it to a still frame.
struct HeroBackdrop: View {
    let url: URL?
    var drifts: Bool = false

    @State private var size: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var kenBurns: Bool { drifts && !reduceMotion }

    var body: some View {
        ZStack {
            RemoteImage(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(KenBurnsDrift(active: kenBurns, size: size))
                .clipped()
            LinearGradient(
                stops: [.init(color: .clear, location: 0.45), .init(color: Theme.Palette.canvas, location: 1)],
                startPoint: .top, endPoint: .bottom)
            LinearGradient(
                stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .clear, location: 0.6)],
                startPoint: .leading, endPoint: .trailing)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
    }
}

/// The drift itself: a `phaseAnimator` cycling rest ⇄ drifted every 24 s for as long as the view
/// exists. A `withAnimation(.repeatForever)` fired from `.onAppear` never moved the art at all
/// on Home (two captures 6 s apart were pixel-identical, while a shimmer on the same screen
/// animated), and even when it runs it does not survive the view leaving and re-entering the
/// screen. The phase animator owns its own loop, so a data refresh neither restarts nor stops it.
/// Inactive (Reduce Motion, or a title page) = the image untouched, no animator at all.
private struct KenBurnsDrift: ViewModifier {
    let active: Bool
    let size: CGSize

    func body(content: Content) -> some View {
        if active {
            content.phaseAnimator([false, true]) { image, drifted in
                image
                    .scaleEffect(drifted ? 1.09 : 1)
                    .offset(x: drifted ? -0.014 * size.width : 0, y: drifted ? -0.012 * size.height : 0)
            } animation: { _ in .easeInOut(duration: 24) }
        } else {
            content
        }
    }
}

/// A film's resolution/source/codec pill. File-internal (not `private`) — the Versions list
/// (Task 5) draws the same chip for an owned copy.
struct QualityChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.Palette.chipFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// While the store is still resolving: the backdrop and title from the `MediaItem` alone, with
/// shimmer where the buttons go. Never a spinner.
struct TitleHeroPlaceholder: View {
    let item: MediaItem

    @Environment(\.pageLeadingInset) private var pageLeadingInset
    @State private var width: CGFloat = 1200

    private var height: CGFloat { TitlePageLayout.heroHeight(width: width) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                Text(item.title)
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
                ShimmerView(cornerRadius: 6).frame(width: 220, height: 40)
            }
            .padding(.leading, pageLeadingInset + 8)
            .padding(.bottom, 28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background {
            HeroBackdrop(url: TMDBClient.imageURL(path: item.backdropPath ?? item.posterPath, size: "w1280"))
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .clipped()
    }
}

/// The title page's hero: full-bleed backdrop (parallaxing and fading on scroll), logo art, the
/// meta + credit line, the franchise line, quality/rating chips and the action row.
struct TitleHero: View {
    let store: DetailStore
    let acquirer: TitleAcquirer?
    /// The page's `ScrollView` offset, for the backdrop parallax (Decision 12). 0 when the page
    /// itself does not track it (e.g. the placeholder never scrolls under this view alone).
    var scrollOffset: CGFloat = 0

    @Environment(\.pageLeadingInset) private var pageLeadingInset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 1200

    private var height: CGFloat { TitlePageLayout.heroHeight(width: width) }

    /// 0.4× the scroll offset — Reduce Motion drops the parallax to a still frame (Decision 12).
    private var parallaxOffset: CGFloat {
        reduceMotion ? 0 : max(0, scrollOffset) * 0.4
    }

    /// Fades out across the hero's own height, floor 0.
    private var backdropOpacity: Double {
        guard height > 0 else { return 1 }
        return 1 - min(1, max(0, scrollOffset) / height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            copy
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background {
            HeroBackdrop(url: TMDBClient.imageURL(path: store.backdropPath ?? store.item.posterPath, size: "w1280"))
                .offset(y: parallaxOffset)
                .opacity(backdropOpacity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .clipped()
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 10) {
            TitleLogo(path: store.logoPath, title: store.item.title)
            metaAndCreditLine
            if let franchise = store.franchise {
                Text(TitlePageText.franchiseLine(franchise))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.gold)
            }
            if !qualityChips.isEmpty || hasAnyRatingChip { chipRow }
            TitleActionsRow(store: store, acquirer: acquirer)
        }
        .padding(.leading, pageLeadingInset + 8)
        .padding(.bottom, 28)
        .frame(maxWidth: 640, alignment: .leading)
    }

    // MARK: - Meta + credit

    private var metaLine: String {
        TitlePageText.metaLine(
            year: store.item.year,
            runtimeMinutes: store.item.kind == .movie ? store.runtime : nil,
            genres: store.genres,
            seasonCount: store.item.kind == .show ? store.numberOfSeasons : nil)
    }

    /// "Dir." + bold director names (film) / "Created by" + bold creator names (show), appended
    /// to the meta line. nil credit → the meta line alone.
    private var creditParts: (prefix: String, names: String)? {
        let names = store.item.kind == .movie ? store.directors.map(\.name) : store.creatorRefs.map(\.name)
        guard !names.isEmpty else { return nil }
        return (store.item.kind == .movie ? "Dir." : "Created by", names.joined(separator: ", "))
    }

    private var metaAndCreditLine: some View {
        Group {
            if let parts = creditParts {
                Text("\(metaLine) \u{00B7} \(parts.prefix) \(Text(parts.names).fontWeight(.bold))")
            } else {
                Text(metaLine)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.white.opacity(0.8))
    }

    // MARK: - Chip row

    /// Films only, and only once owned — a show's chips would just repeat the meta line's season
    /// count, and an unowned film has no source to describe.
    private var qualityChips: [String] {
        guard store.item.kind == .movie, let parsed = store.bestSource?.parsed else { return [] }
        return [parsed.resolution, parsed.source, parsed.videoCodec, parsed.audioCodec].compactMap { $0 }
    }

    private var hasAnyRatingChip: Bool {
        store.ratingsState == .loading || store.letterboxdState == .loading
            || (store.ratings?.hasAny ?? false) || store.letterboxdRating != nil
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(qualityChips, id: \.self) { QualityChip(text: $0) }
            if !qualityChips.isEmpty, hasAnyRatingChip {
                Rectangle().fill(Theme.Palette.hairline).frame(width: 1, height: 14)
            }
            RatingChips(store: store)
        }
        // The row can run wider than the 640 pt copy column once every chip is present — never
        // compress a chip's text into a vertical wrap to force it back inside that width.
        .fixedSize(horizontal: true, vertical: false)
    }
}
