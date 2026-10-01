import DebridCore
import DebridUI
import SwiftUI

/// One episode card in the side-scrolling row: a 16:9 still (the focusable `.card`). A downloaded
/// episode plays on select (with a Mark Watched context menu); a not-downloaded one shows a
/// download glyph + "Not downloaded" and downloads-then-plays on select.
struct EpisodeRow: View {
    let store: DetailStore
    let row: DetailStore.EpisodeRowInfo
    var isDownloading: Bool = false
    var onDownload: (DetailStore.EpisodeRowInfo) -> Void = { _ in }
    @Environment(\.openBrowseDestination) private var openDestination

    private let width: CGFloat = 320

    /// Keyed by season/episode NUMBER, not by the file you own: an episode you have watched but
    /// never downloaded still has watch state, and this row still has to show it.
    private var contentKey: String {
        WatchKey.content(forShow: store.item, season: row.season, number: row.number)
    }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }
    private var isWatched: Bool { watch?.finished == true }

    var body: some View {
        // ONE control whose action varies — never a link-or-button branch. The branch swapped the
        // focused card for a different view the moment the episode became yours (a page now adopts
        // the library's item while it is open: an episode bought from this card, a season pack
        // landing), and tvOS dropped focus with it. Same shape as `DownloadingRailCard`.
        // Not `.disabled(isDownloading)`: a disabled card cannot keep focus either; the page ignores
        // a second press while one is under way (`DetailView.playEpisode`).
        Button {
            if let ep = row.ownedEpisode, let src = row.ownedSource {
                openDestination(.play(store.playRequest(source: src, episode: ep, label: label)))
            } else {
                onDownload(row)
            }
        } label: { lockup }
        .buttonStyle(.borderless)
        .contextMenu {
            Button(isWatched ? "Mark Unwatched" : "Mark Watched") {
                Task { await store.setWatched(!isWatched, contentKey: contentKey, source: row.ownedSource) }
            }
            if let ep = row.ownedEpisode { ownedVersionsMenu(ep) }
            findOtherVersionsLink
        }
        .frame(width: width, alignment: .leading)
    }

    /// The still AND its words, as one focus target — the tvOS "lockup". Only the still was
    /// focusable before, so the focus engine scrolled the page just far enough to show the still,
    /// and the title and synopsis under it ran off the bottom of the screen. The highlight stays on
    /// the still alone (`hoverEffect`), the way the Apple TV app draws an episode.
    private var lockup: some View {
        VStack(alignment: .leading, spacing: 8) {
            still.hoverEffect(.highlight)
            EpisodeCardText(title: title, meta: subtitle, synopsis: row.meta?.overview,
                            isWatched: isWatched)
        }
        .frame(width: width, alignment: .leading)
    }

    /// The other copies of this episode you already own — the episode equivalent of a movie's
    /// Versions section. Only rendered when there IS a choice, so the common single-copy episode
    /// keeps a two-item menu.
    @ViewBuilder private func ownedVersionsMenu(_ ep: Episode) -> some View {
        if row.hasAlternateVersions {
            Menu("Versions") {
                ForEach(row.ownedVersions, id: \.self) { src in
                    NavigationLink(value: store.playRequest(source: src, episode: ep, label: label)) {
                        Text(versionLabel(src))
                    }
                }
            }
        }
    }

    /// Search every release of this episode — cached and not — exactly as a movie can.
    @ViewBuilder private var findOtherVersionsLink: some View {
        if let hit = showHit {
            NavigationLink(value: BrowseDestination.episodeVersions(hit, season: row.season,
                                                                    number: row.number)) {
                Label("Find Other Versions", systemImage: "square.stack.3d.up")
            }
        }
    }

    /// The show, as the Add pipeline wants it. Needs a TMDB id to search.
    private var showHit: SearchHit? {
        guard let tmdb = store.item.tmdbID else { return nil }
        return SearchHit(result: TMDBSearchResult(
            id: tmdb, title: nil, name: store.item.title, releaseDate: nil, firstAirDate: nil,
            posterPath: store.item.posterPath, overview: nil, voteAverage: nil), kind: .show)
    }

    /// Resolution · source · size — enough to tell two copies apart in a menu, where the movie
    /// list's `QualityChips` cannot render.
    private func versionLabel(_ src: MediaSource) -> String {
        var parts = [src.parsed.resolution, src.parsed.source].compactMap { $0 }
        if let bytes = src.sizeBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        if parts.isEmpty { parts = ["Version"] }
        return parts.joined(separator: " · ")
    }

    private var label: String { "\(store.item.title) — S\(row.season)·E\(row.number)" }
    private var title: String { "\(row.number) · \(row.meta?.name ?? "Episode \(row.number)")" }
    private var subtitle: String {
        if isDownloading { return "Downloading\u{2026}" }
        if !row.isDownloaded { return "Not downloaded" }
        return [row.meta?.runtime.map { "\($0) min" }, row.ownedSource?.parsed.resolution]
            .compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private var still: some View {
        Group {
            if let url = TMDBClient.imageURL(path: row.meta?.stillPath, size: "w300") {
                RemoteImage(url: url)
            } else {
                Theme.Palette.surface2.overlay {
                    Image(systemName: "tv").font(.system(size: 36)).foregroundStyle(.white.opacity(0.2))
                }
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous))
        .opacity(row.isDownloaded ? 1 : 0.5)          // dim not-downloaded episodes
        .overlay {
            if !row.isDownloaded {
                Image(systemName: isDownloading ? "arrow.down.circle" : "arrow.down.circle.fill")
                    .font(.system(size: 44)).foregroundStyle(.white.opacity(0.9))
                    .symbolEffect(.pulse, isActive: isDownloading)
            }
        }
        .overlay(alignment: .bottom) { progressBar }
    }

    @ViewBuilder private var progressBar: some View {
        if isWatched {
            bar(fraction: 1, color: Theme.Palette.gold)
        } else if let w = watch, w.durationSeconds > 0, w.positionSeconds > 0 {
            bar(fraction: w.positionSeconds / w.durationSeconds, color: Theme.Palette.gold)
        }
    }

    private func bar(fraction: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.4)
                Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 5)
    }
}

/// A stable-height skeleton card shown while a season's episodes load. It matches `EpisodeRow`'s
/// size so the side-scrolling row never collapses to nothing — which is what snapped the whole
/// Detail page's scroll back to the top when you switched seasons or scrolled into the episodes.
struct EpisodePlaceholderCard: View {
    private let width: CGFloat = 320
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous)
                .fill(Theme.Palette.surface2)
                .frame(width: width, height: width * 9 / 16)
            // The real card's own text block, redacted: the same fonts and the same reserved lines,
            // so the row is exactly as tall loading as loaded and nothing below it moves when the
            // season arrives.
            EpisodeCardText(title: "Episode title", meta: "00 min", synopsis: "Synopsis")
                .redacted(reason: .placeholder)
        }
        .frame(width: width, alignment: .leading)
    }
}

/// What an episode row says when there are no episodes to show — in the row's own height, so the
/// page does not jump when it replaces the skeletons, and with a way to try again when it failed.
struct EpisodeNoticeCard: View {
    let message: String
    var retry: (() -> Void)?
    /// The retry is running: the same button, saying so — it must not be swapped for skeletons.
    var retrying = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            EpisodePlaceholderCard().hidden()          // the height of a row of cards
            VStack(alignment: .leading, spacing: 20) {
                Label(message, systemImage: retry == nil ? "tv" : "exclamationmark.triangle")
                    .font(.seret(Theme.Typography.calloutSize, .medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
                if let retry {
                    Button {
                        if !retrying { retry() }
                    } label: {
                        Label(retrying ? "Trying\u{2026}" : "Try Again",
                              systemImage: retrying ? "hourglass" : "arrow.clockwise")
                    }
                    .buttonStyle(SeretActionButtonStyle())
                }
            }
            .padding(.top, 24)
            .frame(width: 720, alignment: .leading)
        }
    }
}

/// The words under an episode's still: its title, its runtime/status, and what happens in it.
///
/// The title used to be ONE line — "3 · Denial, Anger, Acc…" — and the synopsis was not shown
/// anywhere on the page, so choosing an episode meant choosing it by number. Every line here
/// RESERVES its space, so a card with a short title or no synopsis is as tall as its neighbours:
/// the synopses line up across the row, and the skeleton matches it exactly.
struct EpisodeCardText: View {
    let title: String
    let meta: String
    let synopsis: String?
    var isWatched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).cardTitle().lineLimit(2, reservesSpace: true)
                if isWatched {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.gold)
                }
            }
            Text(meta).font(.seret(Theme.Typography.captionSize, .medium))
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1, reservesSpace: true)
            Text(synopsis ?? "").font(.seret(Theme.Typography.captionSize, .regular))
                .foregroundStyle(Theme.Palette.textSecondary.opacity(0.9))
                .lineLimit(3, reservesSpace: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
