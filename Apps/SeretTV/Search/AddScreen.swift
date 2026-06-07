import DebridCore
import DebridUI
import SwiftUI

/// The Add screen for a picked search result. Resolves TMDB details via `AddFlowStore`, then
/// offers **Get best · Add & Play · More versions** for a movie, or a season/episode picker
/// (then the same actions) for a show. Add & Play presents the player full-screen.
struct AddScreen: View {
    let hit: SearchHit

    @Environment(AppSession.self) private var session
    @State private var flow: AddFlowStore?
    @State private var player: PlayerPresentation?

    var body: some View {
        Group {
            if let flow {
                switch flow.phase {
                case .resolving:
                    ProgressView("Loading…").font(.title3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .resolveFailed(let msg):
                    centered(msg, systemImage: "exclamationmark.triangle")
                case .movie:
                    MovieAdd(flow: flow, onPlay: { player = PlayerPresentation(request: $0) })
                case .show:
                    ShowAdd(flow: flow, onPlay: { player = PlayerPresentation(request: $0) })
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(BackdropBackground(path: flow?.backdropPath, posterFallback: flow?.posterPath))
        .task {
            guard flow == nil else { return }
            let f = session.makeAddFlow(for: hit)
            flow = f
            await f?.resolve()
        }
        .fullScreenCover(item: $player) { presented in
            let engine = VLCKitVideoPlayerEngine(preferences: session.subtitleSettings.preferences)
            if let model = session.makePlayer(for: presented.request, engine: engine) {
                PlayerView(model: model, engine: engine,
                           backdropURL: TMDBClient.imageURL(path: presented.request.item.backdropPath, size: "original"))
            } else {
                Text("Unable to start playback.").font(.title2)
            }
        }
        // A successful add lands a new torrent in RD → refresh the library so it appears
        // without restarting the app.
        .onChange(of: flow?.add?.state) { _, newState in
            if case .added = newState { session.libraryStore?.retry() }
        }
    }

    /// Wraps a `PlaybackRequest` so it can drive `.fullScreenCover(item:)`.
    private struct PlayerPresentation: Identifiable {
        let id = UUID()
        let request: PlaybackRequest
    }

    private func centered(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage).font(.system(size: 64)).foregroundStyle(.secondary)
            Text(text).font(.title3).multilineTextAlignment(.center).frame(maxWidth: 700)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Movie

private struct MovieAdd: View {
    let flow: AddFlowStore
    let onPlay: (PlaybackRequest) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 560)
                Text(flow.title).font(.system(size: 48, weight: .bold))
                if let year = flow.year { Text(String(year)).font(.body).foregroundStyle(.secondary) }
                if let overview = flow.overview {
                    Text(overview).font(.body).frame(maxWidth: 1100, alignment: .leading).lineLimit(3)
                }
                TrailerButton(tmdbID: flow.tmdbID, kind: flow.mediaKind).font(.title3)
                if let add = flow.add {
                    AddActions(flow: flow, add: add, onPlay: onPlay)
                }
            }
            .padding(60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Show

private struct ShowAdd: View {
    let flow: AddFlowStore
    let onPlay: (PlaybackRequest) -> Void
    @Environment(AppSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 480)
                Text(flow.title).font(.system(size: 48, weight: .bold))
                if let overview = flow.overview {
                    Text(overview).font(.body).frame(maxWidth: 1100, alignment: .leading).lineLimit(2)
                }
                TrailerButton(tmdbID: flow.tmdbID, kind: flow.mediaKind).font(.title3)
                seasonPicker
                SeasonDownloadButton(store: flow.seasonAdd) { session.libraryStore?.retry() }
                episodeList
                if flow.selectedEpisode != nil, let add = flow.add {
                    AddActions(flow: flow, add: add, onPlay: onPlay)
                }
            }
            .padding(60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var seasonPicker: some View {
        if flow.seasons.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(flow.seasons, id: \.self) { s in
                        Button("Season \(s)") { Task { await flow.selectSeason(s) } }
                            .font(.headline)
                            .buttonStyle(.bordered)
                            .tint(s == flow.selectedSeason ? .yellow : .gray)
                    }
                }
            }
        }
    }

    private var episodeList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(flow.episodes) { ep in
                Button { Task { await flow.selectEpisode(ep.episodeNumber) } } label: {
                    HStack(spacing: 16) {
                        Text("\(ep.episodeNumber)").font(.title3.bold()).frame(width: 44)
                        Text(ep.name ?? "Episode \(ep.episodeNumber)").font(.body)
                        Spacer()
                        if ep.episodeNumber == flow.selectedEpisode {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: 1100, alignment: .leading)
    }
}

// MARK: - Shared add actions

/// Get best · Add & Play · More versions + add-progress, driven by the inner `AddStore`.
private struct AddActions: View {
    let flow: AddFlowStore
    let add: AddStore
    let onPlay: (PlaybackRequest) -> Void
    @Environment(AppSession.self) private var session
    @State private var showAll = false
    @State private var loadingAll = false
    /// Queued add awaiting a replace-existing confirmation (set when the title is owned).
    @State private var pendingReplace: PendingAdd?

    private enum PendingAdd: Identifiable {
        case best, stream(CachedStream)
        var id: String { if case .stream(let s) = self { return s.infoHash } else { return "best" } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch add.state {
            case .loadingStreams:
                ProgressView("Finding cached versions…").font(.title3)
            case .noStreams:
                DownloadSection(flow: flow)
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle").font(.title3)
                Button("Try Again") { Task { await add.loadStreams() } }.font(.title3)
            default:
                actions
            }
            if showAllAvailable { showAllVersions }
        }
        .alert("Replace existing version?",
               isPresented: Binding(get: { pendingReplace != nil },
                                    set: { if !$0 { pendingReplace = nil } }),
               presenting: pendingReplace) { pending in
            Button("Replace", role: .destructive) {
                Task {
                    if let owned = ownedItem() { await session.libraryStore?.remove(owned) }
                    switch pending {
                    case .best:           performPlayBest()
                    case .stream(let s):  performPlay(s)
                    }
                    pendingReplace = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("\u{201C}\(flow.title)\u{201D} is already in your library. Replacing removes the existing version first.")
        }
    }

    @ViewBuilder private var actions: some View {
        if let best = add.best {
            HStack(spacing: 16) {
                QualityChips(parsed: best.parsed)
                LanguageBadges(codes: best.languages)
            }
            if add.isFallback {
                Label("Audio may not be in the original language.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button { playBest() } label: { Label("Play", systemImage: "play.fill") }
                .font(.title3)
            addStatus
        }
    }

    /// The expander shows whenever the title resolved (a cached best exists, or none is cached).
    private var showAllAvailable: Bool {
        if case .noStreams = add.state { return true }
        return add.best != nil
    }

    @ViewBuilder private var showAllVersions: some View {
        Button {
            showAll.toggle()
            if showAll && add.allVersions.isEmpty {
                Task { loadingAll = true; await add.loadAllVersions(); loadingAll = false }
            }
        } label: {
            Label(showAll ? "Hide versions" : "Show all versions", systemImage: "square.stack.3d.up")
        }
        .font(.title3)
        if showAll {
            if loadingAll {
                ProgressView().padding(.vertical, 8)
            } else if add.allVersions.isEmpty {
                Text("No other versions found.").font(.callout).foregroundStyle(.secondary)
            } else {
                allVersionsList
            }
        }
    }

    private var allVersionsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(add.allVersions) { stream in
                Button { pick(stream) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 16) {
                            CacheBadge(isCached: stream.isCached)
                            if let year = stream.parsed.year {
                                Text(String(year)).font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(.white.opacity(0.12), in: Capsule())
                            }
                            QualityChips(parsed: stream.parsed)
                            LanguageBadges(codes: stream.languages)
                            Spacer()
                            if let size = stream.sizeBytes {
                                Text(Self.sizeGB(size)).font(.callout).foregroundStyle(.secondary)
                            }
                            Image(systemName: stream.isCached ? "play.circle" : "arrow.down.circle")
                        }
                        Text(stream.rawTitle).font(.callout).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: 1100, alignment: .leading)
    }

    /// Cached version → add + play now; uncached → start that version's download.
    private func pick(_ stream: CachedStream) {
        if stream.isCached {
            play(stream)
        } else {
            Task {
                await session.downloadStore?.request(tmdbID: flow.tmdbID, title: flow.title,
                                                     kind: flow.mediaKind, candidates: [stream],
                                                     posterPath: flow.posterPath)
            }
        }
    }

    static func sizeGB(_ bytes: Int) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }

    @ViewBuilder private var addStatus: some View {
        switch add.state {
        case .adding:
            ProgressView("Adding to Real‑Debrid…").font(.title3)
        case .added:
            Label("Added — find it in your library.", systemImage: "checkmark.circle.fill")
                .font(.title3).foregroundStyle(.green)
        case .addFailed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle").font(.title3).foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    /// Add the best instantly-available version (auto-falling-back) and play it.
    private func playBest() {
        if ownedItem() != nil { pendingReplace = .best } else { performPlayBest() }
    }
    /// Add a specific chosen version and play it.
    private func play(_ stream: CachedStream) {
        if ownedItem() != nil { pendingReplace = .stream(stream) } else { performPlay(stream) }
    }

    private func performPlayBest() {
        Task {
            await flow.addBest()
            if case let .added(info) = add.state, let req = flow.playbackRequest(from: info) { onPlay(req) }
        }
    }
    private func performPlay(_ stream: CachedStream) {
        Task {
            await flow.add(stream: stream)
            if case let .added(info) = add.state, let req = flow.playbackRequest(from: info) { onPlay(req) }
        }
    }

    private func ownedItem() -> MediaItem? {
        guard flow.mediaKind == .movie else { return nil }
        return session.libraryStore?.ownedItem(tmdbID: flow.tmdbID)
    }
}

// MARK: - Request Download (uncached fallback)

/// Shown when a title has no instantly-cached version. Offers "Request Download" (best uncached
/// release → RD download), then live progress from the app-wide `DownloadStore`. The title flips
/// into the library when RD finishes.
private struct DownloadSection: View {
    let flow: AddFlowStore
    @Environment(AppSession.self) private var session
    @State private var requesting = false

    var body: some View {
        let status = session.downloadStore?.status(forTMDB: flow.tmdbID)
        VStack(alignment: .leading, spacing: 16) {
            if requesting && status == nil {
                ProgressView("Starting download…").font(.title3)
            } else if case .queued = status?.phase {
                ProgressView("Starting download…").font(.title3)
            } else if case .downloading = status?.phase {
                let pct = Int((status?.fraction ?? 0) * 100)
                Label("Downloading \(pct)% to Real‑Debrid…", systemImage: "arrow.down.circle.fill")
                    .font(.title3).foregroundStyle(.yellow)
                ProgressView(value: status?.fraction ?? 0).tint(.yellow).frame(maxWidth: 700)
                Text("It'll appear in your library when it's ready.").font(.callout).foregroundStyle(.secondary)
                Button(role: .destructive) {
                    Task { await session.downloadStore?.cancel(tmdbID: flow.tmdbID) }
                } label: { Label("Cancel download", systemImage: "xmark.circle") }
                    .font(.title3)
            } else if case .failed(let reason) = status?.phase {
                Label(reason, systemImage: "exclamationmark.triangle").font(.title3).foregroundStyle(.orange)
                requestButton(title: "Try Another Version")
            } else {
                Label("No cached version found.", systemImage: "magnifyingglass")
                    .font(.title3).foregroundStyle(.secondary)
                Text("It isn't in Real‑Debrid's cache yet. Start a download and it'll appear in your library when it's ready.")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: 900, alignment: .leading)
                requestButton(title: "Request Download")
            }
        }
    }

    private func requestButton(title: String) -> some View {
        Button {
            Task {
                requesting = true
                let candidates = await flow.uncachedCandidates()
                await session.downloadStore?.request(tmdbID: flow.tmdbID, title: flow.title,
                                                     kind: flow.mediaKind, candidates: candidates,
                                                     posterPath: flow.posterPath)
                requesting = false
            }
        } label: { Label(title, systemImage: "arrow.down.circle") }
            .font(.title3)
            .disabled(requesting)
    }
}

/// ⚡ Instant (already on RD) vs ⬇️ Download (will fetch) — from Comet's cache marker.
private struct CacheBadge: View {
    let isCached: Bool
    var body: some View {
        Label(isCached ? "Instant" : "Download", systemImage: isCached ? "bolt.fill" : "arrow.down.circle")
            .font(.caption.weight(.bold))
            .foregroundStyle(isCached ? Color.green : .yellow)
            .padding(.vertical, 4).padding(.horizontal, 10)
            .background((isCached ? Color.green : .yellow).opacity(0.15), in: Capsule())
    }
}

/// Uppercased ISO-639-1 language chips (e.g. EN · FR).
private struct LanguageBadges: View {
    let codes: [String]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(codes.prefix(4), id: \.self) { code in
                Text(code.uppercased())
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
            }
        }
    }
}
