import DebridCore
import DebridUI
import SwiftUI

/// Every version of one title — cached and uncached — as a full-screen ranked list.
///
/// Reached from a title page's "Versions", whether or not you own it. It used to live inside the
/// Add screen behind a "Show all versions" toggle, which meant a screen of hero plus a tap before
/// the list appeared. This loads the list immediately and shows nothing else.
///
/// Picking: a version Real-Debrid already has plays at once; anything else starts a download and
/// reports progress in place. Cache flags lag, so it tries the instant add rather than trusting the
/// badge.
struct VersionsScreen: View {
    let hit: SearchHit
    /// When set, the list is for ONE episode of a show rather than the whole title. Episodes had
    /// no version picker at all: a movie offered both its owned copies and this search, and an
    /// episode row offered only Mark Watched.
    var episode: (season: Int, number: Int)?
    /// Play a version that turned out to be instantly available. The parent presents the player —
    /// this screen is itself a cover, and a cover cannot stack another from the same shell.
    let onPlay: (PlaybackRequest) -> Void

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var flow: AddFlowStore?
    @State private var versions: [CachedStream] = []
    @State private var phase: Phase = .loading
    @State private var picking: String?

    private enum Phase { case loading, ready, empty, failed }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Text("Instant versions play right away; the rest download to Real\u{2011}Debrid first.")
                        .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
                    downloadStatus
                    content
                }
                .padding(Theme.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(CanvasBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").font(.headline) }
                        .tint(Theme.Palette.gold)
                }
            }
        }
        .task {
            guard flow == nil else { return }
            let f = session.makeAddFlow(for: hit)
            flow = f
            await f?.resolve()
            // An episode needs its own target: Comet/Torrentio queries are per `series(s,e)`, so
            // without this the list would be the show's, not this episode's.
            if let episode {
                await f?.selectSeason(episode.season)
                await f?.selectEpisode(episode.number)
            }
            guard let add = f?.add else { phase = .failed; return }
            await add.loadAllVersions()
            versions = add.allVersions
            phase = versions.isEmpty ? .empty : .ready
        }
    }

    private var title: String {
        let base = flow?.title ?? hit.result.displayTitle
        guard let episode else { return base }
        return "\(base) — S\(episode.season)·E\(episode.number)"
    }

    /// What a download started here is filed under. Was hardcoded to the movie key, which would
    /// have reported an episode's progress against the whole show.
    private func downloadKey(_ flow: AddFlowStore) -> String {
        guard let episode else { return DownloadKey.movie(tmdbID: flow.tmdbID) }
        return DownloadKey.episode(showTmdbID: flow.tmdbID,
                                   season: episode.season, number: episode.number)
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            HStack(spacing: Theme.Space.sm) {
                ProgressView().tint(Theme.Palette.gold)
                Text("Finding versions…").font(Theme.Typo.body())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.vertical, Theme.Space.lg)
        case .failed:
            Label("Couldn't load versions. Check your connection and try again.",
                  systemImage: "exclamationmark.triangle")
                .font(Theme.Typo.body()).foregroundStyle(.orange)
        case .empty:
            Label("No other versions found.", systemImage: "square.stack.3d.up.slash")
                .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
        case .ready:
            // Lazy so the (often 30+) rows realise as they scroll in — building every chip and
            // badge up front made the list stutter on the old Add screen.
            LazyVStack(alignment: .leading, spacing: Theme.Space.sm) {
                ForEach(versions) { row($0) }
            }
        }
    }

    private func row(_ stream: CachedStream) -> some View {
        Button { pick(stream) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Theme.Space.sm) {
                    CacheBadge(isCached: stream.isCached)
                    if let year = stream.parsed.year { QualityChip(text: String(year)) }
                    QualityChipRow(parsed: stream.parsed)
                    ForEach(stream.languages.prefix(2), id: \.self) {
                        QualityChip(text: $0.uppercased())
                    }
                    Spacer()
                    if let size = stream.sizeBytes {
                        Text(Self.sizeGB(size)).font(Theme.Typo.caption())
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    if picking == stream.infoHash {
                        ProgressView().tint(Theme.Palette.gold)
                    } else {
                        Image(systemName: stream.isCached ? "play.circle.fill" : "arrow.down.circle.fill")
                            .foregroundStyle(Theme.Palette.gold)
                    }
                }
                // The full release name — read the source (CAM/TELESYNC), year, group to confirm
                // it's the right film/version.
                Text(stream.rawTitle)
                    .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(Theme.Space.md)
            .background(Theme.Palette.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Live progress for a version picked here that had to be downloaded.
    @ViewBuilder private var downloadStatus: some View {
        if let flow, let status = session.downloadStore?
            .status(forContentKey: downloadKey(flow)) {
            switch status.phase {
            case .queued:
                ProgressView("Starting download…").tint(Theme.Palette.gold)
            case .downloading:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Downloading \(Int(status.fraction * 100))% to Real\u{2011}Debrid…",
                          systemImage: "arrow.down.circle.fill")
                        .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.gold)
                    ProgressView(value: status.fraction).tint(Theme.Palette.gold)
                    Text("It'll appear in your library when it's ready.")
                        .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
                }
            case .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(Theme.Typo.body()).foregroundStyle(.orange)
            case .ready:
                EmptyView()
            }
        }
    }

    private func pick(_ stream: CachedStream) {
        guard picking == nil, let flow else { return }
        Task {
            picking = stream.infoHash
            if let request = await flow.instantPlay(stream) {
                session.libraryStore?.retry()      // a new torrent landed in RD
                dismiss()
                onPlay(request)
            } else {
                await session.downloadStore?.request(
                    contentKey: downloadKey(flow),
                    tmdbID: flow.tmdbID, title: flow.title, kind: flow.mediaKind,
                    candidates: [stream], posterPath: flow.posterPath)
            }
            picking = nil
        }
    }

    static func sizeGB(_ bytes: Int) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}

/// ⚡ Instant (already on RD) vs ⬇️ Download (will fetch) — from Comet's cache marker.
struct CacheBadge: View {
    let isCached: Bool
    var body: some View {
        Label(isCached ? "Instant" : "Download",
              systemImage: isCached ? "bolt.fill" : "arrow.down.circle")
            .font(.system(size: 10, weight: .bold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isCached ? Color.green : Theme.Palette.gold)
            .padding(.vertical, 3).padding(.horizontal, 7)
            .background((isCached ? Color.green : Theme.Palette.gold).opacity(0.15), in: Capsule())
    }
}
