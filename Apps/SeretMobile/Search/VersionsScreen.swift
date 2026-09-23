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
/// reports progress in place. Cache flags lag, so `VersionsModel.pick` tries the instant add
/// rather than trusting the badge.
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
    @State private var model: VersionsModel?

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
            guard model == nil else { return }
            let target: AcquisitionStore.Target = episode.map { .episode(season: $0.season, number: $0.number) } ?? .movie
            // `MediaItem.placeholder(for:)` always carries the hit's TMDB id, so this only returns
            // nil the same way the rest of `AppSession`'s `make…` seams do: no session at all.
            guard let m = session.makeVersionsModel(for: MediaItem.placeholder(for: hit), target: target) else { return }
            model = m
            await m.load()
        }
    }

    private var title: String { model?.title ?? hit.result.displayTitle }

    @ViewBuilder private var content: some View {
        switch model?.phase ?? .loading {
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
                // Big releases first under their own header. Ranking them last for being oversized
                // buried them at the bottom of thirty-odd rows; the ranking is unchanged, they are
                // just no longer out of sight.
                let larger = model?.larger ?? []
                let rest = model?.rest ?? []
                if !larger.isEmpty {
                    sectionHeader("Larger files",
                                  "Highest bitrate. Slower to start and heavier to skip.")
                    ForEach(larger) { row($0) }
                }
                if !rest.isEmpty {
                    if !larger.isEmpty {
                        sectionHeader("Recommended", "Sized to play smoothly on this hardware.")
                    }
                    ForEach(rest) { row($0) }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.Typo.headline())
            Text(caption).font(Theme.Typo.caption())
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.top, Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    if model?.picking == stream.infoHash {
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
        if let status = model?.downloadStatus {
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
        guard let model, model.picking == nil else { return }
        Task {
            switch await model.pick(stream) {
            case let .play(request):
                dismiss()
                onPlay(request)
            default:
                break   // downloadStarted / failed / busy — the status line above already reflects it
            }
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
