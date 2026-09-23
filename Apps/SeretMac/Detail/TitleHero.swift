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

private struct QualityChip: View {
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

/// The title page's hero: full-bleed backdrop fading into the canvas, title, meta line, quality
/// chips (films only) and the primary action row (Play/Resume + Start Over, from
/// `DetailStore.primaryPlay()`).
struct TitleHero: View {
    let store: DetailStore

    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(\.pageLeadingInset) private var pageLeadingInset
    @State private var width: CGFloat = 1200

    private var height: CGFloat { TitlePageLayout.heroHeight(width: width) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            copy
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background {
            HeroBackdrop(url: TMDBClient.imageURL(path: store.backdropPath ?? store.item.posterPath, size: "w1280"))
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .clipped()
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.item.title)
                .font(.system(size: 38, weight: .heavy))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
            Text(metaLine)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.8))
            if !qualityChips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(qualityChips, id: \.self) { QualityChip(text: $0) }
                }
            }
            actions
        }
        .padding(.leading, pageLeadingInset + 8)
        .padding(.bottom, 28)
        .frame(maxWidth: 640, alignment: .leading)
    }

    private var metaLine: String {
        TitlePageText.metaLine(
            year: store.item.year,
            runtimeMinutes: store.item.kind == .movie ? store.runtime : nil,
            genres: store.genres,
            seasonCount: store.item.kind == .show ? store.numberOfSeasons : nil)
    }

    /// Films only — a show's chips would just repeat the meta line's season count.
    private var qualityChips: [String] {
        guard store.item.kind == .movie, let parsed = store.bestSource?.parsed else { return [] }
        return [parsed.resolution, parsed.source, parsed.videoCodec, parsed.audioCodec].compactMap { $0 }
    }

    @ViewBuilder private var actions: some View {
        if let pp = store.primaryPlay() {
            HStack(spacing: 10) {
                Button {
                    shell?.present(pp.request)
                } label: {
                    Label(primaryTitle(pp), systemImage: "play.fill")
                }
                .buttonStyle(GoldButtonStyle())
                if pp.resumeAt != nil {
                    Button {
                        shell?.present(pp.startOver)
                    } label: {
                        Label("Start Over", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
            .padding(.top, 4)
        } else {
            Button { } label: { Text(TitlePageText.unavailableTitle(isOwned: isOwned)) }
                .buttonStyle(GoldButtonStyle())
                .disabled(true)
                .padding(.top, 4)
        }
    }

    /// Owned = the library has something under this item — a source (a film) or a season (a show).
    /// A title that never went through `LibraryStore` at all (a placeholder for a TMDB hit,
    /// Decision 2) has neither, so its disabled button reads "Not in Your Library" rather than
    /// "Not Available".
    private var isOwned: Bool { !(store.item.sources.isEmpty && store.item.seasons.isEmpty) }

    private func primaryTitle(_ pp: DetailStore.PrimaryPlay) -> String {
        TitlePageText.primaryTitle(episode: pp.episode.map { ($0.season, $0.number) }, resumeAt: pp.resumeAt)
    }
}
