import Testing
import DebridCore
@testable import DebridUI

@MainActor
@Suite struct ScrollFocusTrackerTests {
    private static func tile(_ id: Int) -> DownloadTile {
        DownloadTile(tmdbID: id, title: "T\(id)", posterPath: nil,
                     status: DownloadStatus(torrentID: "t\(id)", contentKey: "movie:tmdb:\(id)", tmdbID: id,
                                            phase: .downloading, fraction: 0.5))
    }
    private static let noGrid: (String) -> Bool = { _ in false }
    private static let grid: (String) -> Bool = { $0 == "cell" }

    @Test func followsTheLiveTilesWhileNothingInTheScrollHasFocus() {
        let tracker = ScrollFocusTracker()
        #expect(tracker.tiles(for: [Self.tile(1)], gridContains: Self.noGrid) == [Self.tile(1)])
        #expect(tracker.tiles(for: [], gridContains: Self.noGrid) == [])
        #expect(!tracker.holding)
    }

    @Test func holdsTheShapeWhileAGridCellHasFocus() {
        let tracker = ScrollFocusTracker()
        _ = tracker.tiles(for: [], gridContains: Self.grid)
        tracker.focusedID = "cell"
        // Appearing waits…
        #expect(tracker.tiles(for: [Self.tile(1)], gridContains: Self.grid) == [])
        #expect(tracker.holding)
        // …and lands once focus has left the scroll.
        tracker.focusedID = nil
        #expect(tracker.tiles(for: [Self.tile(1)], gridContains: Self.grid) == [Self.tile(1)])
        #expect(!tracker.holding)
        // Disappearing waits too, keeping the last cards.
        tracker.focusedID = "cell"
        #expect(tracker.tiles(for: [], gridContains: Self.grid) == [Self.tile(1)])
        #expect(tracker.holding)
    }

    @Test func liveTilesFlowInWhileTheShapeIsTheSame() {
        let tracker = ScrollFocusTracker()
        _ = tracker.tiles(for: [Self.tile(1)], gridContains: Self.grid)
        tracker.focusedID = "cell"
        #expect(tracker.tiles(for: [Self.tile(2)], gridContains: Self.grid) == [Self.tile(2)])
        #expect(!tracker.holding)
    }

    /// The focused card goes while another carries on: it never reports losing focus, so the
    /// tracker must drop it — or the next appear/disappear would be held with focus on the header.
    @Test func aRemovedFocusedStripCardStopsHoldingTheStrip() {
        let tracker = ScrollFocusTracker()
        _ = tracker.tiles(for: [Self.tile(1), Self.tile(2)], gridContains: Self.noGrid)
        tracker.focusedID = ScrollFocusTracker.stripID(Self.tile(1))
        #expect(tracker.tiles(for: [Self.tile(2)], gridContains: Self.noGrid) == [Self.tile(2)])
        #expect(tracker.focusedID == nil)
        // The last one ends: nothing in the scroll has focus, so the strip goes.
        #expect(tracker.tiles(for: [], gridContains: Self.noGrid) == [])
        #expect(!tracker.holding)
    }

    @Test func aRemovedFocusedGridTitleStopsHoldingTheStrip() {
        let tracker = ScrollFocusTracker()
        _ = tracker.tiles(for: [Self.tile(1)], gridContains: Self.grid)
        tracker.focusedID = "gone"            // a title removed from the library
        #expect(tracker.tiles(for: [], gridContains: Self.grid) == [])
        #expect(tracker.focusedID == nil)
    }

    /// The last card's download finishes while it has focus: the card stays (held), so focus stays.
    @Test func aFocusedLastCardIsHeldNotDropped() {
        let tracker = ScrollFocusTracker()
        _ = tracker.tiles(for: [Self.tile(1)], gridContains: Self.noGrid)
        tracker.focusedID = ScrollFocusTracker.stripID(Self.tile(1))
        #expect(tracker.tiles(for: [], gridContains: Self.noGrid) == [Self.tile(1)])
        #expect(tracker.focusedID == ScrollFocusTracker.stripID(Self.tile(1)))
        #expect(tracker.holding)
    }
}
