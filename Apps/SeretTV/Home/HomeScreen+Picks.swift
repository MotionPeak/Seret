import DebridCore
import DebridUI
import SwiftUI

/// Home's two watchlist rows — "Picked for Right Now" and "Both of You Want to See" — as one value:
/// what `HomePicksStore` publishes, or the `-uiPreview homepicks` harness's fixture.
struct HomeWatchlistRows: Equatable {
    var picked: [WatchlistEntry] = []
    var both: [WatchlistEntry] = []
    /// Whose list each film is on — the chips and the header's tags. Nil with no partner.
    var membership: WatchlistMembership?
    var partnerName: String?
    /// The day's list is being made — on a first run, the minute before there is any.
    var isRefreshing = false

    var isEmpty: Bool { picked.isEmpty && both.isEmpty }
}

extension HomeWatchlistRows {
    @MainActor
    init(_ store: HomePicksStore) {
        self.init(picked: store.picked, both: store.both, membership: store.membership,
                  partnerName: store.partnerName, isRefreshing: store.isRefreshing)
    }
}
