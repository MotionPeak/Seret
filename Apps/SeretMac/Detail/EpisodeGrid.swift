import DebridCore
import DebridUI
import SwiftUI

/// The selected season's episodes: TMDB's list merged with whatever is downloaded
/// (`store.episodes(forSeason:)`), reflowing 1/2/3-up with the container's own measured width —
/// not the window's — since it sits inside the page's padded body.
struct EpisodeGrid: View {
    let store: DetailStore
    let acquirer: TitleAcquirer?
    /// Opens the Versions sheet for one episode — owned by `TitlePage` (Decision 7: a sheet's
    /// dependencies are passed explicitly).
    let onFindOtherVersions: (Int, Int) -> Void

    @Environment(ShellModel.self) private var shell: ShellModel?
    @State private var width: CGFloat = 900

    private var rows: [DetailStore.EpisodeRowInfo] { store.episodes(forSeason: store.selectedSeason) }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 22), count: TitlePageLayout.episodeColumns(width: width))
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
            ForEach(rows) { row in
                EpisodeCard(store: store, row: row, acquirer: acquirer,
                           onFindOtherVersions: { onFindOtherVersions(row.season, row.number) },
                           onPlay: { request in shell?.present(request) })
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

private struct EpisodeCard: View {
    let store: DetailStore
    let row: DetailStore.EpisodeRowInfo
    let acquirer: TitleAcquirer?
    let onFindOtherVersions: () -> Void
    let onPlay: (PlaybackRequest) -> Void

    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var key: String { WatchKey.content(forShow: store.item, season: row.season, number: row.number) }
    private var watchState: WatchState? { store.watchState(forKey: key) }
    private var badge: WatchBadge { WatchBadge(watchState) }
    private var active: Bool { hovering }

    /// finding/downloading/owned/not-downloaded — `TitleAcquirer` reads the store's tracked
    /// download and its own busy set; a nil acquirer (harness with none injected) falls back to
    /// the row's own ownership.
    private var availability: TitleAcquirer.EpisodeAvailability {
        acquirer?.availability(of: row) ?? (row.isDownloaded ? .downloaded : .notDownloaded)
    }

    private var isInFlight: Bool {
        switch availability {
        case .finding, .downloading(_): true
        default: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            still
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(row.number)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Palette.gold)
                Text(row.meta?.name ?? "Episode \(row.number)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
            }
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(row.isDownloaded ? Theme.Palette.textSecondary : Theme.Palette.textTertiary)
            }
        }
        .opacity(row.isDownloaded ? 1 : 0.45)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { Task { await tap() } }
        .contextMenu { contextMenuItems }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var caption: String? {
        guard row.isDownloaded, let runtime = row.meta?.runtime else { return nil }
        return "\(runtime)m"
    }

    private var still: some View {
        RemoteImage(url: TMDBClient.imageURL(path: row.meta?.stillPath ?? store.backdropPath, size: "w500"))
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(alignment: .topTrailing) { watchedMark }
            .overlay(alignment: .bottom) { bottomOverlay }
            .overlay { playGlyph }
            .overlay { rim }
            .offset(y: active && !reduceMotion ? -4 : 0)
            .animation(Theme.Motion.quick, value: active)
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

    /// Bottom-anchored per the shell-wide rule: `VStack { Spacer(minLength: 0); content }`. Either
    /// the acquire badge (not downloaded / finding / downloading / failed) or, failing that, the
    /// owned in-progress line — the two never apply at once.
    @ViewBuilder private var bottomOverlay: some View {
        if let text = TitlePageText.episodeBadge(availability) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                acquireBadge(text)
            }
        } else if case let .progress(fraction) = badge {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                GoldProgressBar(fraction: fraction)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
    }

    private func acquireBadge(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                switch availability {
                case .notDownloaded:
                    Image(systemName: "arrow.down.circle")
                case .finding:
                    Image(systemName: "ellipsis").symbolEffect(.pulse, isActive: !reduceMotion)
                default:
                    EmptyView()
                }
                Text(text)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            if case let .downloading(fraction) = availability {
                GoldProgressBar(fraction: fraction).frame(height: 3)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.6), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .padding(8)
    }

    @ViewBuilder private var playGlyph: some View {
        if active {
            ZStack {
                Circle().fill(Color.black.opacity(0.55))
                Image(systemName: row.isDownloaded ? "play.fill" : "arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
        }
    }

    @ViewBuilder private var rim: some View {
        if active {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.gold.opacity(0.75), lineWidth: 1.5)
                .goldGlow(14, opacity: 0.25)
        }
    }

    // MARK: - Actions

    private func play(fromStart: Bool) {
        guard let request = store.episodePlayRequest(for: row, fromStart: fromStart) else { return }
        onPlay(request)
    }

    private func playVersion(_ source: MediaSource) {
        guard let episode = row.ownedEpisode else { return }
        let label = DetailStore.episodeLabel(showTitle: store.item.title, season: row.season, number: row.number)
        onPlay(store.playRequest(source: source, episode: episode, label: label))
    }

    /// A click: play an owned episode, or — for one you don't have yet — find/add/play it
    /// (falling back to a tracked download), the same outcome switch the hero's acquire button
    /// uses. Ignored while already finding or downloading.
    private func tap() async {
        guard !isInFlight else { return }
        if row.isDownloaded {
            play(fromStart: false)
            return
        }
        guard let acquirer else { return }
        switch await acquirer.play(.episode(season: row.season, number: row.number)) {
        case .play(let request):
            onPlay(request)
        case .downloadStarted:
            shell?.showToast("Downloading S\(row.season)\u{00B7}E\(row.number) to Real\u{2011}Debrid")
        case .failed(let message) where !message.isEmpty:
            shell?.showToast(message, isFailure: true)
        case .noneInstant, .failed:
            break   // a busy target tapped again, or a film-shaped outcome that can't occur here
        }
    }

    // MARK: - Context menu

    private var menuGroups: [[EpisodeMenuItem]] {
        let inProgress = watchState.map { !$0.finished && $0.positionSeconds > 0 } ?? false
        return EpisodeMenu.make(row: row, watched: watchState?.finished ?? false,
                                inProgress: inProgress, availability: availability)
    }

    @ViewBuilder private var contextMenuItems: some View {
        ForEach(Array(menuGroups.enumerated()), id: \.offset) { index, group in
            if index > 0 { Divider() }
            groupContent(group)
        }
    }

    /// A group that is entirely `.version` entries is "Versions ▸", the episode's own copies —
    /// every other group renders as flat buttons.
    @ViewBuilder private func groupContent(_ group: [EpisodeMenuItem]) -> some View {
        if group.allSatisfy({ if case .version = $0 { true } else { false } }), !group.isEmpty {
            Menu("Versions") {
                ForEach(group, id: \.self) { item in
                    if case let .version(source, isPlaying) = item {
                        Button {
                            playVersion(source)
                        } label: {
                            if isPlaying {
                                Label(source.versionSummary, systemImage: "checkmark")
                            } else {
                                Text(source.versionSummary)
                            }
                        }
                    }
                }
            }
        } else {
            ForEach(group, id: \.self) { item in
                menuButton(item)
            }
        }
    }

    @ViewBuilder private func menuButton(_ item: EpisodeMenuItem) -> some View {
        switch item {
        case .play:
            Button("Play") { play(fromStart: false) }
        case .playFromBeginning:
            Button("Play from Beginning") { play(fromStart: true) }
        case .downloadAndPlay:
            Button("Download and Play") { Task { await tap() } }
        case .markWatched(let newValue):
            Button(newValue ? "Mark as Watched" : "Mark as Unwatched") {
                Task { await store.setWatched(newValue, contentKey: key, source: row.ownedSource) }
            }
        case .findOtherVersions:
            Button("Find Other Versions\u{2026}", action: onFindOtherVersions)
        case .cancelDownload:
            Button("Cancel Download") {
                Task { await acquirer?.cancelDownload(.episode(season: row.season, number: row.number)) }
            }
        case .version:
            EmptyView()   // rendered by `groupContent`'s "Versions" submenu instead
        }
    }

    private var accessibilityLabel: String {
        let name = row.meta?.name ?? "Episode \(row.number)"
        if let badgeText = TitlePageText.episodeBadge(availability) {
            return "Episode \(row.number), \(name), \(badgeText)"
        }
        switch badge {
        case .watched: return "Episode \(row.number), \(name), watched"
        case .progress(let fraction): return "Episode \(row.number), \(name), \(Int((fraction * 100).rounded())) percent watched"
        case .none: return "Episode \(row.number), \(name)"
        }
    }
}
