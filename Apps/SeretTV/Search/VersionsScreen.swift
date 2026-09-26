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
    /// When set, the list is for ONE episode of a show rather than the whole title. Episodes had
    /// no version picker at all: a movie offered both its owned copies and this search, and an
    /// episode row offered only Mark Watched.
    var episode: (season: Int, number: Int)?

    @Environment(AppSession.self) private var session
    @State private var model: VersionsModel?
    @State private var player: PlayerPresentation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                downloadStatus
                content
            }
            .padding(.horizontal, Theme.Layout.contentMargin).padding(.vertical, 50)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CanvasBackground())
        .task {
            guard model == nil else { return }
            let target: AcquisitionStore.Target = episode.map { .episode(season: $0.season, number: $0.number) } ?? .movie
            // `MediaItem.placeholder(for:)` always carries the hit's TMDB id, so this only returns
            // nil the same way the rest of `AppSession`'s `make…` seams do: no session at all.
            guard let m = session.makeVersionsModel(for: placeholderItem, target: target) else { return }
            model = m
            await m.load()
        }
        .fullScreenCover(item: $player) { presented in
            PlayerHost(request: presented.request, app: session, backdropSize: "original")
        }
    }

    /// `makeVersionsModel` wants a `MediaItem` (it is the title page's seam); this screen only has
    /// a `SearchHit`, so it builds the placeholder item the same way `MediaItem.placeholder(for:)`
    /// does — this screen is reached whether or not the title is owned.
    private var placeholderItem: MediaItem { MediaItem.placeholder(for: hit) }

    private var title: String { model?.title ?? hit.result.title ?? hit.result.name ?? "" }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).screenTitle()
            Text("Instant versions play right away; the rest download to Real‑Debrid first.")
                .calloutText().foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    @ViewBuilder private var content: some View {
        switch model?.phase ?? .loading {
        case .loading:
            HStack(spacing: 16) {
                ProgressView().controlSize(.large).tint(Theme.Palette.gold)
                Text("Finding versions…").font(.seret(.title3, .medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.vertical, 40)
        case .failed:
            Label("Couldn't load versions. Check your connection and try again.",
                  systemImage: "exclamationmark.triangle").font(.seretTitle3)
        case .empty:
            Label("No other versions found.", systemImage: "square.stack.3d.up.slash").font(.seretTitle3)
                .foregroundStyle(Theme.Palette.textSecondary)
        case .ready:
            // Lazy so the (often 30+) rows realise as they scroll in — building every chip and
            // badge up front made the list stutter on the Add screen.
            VersionList(groups: model?.groups ?? [], picking: model?.picking, onPick: pick,
                        hebrew: { model?.hebrew(for: $0) ?? .none })
                .frame(maxWidth: 1400, alignment: .leading)
        }
    }

    /// Live progress for a version picked here that had to be downloaded.
    @ViewBuilder private var downloadStatus: some View {
        if let status = model?.downloadStatus {
            switch status.phase {
            case .queued:
                ProgressView("Starting download…").font(.seretTitle3)
            case .downloading:
                VStack(alignment: .leading, spacing: 10) {
                    Label("Downloading \(Int(status.fraction * 100))% to Real‑Debrid…",
                          systemImage: "arrow.down.circle.fill")
                        .font(.seretTitle3).foregroundStyle(.yellow)
                    ProgressView(value: status.fraction).tint(.yellow).frame(maxWidth: 700)
                    Text("It'll appear in your library when it's ready.")
                        .font(.seretCallout).foregroundStyle(.secondary)
                }
            case .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.seretTitle3).foregroundStyle(.orange)
            case .ready:
                EmptyView()
            }
        }
    }

    /// Cached → add and play now; otherwise start that version's download. The cache flag lags, so
    /// `VersionsModel.pick` tries the instant add first rather than trusting the badge.
    private func pick(_ stream: CachedStream) {
        guard let model else { return }
        Task {
            switch await model.pick(stream) {
            case let .play(request):
                player = PlayerPresentation(request: request)
            default:
                break   // downloadStarted / failed / busy — the status line above already reflects it
            }
        }
    }

    /// Wraps a `PlaybackRequest` so it can drive `.fullScreenCover(item:)`.
    private struct PlayerPresentation: Identifiable {
        let id = UUID()
        let request: PlaybackRequest
    }
}
