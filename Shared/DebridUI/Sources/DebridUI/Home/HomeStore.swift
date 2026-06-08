import Foundation
import Observation
import DebridCore

/// One Continue-Watching entry: the title plus its resume progress and a subtitle (episode label).
public struct HomeItem: Identifiable, Sendable, Equatable {
    public let item: MediaItem
    public let fraction: Double
    public let subtitle: String
    public var id: String { item.id + "|" + subtitle }
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
        if let movie = movies.first(where: { $0.id == s.contentKey }) {
            return HomeItem(item: movie, fraction: fraction, subtitle: "")
        }
        if let show = shows.first(where: { s.contentKey.hasPrefix($0.id + ":") }) {
            let epKey = String(s.contentKey.dropFirst(show.id.count + 1))
            return HomeItem(item: show, fraction: fraction, subtitle: Self.formatEpisodeKey(epKey))
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
