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
    /// Whether the backdrop is on screen at all; the drift only runs while it is.
    @State private var onScreen = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isPageShown) private var isPageShown

    /// The drift runs only where it can be seen: not under Reduce Motion, not on a section kept
    /// alive behind the current one, not once the hero has scrolled away.
    private var kenBurns: Bool { drifts && !reduceMotion && isPageShown && onScreen }

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
        .onScrollVisibilityChange(threshold: 0.05) { onScreen = $0 }
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
    /// nil until the page's own trailer resolution starts (Task 4). The muted inline loop and the
    /// two bottom-trailing capsules only ever appear once it has a stream to show.
    var trailer: TrailerModel?
    /// Set by the page once its 4 s / autoplay-setting gate lets the inline trailer start.
    var autoplayArmed = false
    /// Opens the page's Versions sheet — threaded down to `TitleActionsRow`'s ⋯ menu.
    var onFindOtherVersions: () -> Void = {}
    /// `false` while a forward flight for THIS title is still mid-air (Task 8): the real backdrop
    /// stays invisible (the flyer is showing it instead) and the copy holds off its cascade.
    var cascadeActive = true

    @Environment(\.pageLeadingInset) private var pageLeadingInset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ShellModel.self) private var shell: ShellModel?
    @State private var width: CGFloat = 1200
    @State private var showVideo = false
    @State private var muted = true
    @State private var heroVisible = true

    private var height: CGFloat { TitlePageLayout.heroHeight(width: width) }


    /// The inline loop only actually renders while every one of these holds — armed, the hero is
    /// on screen, Reduce Motion is off, and neither the player nor the full trailer is up.
    private var trailerActive: Bool {
        showVideo && heroVisible && !reduceMotion && shell?.playback == nil && shell?.trailer == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            copy
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background {
            ZStack {
                HeroBackdrop(url: TMDBClient.imageURL(path: store.backdropPath ?? store.item.posterPath, size: "w1280"))
                if trailerActive, let url = trailer?.streamURL {
                    // The trailer covers the backdrop's own shading, so it carries its own — a
                    // little heavier, since a trailer is often brighter than a still.
                    InlineTrailer(url: url, muted: $muted)
                        .overlay {
                            ZStack {
                                LinearGradient(
                                    stops: [.init(color: .clear, location: 0.4), .init(color: Theme.Palette.canvas, location: 1)],
                                    startPoint: .top, endPoint: .bottom)
                                LinearGradient(
                                    stops: [.init(color: .black.opacity(0.7), location: 0), .init(color: .clear, location: 0.65)],
                                    startPoint: .leading, endPoint: .trailing)
                            }
                            .allowsHitTesting(false)
                        }
                        .transition(.opacity)
                }
            }
            // Parallax (0.4× the scroll, Reduce Motion: none) and a fade across the hero's own
            // height, computed per frame from this view's own position in the scroll view. It used
            // to be a page-level `@State` offset written on every scroll frame, which re-evaluated
            // the WHOLE title page 120 times a second — the stutter on a ProMotion display.
            .visualEffect { [factor = reduceMotion ? 0 : 0.4, height] content, proxy in
                let scrolled = max(0, -proxy.frame(in: .scrollView).minY)
                return content
                    .offset(y: scrolled * factor)
                    .opacity(height > 0 ? 1 - min(1, scrolled / height) : 1)
            }
            // The flyer paints this exact band while it is mid-air — the real backdrop only takes
            // over once `landFlight` fires (Task 8).
            .opacity(cascadeActive ? 1 : 0)
        }
        .overlay(alignment: .bottomTrailing) {
            if trailer?.streamURL != nil { trailerCapsules.padding(24) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ShellSpace.window)) } action: { frame in
            shell?.heroFrame = frame
        }
        .onScrollVisibilityChange(threshold: 0.2) { visible in heroVisible = visible }
        .onChange(of: autoplayArmed, initial: true) { _, armed in
            guard armed, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6)) { showVideo = true }
        }
        .clipped()
    }

    /// *Trailer muted* ⇄ *Sound on* (only once the inline loop is actually showing) and
    /// *Watch Trailer* (whenever a stream exists at all).
    private var trailerCapsules: some View {
        HStack(spacing: 10) {
            if showVideo {
                Button {
                    muted.toggle()
                } label: {
                    Label(muted ? "Trailer muted" : "Sound on",
                         systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            if let url = trailer?.streamURL {
                Button {
                    shell?.presentTrailer(url, title: store.item.title)
                } label: {
                    Label("Watch Trailer", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Theme.Palette.textPrimary)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 10) {
            TitleLogo(path: store.logoPath, title: store.item.title)
                .cascadeIn(index: 0, active: cascadeActive)
            metaAndCreditLine
                .cascadeIn(index: 1, active: cascadeActive)
            if let franchise = store.franchise {
                Text(TitlePageText.franchiseLine(franchise))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.gold)
                    .cascadeIn(index: 2, active: cascadeActive)
            }
            if !qualityChips.isEmpty || hasAnyRatingChip {
                chipRow.cascadeIn(index: 3, active: cascadeActive)
            }
            TitleActionsRow(store: store, acquirer: acquirer, trailer: trailer,
                           onFindOtherVersions: onFindOtherVersions)
                .cascadeIn(index: 4, active: cascadeActive)
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

    /// "Dir." + the directors (film) / "Created by" + the creators (show), each a pressable
    /// `TMDBPersonRef` — nil credit → the meta line alone.
    private var creditPeople: (prefix: String, people: [TMDBPersonRef])? {
        let people = store.item.kind == .movie ? store.directors : store.creatorRefs
        guard !people.isEmpty else { return nil }
        return (store.item.kind == .movie ? "Dir." : "Created by", people)
    }

    private var metaAndCreditLine: some View {
        HStack(spacing: 4) {
            Text(metaLine)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.8))
            if let credit = creditPeople {
                Text("\u{00B7} \(credit.prefix)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.8))
                HStack(spacing: 4) {
                    ForEach(Array(credit.people.enumerated()), id: \.offset) { index, person in
                        CreditPersonButton(person: person, trailingComma: index < credit.people.count - 1) { ref in
                            shell?.open(.person(ref))
                        }
                    }
                }
            }
        }
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

/// One credit name in the meta line: bold, underlines on hover, opens the person's page — the
/// twin right-click "Open" duplicates its only click action, as every hover control must.
private struct CreditPersonButton: View {
    let person: TMDBPersonRef
    let trailingComma: Bool
    let onOpen: (TMDBPersonRef) -> Void

    @State private var hovering = false

    var body: some View {
        Button { onOpen(person) } label: {
            Text(person.name + (trailingComma ? "," : ""))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.8))
                .underline(hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu { Button("Open") { onOpen(person) } }
    }
}
