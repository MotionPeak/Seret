import Foundation
import Observation
import DebridCore

/// The artwork and facts the preview header needs beyond what a tile already carries. Fetched on
/// demand from TMDB details, which ride the same call the Detail screen makes.
public struct TitleArt: Sendable, Equatable {
    public let logoPath: String?
    public let backdropPath: String?
    public let voteAverage: Double?
    public let genres: [String]
    public let runtimeMinutes: Int?
    public let seasonCount: Int?

    public init(logoPath: String?, backdropPath: String?, voteAverage: Double?, genres: [String],
                runtimeMinutes: Int?, seasonCount: Int?) {
        self.logoPath = logoPath; self.backdropPath = backdropPath; self.voteAverage = voteAverage
        self.genres = genres; self.runtimeMinutes = runtimeMinutes; self.seasonCount = seasonCount
    }
}

/// A bounded cache of `TitleArt`, shared by every screen with a preview header.
///
/// The load is **store-owned**: it runs in a task the store creates, so a caller that goes away
/// (focus moved on, the view disappeared) cannot cancel a fetch another caller is waiting on, and
/// two callers for one title share a single request.
@MainActor
@Observable
public final class TitleArtStore {
    private struct Key: Hashable { let kind: MediaKind; let tmdbID: Int }

    @ObservationIgnored private let details: MediaDetailsProviding
    @ObservationIgnored private let capacity: Int
    private var cache: [Key: TitleArt] = [:]
    /// Least- to most-recently used.
    @ObservationIgnored private var order: [Key] = []
    @ObservationIgnored private var inFlight: [Key: Task<TitleArt?, Never>] = [:]

    public init(details: MediaDetailsProviding, capacity: Int = 300) {
        self.details = details
        self.capacity = max(1, capacity)
    }

    /// The cached art, or nil when it hasn't loaded (or failed). Synchronous, so a view can render
    /// it the moment it exists.
    public func art(for kind: MediaKind, tmdbID: Int) -> TitleArt? {
        cache[Key(kind: kind, tmdbID: tmdbID)]
    }

    /// Loads (or joins the load of) a title's art. Nil on any error; a later call retries.
    public func load(_ kind: MediaKind, tmdbID: Int) async -> TitleArt? {
        let key = Key(kind: kind, tmdbID: tmdbID)
        if let cached = cache[key] { touch(key); return cached }
        if let running = inFlight[key] { return await running.value }
        let details = details
        let task = Task { [weak self] () -> TitleArt? in
            let art = await Self.fetch(details, kind: kind, tmdbID: tmdbID)
            self?.finish(key, art)
            return art
        }
        inFlight[key] = task
        return await task.value
    }

    private func finish(_ key: Key, _ art: TitleArt?) {
        inFlight[key] = nil
        guard let art else { return }
        cache[key] = art
        touch(key)
        while order.count > capacity {
            cache[order.removeFirst()] = nil
        }
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private nonisolated static func fetch(_ details: MediaDetailsProviding, kind: MediaKind,
                                          tmdbID: Int) async -> TitleArt? {
        do {
            switch kind {
            case .movie:
                let d = try await details.movieDetails(tmdbID: tmdbID)
                return TitleArt(logoPath: d.logoPath,
                                backdropPath: d.preferredBackdropPath ?? d.backdropPath,
                                voteAverage: d.voteAverage, genres: d.genres.map(\.name),
                                runtimeMinutes: d.runtime, seasonCount: nil)
            case .show:
                let d = try await details.tvDetails(tmdbID: tmdbID)
                return TitleArt(logoPath: d.logoPath,
                                backdropPath: d.preferredBackdropPath ?? d.backdropPath,
                                voteAverage: d.voteAverage, genres: d.genres.map(\.name),
                                runtimeMinutes: nil, seasonCount: d.numberOfSeasons)
            }
        } catch {
            return nil
        }
    }
}
