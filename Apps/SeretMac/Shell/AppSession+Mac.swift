import DebridCore
import DebridUI

extension AppSession {
    /// The one way the Mac builds a title's store (title page AND poster Play), wired exactly as
    /// the iPhone's DetailScreen does. nil while signed out.
    func makeDetailStore(for item: MediaItem) -> DetailStore? {
        guard let details = detailsProvider else { return nil }
        return DetailStore(item: item, details: details, watch: watchStore, profileID: activeProfileID,
                           myList: myListStore, ratings: ratingsProvider, versionPrefs: versionPreferences,
                           letterboxd: letterboxdRatingProvider, subtitleEvidence: subtitleEvidence)
    }
}
