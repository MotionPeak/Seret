import DebridCore
import DebridUI
import SwiftUI

/// Movie Detail: backdrop hero, metadata, overview, Play/Resume, Versions, Mark Watched.
struct MovieDetailView: View {
    let store: DetailStore
    var onRemove: () -> Void = {}

    private var item: MediaItem { store.item }
    private var contentKey: String { WatchKey.content(forMovie: item) }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TrailerHero(tmdbID: item.tmdbID, kind: .movie,
                            backdropPath: store.backdropPath, posterFallback: item.posterPath)
                VStack(alignment: .leading, spacing: 36) {
                    hero.frame(maxWidth: .infinity, alignment: .leading)
                    if store.versions.count > 1 { versionsSection }   // single source → no disclosure (spec §6)
                }
                .padding(60)
            }
        }
        .background(CanvasBackground())
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(item.title).font(.system(size: 48, weight: .bold))
            Text(metaLine).font(.body).foregroundStyle(.secondary)
            if let best = store.bestSource { QualityChips(parsed: best.parsed) }
            if let overview = store.overview {
                Text(overview).font(.body).frame(maxWidth: 1100, alignment: .leading).lineLimit(3)
            }
            actions
            if store.bestSource == nil, let tmdb = item.tmdbID {
                MovieDownloadSection(tmdbID: tmdb, title: item.title, posterPath: item.posterPath,
                                     imdbID: store.imdbID, originalLanguage: store.originalLanguage)
            }
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let y = item.year { parts.append(String(y)) }
        if let r = store.runtime { parts.append("\(r) min") }
        if !store.genres.isEmpty { parts.append(store.genres.prefix(3).joined(separator: " · ")) }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 20) {
            if let best = store.bestSource {
                if let resume = resumeSeconds {
                    NavigationLink(value: store.playRequest(source: best, episode: nil, label: item.title)) {
                        Label("Resume \(Timecode.format(resume))", systemImage: "play.fill")
                    }
                    NavigationLink(value: store.playRequest(source: best, episode: nil,
                                                            label: item.title, fromStart: true)) {
                        Label("Play from Start", systemImage: "gobackward")
                    }
                } else {
                    NavigationLink(value: store.playRequest(source: best, episode: nil, label: item.title)) {
                        Label("Play", systemImage: "play.fill")
                    }
                }
            }
            Button {
                Task {
                    await store.setWatched(!isWatched, contentKey: contentKey,
                                           source: store.bestSource ?? item.sources[0])
                }
            } label: {
                Label(isWatched ? "Mark Unwatched" : "Mark Watched",
                      systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .disabled(item.sources.isEmpty)
            TrailerButton(tmdbID: item.tmdbID, kind: .movie)
            Button(role: .destructive) { onRemove() } label: {
                Label("Remove from Library", systemImage: "trash")
            }
        }
        .font(.title3)
    }

    private var resumeSeconds: Double? {
        guard let w = watch, !w.finished, w.positionSeconds > 0 else { return nil }
        return w.positionSeconds
    }
    private var isWatched: Bool { watch?.finished == true }

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Versions").font(.title2.bold())
            ForEach(store.versions, id: \.self) { src in
                NavigationLink(value: store.playRequest(source: src, episode: nil, label: item.title)) {
                    HStack {
                        QualityChips(parsed: src.parsed)
                        Spacer()
                        Image(systemName: "play.circle")
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: 1100, alignment: .leading)
    }
}

#Preview {
    let s = MediaSource(torrentID: "t", fileID: nil, restrictedLink: "l",
                        parsed: ParsedRelease(title: "Dune", resolution: "2160p",
                                              source: "REMUX", videoCodec: "HEVC"))
    let item = MediaItem(id: "1", kind: .movie, title: "Dune: Part Two", year: 2024,
                         sources: [s], seasons: [], tmdbID: nil,
                         overview: "Paul Atreides unites with the Fremen…")
    return NavigationStack {
        MovieDetailView(store: DetailStore(item: item, details: PreviewDetails(), watch: nil))
    }
}

/// Inert provider for previews (never called when tmdbID is nil).
private struct PreviewDetails: MediaDetailsProviding {
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw CancellationError() }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
}

/// Request Download for a movie with no cached/playable version (tvOS). Mirrors the iOS Detail
/// section: fetch the best uncached release via the shared Add seam, start an RD download, and show
/// live progress from the app-wide `DownloadStore`. When it finishes the title flips into the
/// library and Play lights up.
private struct MovieDownloadSection: View {
    let tmdbID: Int
    let title: String
    let posterPath: String?
    let imdbID: String?
    let originalLanguage: String?
    @Environment(AppSession.self) private var session
    @State private var requesting = false

    var body: some View {
        let status = session.downloadStore?.status(forTMDB: tmdbID)
        VStack(alignment: .leading, spacing: 16) {
            if requesting && status == nil {
                ProgressView("Starting download…")
            } else if case .queued = status?.phase {
                ProgressView("Starting download…")
            } else if case .downloading = status?.phase {
                let pct = Int((status?.fraction ?? 0) * 100)
                Label("Downloading \(pct)% to Real-Debrid…", systemImage: "arrow.down.circle.fill")
                ProgressView(value: status?.fraction ?? 0).frame(maxWidth: 600)
                Text("It'll appear here when it's ready.").font(.callout).foregroundStyle(.secondary)
            } else if case .failed(let reason) = status?.phase {
                Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                requestButton("Try Another Version")
            } else {
                Text("No cached version exists. Start a download and it'll appear here when it's ready.")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: 1000, alignment: .leading)
                requestButton("Request Download")
            }
        }
        .font(.title3)
    }

    private func requestButton(_ label: String) -> some View {
        Button {
            Task {
                requesting = true
                var candidates: [CachedStream] = []
                if let imdbID, let add = session.makeAddStore(imdbID: imdbID, kind: .movie,
                                                              originalLanguage: originalLanguage) {
                    candidates = await add.uncachedCandidates()
                }
                await session.downloadStore?.request(tmdbID: tmdbID, title: title, kind: .movie,
                                                     candidates: candidates, posterPath: posterPath)
                requesting = false
            }
        } label: { Label(label, systemImage: "arrow.down.circle") }
            .disabled(requesting || imdbID == nil)
    }
}
