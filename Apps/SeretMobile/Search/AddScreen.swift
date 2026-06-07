import DebridCore
import DebridUI
import SwiftUI

/// The Add screen for a picked search result. Resolves TMDB details via `AddFlowStore`, then
/// offers **Get best · Add & Play · More versions** for a movie, or a season/episode picker
/// (then the same actions) for a show. Presented full-screen by `RootView` (rotation-safe);
/// presents the player itself, mirroring `DetailScreen`.
struct AddScreen: View {
    let hit: SearchHit

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var flow: AddFlowStore?
    @State private var playback: PlaybackPresentation?

    var body: some View {
        NavigationStack {
            // Backdrop as the ScrollView's `.background` (mirrors DetailScreen) — a parent ZStack
            // here swallowed the top inset, pinning content under the toolbar.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DetailBackdrop(path: flow?.backdropPath, posterFallback: flow?.posterPath))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "chevron.down").font(.headline) }
                            .tint(Theme.Palette.gold)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task {
            guard flow == nil else { return }
            let f = session.makeAddFlow(for: hit)
            flow = f
            await f?.resolve()
        }
        .fullScreenCover(item: $playback) { presented in
            let engine = VLCKitVideoPlayerEngine(preferences: session.subtitleSettings.preferences)
            if let model = session.makePlayer(for: presented.request, engine: engine) {
                PlayerView(model: model, engine: engine,
                           backdropURL: TMDBClient.imageURL(path: presented.request.item.backdropPath, size: "w1280"),
                           onExit: { playback = nil })
            } else {
                PlayerPlaceholder(request: presented.request)
            }
        }
        // A successful add lands a new torrent in RD → refresh the library so it appears
        // without restarting the app.
        .onChange(of: flow?.add?.state) { _, newState in
            if case .added = newState { session.libraryStore?.retry() }
        }
    }

    @ViewBuilder private var content: some View {
        if let flow {
            switch flow.phase {
            case .resolving:
                ProgressView().tint(Theme.Palette.gold)
            case .resolveFailed(let msg):
                message(msg, systemImage: "exclamationmark.triangle")
            case .movie:
                MovieAddBody(flow: flow, onPlay: present)
            case .show:
                ShowAddBody(flow: flow, onPlay: present)
            }
        } else {
            ProgressView().tint(Theme.Palette.gold)
        }
    }

    private func present(_ request: PlaybackRequest) {
        playback = PlaybackPresentation(request: request)
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: systemImage).font(.system(size: 42)).foregroundStyle(Theme.Palette.gold)
            Text(text).font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, Theme.Space.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Movie

private struct MovieAddBody: View {
    let flow: AddFlowStore
    let onPlay: (PlaybackRequest) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Text(flow.title).font(Theme.Typo.titleXL()).foregroundStyle(Theme.Palette.textPrimary)
                if let year = flow.year {
                    Text(String(year)).font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                }
                if let overview = flow.overview {
                    Text(overview).font(Theme.Typo.body())
                        .foregroundStyle(Theme.Palette.textSecondary).lineSpacing(3)
                }
                TrailerButton(tmdbID: flow.tmdbID, kind: flow.mediaKind)
                if let add = flow.add { AddActionsView(flow: flow, add: add, onPlay: onPlay) }
            }
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, 200)
            .padding(.bottom, Theme.Space.xxl)
        }
    }
}

// MARK: - Show

private struct ShowAddBody: View {
    let flow: AddFlowStore
    let onPlay: (PlaybackRequest) -> Void
    @Environment(AppSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Text(flow.title).font(Theme.Typo.titleXL()).foregroundStyle(Theme.Palette.textPrimary)
                if let overview = flow.overview {
                    Text(overview).font(Theme.Typo.body())
                        .foregroundStyle(Theme.Palette.textSecondary).lineLimit(3)
                }
                TrailerButton(tmdbID: flow.tmdbID, kind: flow.mediaKind)
                seasonPicker
                SeasonDownloadButton(store: flow.seasonAdd) { session.libraryStore?.retry() }
                // Picked-episode actions surface right here (like a movie) so they're visible
                // without scrolling past the whole episode list.
                if let ep = selectedEpisodeMeta, let add = flow.add {
                    selectedEpisodeCard(ep: ep, add: add)
                }
                episodeList
            }
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)            // center the readable column (no left-edge crop on iPad)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, 200)
            .padding(.bottom, Theme.Space.xxl)
        }
    }

    private var selectedEpisodeMeta: TMDBEpisodeDetails? {
        flow.episodes.first { $0.episodeNumber == flow.selectedEpisode }
    }

    private func selectedEpisodeCard(ep: TMDBEpisodeDetails, add: AddStore) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.md) {
                episodeStill(ep)
                VStack(alignment: .leading, spacing: 4) {
                    Text("S\(flow.selectedSeason ?? 0)·E\(ep.episodeNumber)")
                        .font(Theme.Typo.label()).foregroundStyle(Theme.Palette.gold)
                    Text(ep.name ?? "Episode \(ep.episodeNumber)")
                        .font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textPrimary).lineLimit(2)
                }
                Spacer()
            }
            AddActionsView(flow: flow, add: add, onPlay: onPlay)
        }
        .padding(Theme.Space.md)
        .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Theme.Palette.gold.opacity(0.4), lineWidth: 1))
    }

    private func episodeStill(_ ep: TMDBEpisodeDetails) -> some View {
        AsyncImage(url: TMDBClient.imageURL(path: ep.stillPath, size: "w300")) { phase in
            if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
            else { ZStack { Theme.Palette.surface2; Image(systemName: "film").foregroundStyle(Theme.Palette.textTertiary) } }
        }
        .frame(width: 124, height: 70)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip))
    }

    @ViewBuilder private var seasonPicker: some View {
        if flow.seasons.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(flow.seasons, id: \.self) { s in
                        let selected = s == flow.selectedSeason
                        Button("Season \(s)") { Task { await flow.selectSeason(s) } }
                            .font(Theme.Typo.headline())
                            .foregroundStyle(selected ? Color(hex: 0x1A1400) : Theme.Palette.textSecondary)
                            .padding(.vertical, 7).padding(.horizontal, Theme.Space.lg)
                            .background(selected ? AnyShapeStyle(Theme.Palette.goldGradient)
                                                 : AnyShapeStyle(Theme.Palette.surface2), in: Capsule())
                    }
                }
            }
        }
    }

    private var episodeList: some View {
        VStack(spacing: 0) {
            ForEach(flow.episodes) { ep in
                let selected = ep.episodeNumber == flow.selectedEpisode
                Button { Task { await flow.selectEpisode(ep.episodeNumber) } } label: {
                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        episodeStill(ep)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(ep.episodeNumber). \(ep.name ?? "Episode \(ep.episodeNumber)")")
                                .font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textPrimary).lineLimit(1)
                            if let o = ep.overview, !o.isEmpty {
                                Text(o).font(Theme.Typo.caption())
                                    .foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(Theme.Palette.gold)
                    }
                    .padding(.vertical, Theme.Space.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().overlay(Theme.Palette.hairline)
            }
        }
    }
}

// MARK: - Shared add actions

private struct AddActionsView: View {
    let flow: AddFlowStore
    let add: AddStore
    let onPlay: (PlaybackRequest) -> Void
    @Environment(AppSession.self) private var session
    @State private var showAll = false
    @State private var loadingAll = false
    /// What the user just tapped to play, queued behind a "replace existing?" confirm. Set when
    /// the title is already in the library; cleared on confirm or cancel.
    @State private var pendingReplace: PendingAdd?

    /// Either "best" (auto-fallback) or a specific user-picked stream.
    private enum PendingAdd: Identifiable {
        case best, stream(CachedStream)
        var id: String { if case .stream(let s) = self { return s.infoHash } else { return "best" } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            switch add.state {
            case .loadingStreams:
                ProgressView("Finding cached versions…").tint(Theme.Palette.gold)
            case .noStreams:
                DownloadSection(flow: flow)
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                Button("Try Again") { Task { await add.loadStreams() } }.buttonStyle(GhostButtonStyle())
            default:
                actions
            }
            if showAllAvailable { showAllVersions }
        }
        .confirmationDialog(
            "Replace existing version?",
            isPresented: Binding(get: { pendingReplace != nil },
                                 set: { if !$0 { pendingReplace = nil } }),
            titleVisibility: .visible,
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
            HStack(spacing: Theme.Space.sm) {
                QualityChipRow(parsed: best.parsed)
                ForEach(best.languages.prefix(3), id: \.self) { QualityChip(text: $0.uppercased()) }
            }
            if add.isFallback {
                Label("Audio may not be in the original language.", systemImage: "info.circle")
                    .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textSecondary)
            }
            Button { playBest() } label: { Label("Play", systemImage: "play.fill") }
                .buttonStyle(GoldButtonStyle())
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
        }.buttonStyle(GhostButtonStyle())
        if showAll {
            if loadingAll {
                ProgressView().tint(Theme.Palette.gold)
            } else if add.allVersions.isEmpty {
                Text("No other versions found.").font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
            } else {
                allVersionsList
            }
        }
    }

    private var allVersionsList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            ForEach(add.allVersions) { stream in
                Button { pick(stream) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: Theme.Space.sm) {
                            CacheBadge(isCached: stream.isCached)
                            if let year = stream.parsed.year {
                                QualityChip(text: String(year))
                            }
                            QualityChipRow(parsed: stream.parsed)
                            ForEach(stream.languages.prefix(2), id: \.self) { QualityChip(text: $0.uppercased()) }
                            Spacer()
                            if let size = stream.sizeBytes {
                                Text(Self.sizeGB(size)).font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
                            }
                            Image(systemName: stream.isCached ? "play.circle.fill" : "arrow.down.circle.fill")
                                .foregroundStyle(Theme.Palette.gold)
                        }
                        // The full release name — read the source (CAM/TELESYNC), year, group to
                        // confirm it's the right film/version.
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
        }
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
            ProgressView("Adding to Real‑Debrid…").tint(Theme.Palette.gold)
        case .added:
            Label("Added — find it in your library.", systemImage: "checkmark.circle.fill")
                .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.gold)
        case .addFailed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(Theme.Typo.body()).foregroundStyle(.orange)
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

    /// The user's existing library item for this title, if any (movies only — shows aren't
    /// versioned at the item level).
    private func ownedItem() -> MediaItem? {
        guard flow.mediaKind == .movie else { return nil }
        return session.libraryStore?.ownedItem(tmdbID: flow.tmdbID)
    }
}

private extension AddActionsView {
    /// Replace-existing confirmation: surfaced when Play / a version is tapped on a title that's
    /// already in the library. Confirming removes the old item, then adds + plays the new pick.
    /// Lives at the bottom of the body via a modifier.
}

/// ⚡ Instant (already on RD) vs ⬇️ Download (will fetch) — from Comet's cache marker.
private struct CacheBadge: View {
    let isCached: Bool
    var body: some View {
        Label(isCached ? "Instant" : "Download", systemImage: isCached ? "bolt.fill" : "arrow.down.circle")
            .font(.system(size: 10, weight: .bold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isCached ? Color.green : Theme.Palette.gold)
            .padding(.vertical, 3).padding(.horizontal, 7)
            .background((isCached ? Color.green : Theme.Palette.gold).opacity(0.15), in: Capsule())
    }
}

// MARK: - Request Download (uncached fallback)

/// Shown when a title has no instantly-cached version. Offers "Request Download" (find the best
/// uncached release + start an RD download), then live progress driven by the app-wide
/// `DownloadStore`. When the download finishes the title flips into the library (Play lights up).
private struct DownloadSection: View {
    let flow: AddFlowStore
    @Environment(AppSession.self) private var session
    @State private var requesting = false

    var body: some View {
        let status = session.downloadStore?.status(forTMDB: flow.tmdbID)
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            if requesting && status == nil {
                ProgressView("Starting download…").tint(Theme.Palette.gold)
            } else if case .queued = status?.phase {
                ProgressView("Starting download…").tint(Theme.Palette.gold)
            } else if case .downloading = status?.phase {
                let pct = Int((status?.fraction ?? 0) * 100)
                Label("Downloading \(pct)% to Real‑Debrid…", systemImage: "arrow.down.circle.fill")
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.gold)
                ProgressView(value: status?.fraction ?? 0).tint(Theme.Palette.gold)
                Text("It'll appear in your library when it's ready.")
                    .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
                Button(role: .destructive) {
                    Task { await session.downloadStore?.cancel(tmdbID: flow.tmdbID) }
                } label: { Label("Cancel download", systemImage: "xmark.circle") }
                    .buttonStyle(GhostButtonStyle())
            } else if case .failed(let reason) = status?.phase {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(Theme.Typo.body()).foregroundStyle(.orange)
                requestButton(title: "Try Another Version")
            } else {
                Label("No cached version found.", systemImage: "magnifyingglass")
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                Text("It isn't in Real‑Debrid's cache yet. Start a download and it'll appear in your library when it's ready.")
                    .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
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
                                                     kind: flow.mediaKind, candidates: candidates)
                requesting = false
            }
        } label: { Label(title, systemImage: "arrow.down.circle") }
            .buttonStyle(GoldButtonStyle())
            .disabled(requesting)
    }
}
