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
            let engine = VLCKitVideoPlayerEngine()
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
                            .tint(s == flow.selectedSeason ? .white : .secondary)
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
    @State private var showVersions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch add.state {
            case .loadingStreams:
                ProgressView("Finding cached versions…").font(.title3)
            case .noStreams:
                Label("No cached versions found.", systemImage: "magnifyingglass")
                    .font(.title3).foregroundStyle(.secondary)
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle").font(.title3)
                Button("Try Again") { Task { await add.loadStreams() } }.font(.title3)
            default:
                actions
            }
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
            HStack(spacing: 20) {
                Button { Task { await flow.addBest() } } label: {
                    Label("Get best", systemImage: "plus.circle.fill")
                }
                Button {
                    Task {
                        await flow.addBest()
                        if case let .added(info) = add.state, let req = flow.playbackRequest(from: info) {
                            onPlay(req)
                        }
                    }
                } label: { Label("Add & Play", systemImage: "play.fill") }
                if add.ranked.count > 1 {
                    Button { showVersions.toggle() } label: {
                        Label("More versions", systemImage: "square.stack.3d.up")
                    }
                }
            }
            .font(.title3)
            addStatus
            if showVersions { versionsList }
        }
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

    private var versionsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Versions").font(.title2.bold())
            ForEach(add.ranked) { stream in
                Button { Task { await flow.add(stream: stream) } } label: {
                    HStack(spacing: 16) {
                        QualityChips(parsed: stream.parsed)
                        LanguageBadges(codes: stream.languages)
                        Spacer()
                        Image(systemName: "plus.circle")
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: 1100, alignment: .leading)
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
