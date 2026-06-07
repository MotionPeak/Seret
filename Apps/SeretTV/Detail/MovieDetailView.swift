import DebridCore
import DebridUI
import SwiftUI

/// Movie Detail: backdrop hero, metadata, overview, Play/Resume, Versions, Mark Watched.
struct MovieDetailView: View {
    let store: DetailStore

    private var item: MediaItem { store.item }
    private var contentKey: String { WatchKey.content(forMovie: item) }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                // Anchor the hero to the bottom of the first screenful so the backdrop breathes
                // above it and the title/actions sit on a consistent baseline (Apple-TV style).
                hero.frame(maxWidth: .infinity, minHeight: 840, alignment: .bottomLeading)
                if store.versions.count > 1 { versionsSection }   // single source → no disclosure (spec §6)
            }
            .padding(60)
        }
        .background(BackdropBackground(path: store.backdropPath, posterFallback: item.posterPath))
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
