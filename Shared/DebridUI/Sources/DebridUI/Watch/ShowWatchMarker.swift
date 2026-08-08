import DebridCore

/// Marks an entire series watched — or unwatched — from one gesture.
///
/// It writes a row **per episode**, not a single series-level flag. A flag would tick the poster
/// and leave every episode inside the show unticked, which is exactly the inconsistency this is
/// meant to remove. The series key is written too, because that is what a poster reads.
///
/// Cost is one TMDB request per season, so callers run it in the background. A season that fails to
/// load is skipped rather than aborting the rest: half a marked show beats none.
public struct ShowWatchMarker: Sendable {
    private let details: MediaDetailsProviding
    private let watch: WatchProgressProviding

    public init(details: MediaDetailsProviding, watch: WatchProgressProviding) {
        self.details = details
        self.watch = watch
    }

    public func mark(_ watched: Bool, show: MediaItem, profileID: String) async {
        guard show.kind == .show, let tmdbID = show.tmdbID else { return }

        // The series key first: it is what the poster reads, and it should flip even if TMDB is
        // unreachable and no episode can be enumerated.
        await watch.setWatched(watched, contentKey: show.id, sourceKey: "", profileID: profileID)

        guard let tv = try? await details.tvDetails(tmdbID: tmdbID),
              let seasonCount = tv.numberOfSeasons, seasonCount > 0 else { return }

        for season in 1...seasonCount {
            guard let episodes = try? await details.seasonEpisodes(tvID: tmdbID, season: season)
            else { continue }
            for episode in episodes {
                await watch.setWatched(watched,
                                       contentKey: WatchKey.content(forShow: show, season: season,
                                                                    number: episode.episodeNumber),
                                       sourceKey: "", profileID: profileID)
            }
        }
    }
}
