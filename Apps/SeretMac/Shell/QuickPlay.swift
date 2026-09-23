import DebridCore
import DebridUI

/// Play from a poster: local reads only (no TMDB) — the preferred version and owned-episode watch
/// state are all `primaryPlay()` needs — so grid Play and the title page's Play always agree.
@MainActor enum QuickPlay {
    static func request(for item: MediaItem, session: AppSession) async -> PlaybackRequest? {
        guard let store = session.makeDetailStore(for: item) else { return nil }
        await store.loadPreferredVersion()
        await store.reloadWatch()
        return store.primaryPlay()?.request
    }
}
