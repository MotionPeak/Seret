import DebridCore
import DebridUI
import SwiftUI

/// Every version of one title — cached and uncached — as a full-screen ranked list.
///
/// Reached from a library title's "Find Other Versions". That used to push the whole Add screen
/// (backdrop hero, trailer, Play, and a *collapsed* "Show all versions" toggle), which is the wrong
/// destination for someone who already owns the title and just wants a different release: it costs
/// a screen of hero plus one more click before the list appears. This screen loads the list
/// immediately and shows nothing else.
///
/// Picking behaves exactly as it does on the Add screen: a version RD already has plays at once,
/// anything else starts a download and reports progress in place.
struct VersionsScreen: View {
    let hit: SearchHit

    @Environment(AppSession.self) private var session
    @State private var flow: AddFlowStore?
    @State private var versions: [CachedStream] = []
    @State private var phase: Phase = .loading
    @State private var picking: String?
    @State private var player: PlayerPresentation?

    private enum Phase { case loading, ready, empty, failed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                downloadStatus
                content
            }
            .padding(.horizontal, 60).padding(.vertical, 50)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CanvasBackground())
        .task {
            guard flow == nil else { return }
            let f = session.makeAddFlow(for: hit)
            flow = f
            await f?.resolve()
            guard let add = f?.add else { phase = .failed; return }
            await add.loadAllVersions()
            versions = add.allVersions
            phase = versions.isEmpty ? .empty : .ready
        }
        .fullScreenCover(item: $player) { presented in
            let engine = VLCKitVideoPlayerEngine(preferences: session.subtitleSettings.preferences)
            if let model = session.makePlayer(for: presented.request, engine: engine) {
                PlayerView(model: model, engine: engine,
                           backdropURL: TMDBClient.imageURL(path: presented.request.item.backdropPath,
                                                            size: "original"))
            } else {
                Text("Unable to start playback.").font(.title2)
            }
        }
    }

    private var title: String {
        flow?.title ?? hit.result.title ?? hit.result.name ?? ""
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).screenTitle()
            Text("Instant versions play right away; the rest download to Real‑Debrid first.")
                .calloutText().foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            HStack(spacing: 16) {
                ProgressView().controlSize(.large).tint(Theme.Palette.gold)
                Text("Finding versions…").font(.title3.weight(.medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.vertical, 40)
        case .failed:
            Label("Couldn't load versions. Check your connection and try again.",
                  systemImage: "exclamationmark.triangle").font(.title3)
        case .empty:
            Label("No other versions found.", systemImage: "square.stack.3d.up.slash").font(.title3)
                .foregroundStyle(Theme.Palette.textSecondary)
        case .ready:
            // Lazy so the (often 30+) rows realise as they scroll in — building every chip and
            // badge up front made the list stutter on the Add screen.
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(versions) { stream in
                    VersionRow(stream: stream, isPicking: picking == stream.infoHash) { pick(stream) }
                }
            }
            .frame(maxWidth: 1400, alignment: .leading)
        }
    }

    /// Live progress for a version picked here that had to be downloaded.
    @ViewBuilder private var downloadStatus: some View {
        if let flow, let status = session.downloadStore?
            .status(forContentKey: DownloadKey.movie(tmdbID: flow.tmdbID)) {
            switch status.phase {
            case .queued:
                ProgressView("Starting download…").font(.title3)
            case .downloading:
                VStack(alignment: .leading, spacing: 10) {
                    Label("Downloading \(Int(status.fraction * 100))% to Real‑Debrid…",
                          systemImage: "arrow.down.circle.fill")
                        .font(.title3).foregroundStyle(.yellow)
                    ProgressView(value: status.fraction).tint(.yellow).frame(maxWidth: 700)
                    Text("It'll appear in your library when it's ready.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            case .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.title3).foregroundStyle(.orange)
            case .ready:
                EmptyView()
            }
        }
    }

    /// Cached → add and play now; otherwise start that version's download. The cache flag lags, so
    /// try the instant add first rather than trusting the badge.
    private func pick(_ stream: CachedStream) {
        guard picking == nil, let flow else { return }
        Task {
            picking = stream.infoHash
            if let request = await flow.instantPlay(stream) {
                session.libraryStore?.retry()      // a new torrent landed in RD
                player = PlayerPresentation(request: request)
            } else {
                await session.downloadStore?.request(contentKey: DownloadKey.movie(tmdbID: flow.tmdbID),
                                                     tmdbID: flow.tmdbID, title: flow.title,
                                                     kind: flow.mediaKind, candidates: [stream],
                                                     posterPath: flow.posterPath)
            }
            picking = nil
        }
    }

    /// Wraps a `PlaybackRequest` so it can drive `.fullScreenCover(item:)`.
    private struct PlayerPresentation: Identifiable {
        let id = UUID()
        let request: PlaybackRequest
    }
}
