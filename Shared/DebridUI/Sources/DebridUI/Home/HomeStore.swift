import Foundation
import Observation
import DebridCore

/// One Continue-Watching entry: the title plus its resume progress and a subtitle (episode label),
/// PLUS the exact source/episode/position needed to resume playback directly from Home (no detour
/// through the Detail screen). `source` is nil only when the file can't be resolved — then the UI
/// falls back to opening Detail.
public struct HomeItem: Identifiable, Sendable, Equatable {
    public let item: MediaItem
    public let fraction: Double
    public let subtitle: String
    public let episode: Episode?        // the exact episode to resume (nil for a movie)
    public let source: MediaSource?     // the file to play (nil = unresolved → not directly resumable)
    public let contentKey: String       // WatchKey the player records progress under
    public let resumeAt: Double?        // saved position hint (nil = start from 0 / finished)
    public var id: String { item.id + "|" + subtitle }

    /// True when Home can start playback directly (the file resolved).
    public var isResumable: Bool { source != nil }

    /// Build the request that resumes this entry, or nil if the source couldn't be resolved.
    public func playbackRequest() -> PlaybackRequest? {
        guard let source else { return nil }
        let label = episode.map { "\(item.title) — S\($0.season)\u{00B7}E\($0.number)" } ?? item.title
        return PlaybackRequest(item: item, source: source, resumeAt: resumeAt, label: label,
                               contentKey: contentKey, episode: episode, fromStart: false)
    }
}

/// Composes the Home tab's two rails from the library + watch progress. No persistence of its own.
@MainActor
@Observable
public final class HomeStore {
    public private(set) var continueWatching: [HomeItem] = []
    public private(set) var recentlyAdded: [MediaItem] = []
    public var featured: HomeItem? { continueWatching.first }

    /// The profile whose Continue Watching this Home shows. Set by `AppSession` on sign-in / switch.
    public var activeProfileID: String?

    private let watch: WatchProgressProviding
    public init(watch: WatchProgressProviding) { self.watch = watch }

    /// Recompute both rails for the active profile from the current library + watch progress.
    public func rebuild(movies: [MediaItem], shows: [MediaItem]) async {
        guard let profileID = activeProfileID else {
            continueWatching = []; recentlyAdded = []; return
        }
        let states = (try? await watch.recentlyWatched(limit: 20, profileID: profileID)) ?? []
        continueWatching = states.compactMap { Self.resolve($0, movies: movies, shows: shows) }
        let all = movies + shows
        recentlyAdded = Array(all.filter { $0.addedAt != nil }
            .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
            .prefix(20))
    }

    static func resolve(_ s: WatchState, movies: [MediaItem], shows: [MediaItem]) -> HomeItem? {
        let fraction = s.durationSeconds > 0 ? min(1, s.positionSeconds / s.durationSeconds) : 0
        // Resume hint: only when there's real, unfinished progress to jump back to.
        let resume: Double? = (!s.finished && s.positionSeconds > 0) ? s.positionSeconds : nil
        if let movie = movies.first(where: { $0.id == s.contentKey }) {
            return HomeItem(item: movie, fraction: fraction, subtitle: "",
                            episode: nil, source: movie.sources.best,
                            contentKey: s.contentKey, resumeAt: resume)
        }
        if let show = shows.first(where: { s.contentKey.hasPrefix($0.id + ":") }) {
            let epID = String(s.contentKey.dropFirst(show.id.count + 1))
            let episode = show.seasons.flatMap(\.episodes).first { $0.id == epID }
            return HomeItem(item: show, fraction: fraction, subtitle: Self.formatEpisodeKey(epID),
                            episode: episode, source: episode?.source,
                            contentKey: s.contentKey, resumeAt: resume)
        }
        return nil
    }

    /// "s3e4" → "S3 · E4"; falls back to the raw key if it isn't sXeY.
    static func formatEpisodeKey(_ key: String) -> String {
        let lower = key.lowercased()
        guard let s = lower.firstIndex(of: "s"), let e = lower.firstIndex(of: "e"), s < e else { return key }
        let season = lower[lower.index(after: s)..<e]
        let episode = lower[lower.index(after: e)...]
        guard !season.isEmpty, !episode.isEmpty,
              season.allSatisfy(\.isNumber), episode.allSatisfy(\.isNumber) else { return key }
        return "S\(season) · E\(episode)"
    }
}
