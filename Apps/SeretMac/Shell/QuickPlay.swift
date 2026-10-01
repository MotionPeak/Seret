import DebridCore
import DebridUI

/// Play from a poster: local reads only (no TMDB) — the preferred version and owned-episode watch
/// state are all `primaryPlay()` needs — so grid Play and the title page's Play agree. Where local
/// state cannot settle it (a show watched to its last owned episode: ended, or caught up on one
/// still airing?), nil — the caller opens the page, which asks TMDB.
@MainActor enum QuickPlay {
    static func request(for item: MediaItem, session: AppSession) async -> PlaybackRequest? {
        guard let store = session.makeDetailStore(for: item) else { return nil }
        await store.loadPreferredVersion()
        await store.reloadWatch()
        guard store.nextEpisodeIsSettled else { return nil }
        return store.primaryPlay()?.request
    }
}
