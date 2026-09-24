import CoreGraphics
import DebridCore
import DebridUI
import Foundation
import Testing
@testable import Seret

@MainActor
@Suite struct ShellModelTests {
    private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "seret.tests.\(UUID().uuidString)")! }

    @Test func startsOnHomeWithTheSidebarOpen() {
        let model = ShellModel(defaults: freshDefaults())
        #expect(model.selection == .home)
        #expect(model.isSidebarCollapsed == false)
    }

    @Test func collapsingIsRememberedAcrossLaunches() {
        let defaults = freshDefaults()
        let first = ShellModel(defaults: defaults)
        first.toggleSidebar()
        #expect(first.isSidebarCollapsed)
        #expect(ShellModel(defaults: defaults).isSidebarCollapsed)
    }

    @Test func commandDigitsSelectSectionsInSidebarOrder() {
        let model = ShellModel(defaults: freshDefaults())
        model.select(shortcut: 3)
        #expect(model.selection == .shows)
        model.select(shortcut: 5)
        #expect(model.selection == .library)
        model.select(shortcut: 9)                       // no such section: nothing changes
        #expect(model.selection == .library)
    }

    @Test func theSidebarIsGroupedBrowseThenYours() {
        #expect(SidebarSection.allCases.filter { $0.group == .browse } == [.home, .movies, .shows])
        #expect(SidebarSection.allCases.filter { $0.group == .yours } == [.watchlist, .library])
        #expect(SidebarSection.allCases.map(\.shortcutDigit) == [1, 2, 3, 4, 5])
    }

    // The literal RHS is cast to CGFloat explicitly: `#expect(cgFloat == 8 + 250 + 14)` mistypes the
    // right operand under this toolchain's Swift Testing macro expansion and fails even though the
    // values are equal (confirmed with a plain `==` outside the macro) — CGFloat(...) sidesteps it.
    @Test func contentStartsBesideTheSidebarInBothStates() {
        #expect(SidebarMetrics.contentLeading(collapsed: false) == CGFloat(8 + 250 + 14))
        #expect(SidebarMetrics.contentLeading(collapsed: true) == CGFloat(8 + 76 + 14))
    }

    // MARK: - Navigation

    private func item(_ id: String) -> MediaItem {
        MediaItem(id: id, kind: .movie, title: "Title \(id)", year: 2024, sources: [], seasons: [])
    }
    private func route(_ id: String) -> AppRoute { .title(item(id)) }

    @Test func eachSectionKeepsItsOwnPath() {
        let model = ShellModel(defaults: freshDefaults())
        model.select(.movies)
        model.open(route("a"))
        model.select(.shows)
        model.open(route("b"))

        #expect(model.history(for: .movies).path == [route("a")])
        #expect(model.history(for: .shows).path == [route("b")])
    }

    @Test func reselectingTheCurrentSectionPopsToRoot() {
        let model = ShellModel(defaults: freshDefaults())
        model.select(.library)
        model.open(route("a"))
        #expect(model.history(for: .library).path == [route("a")])

        model.select(.library)                     // already selected: pop to root
        #expect(model.selection == .library)
        #expect(model.history(for: .library).path.isEmpty)
    }

    @Test func openPushesOnTheSelectedSection() {
        let model = ShellModel(defaults: freshDefaults())
        model.select(.library)
        model.open(route("a"))
        #expect(model.history(for: .library).path == [route("a")])
        #expect(model.canGoBack)
    }

    // MARK: - Playback slot

    private func request(_ id: String) -> PlaybackRequest {
        let source = MediaSource(torrentID: id, fileID: nil, restrictedLink: "rd://\(id)",
                                 parsed: ParsedRelease(title: "t"))
        return PlaybackRequest(item: item(id), source: source, resumeAt: nil, label: "t", contentKey: id)
    }

    @Test func endingPlaybackClearsTheSlotAndOnlyTeardownSignalsPages() {
        let model = ShellModel(defaults: freshDefaults())
        model.present(request("a"))
        #expect(model.playback != nil)

        model.endPlayback()
        #expect(model.playback == nil)
        // Pages must not re-read watch state yet: the final position is still being written.
        #expect(model.playbackEndedCount == 0)

        model.playerDidTearDown()
        #expect(model.playbackEndedCount == 1)
    }

    @Test func presentingReplacesAnEarlierPresentation() {
        let model = ShellModel(defaults: freshDefaults())
        model.present(request("a"))
        let firstID = model.playback?.id
        model.present(request("a"))
        #expect(model.playback?.id != firstID)
    }

    // MARK: - Toast

    @Test func aNewToastReplacesTheOld() {
        let model = ShellModel(defaults: freshDefaults())
        model.showToast("First")
        let firstID = model.toast?.id
        model.showToast("Second", isFailure: true)

        #expect(model.toast?.id != firstID)
        #expect(model.toast?.message == "Second")
        #expect(model.toast?.isFailure == true)
    }

    @Test func dismissingAStaleToastKeepsTheNewOne() {
        let model = ShellModel(defaults: freshDefaults())
        model.showToast("First")
        let staleID = model.toast!.id
        model.showToast("Second")

        model.dismissToast(staleID)

        #expect(model.toast?.message == "Second")
    }

    // MARK: - Browse genre

    @Test func eachKindRemembersItsGenre() {
        let model = ShellModel(defaults: freshDefaults())
        let drama = DiscoverStore.Genre(name: "Drama", tmdbID: 18)
        let action = DiscoverStore.Genre(name: "Action & Adventure", tmdbID: 10759)

        model.setBrowseGenre(drama, for: .movie)
        model.setBrowseGenre(action, for: .show)

        #expect(model.browseGenre[.movie] == drama)
        #expect(model.browseGenre[.show] == action)
    }

    @Test func allClearsTheGenre() {
        let model = ShellModel(defaults: freshDefaults())
        let drama = DiscoverStore.Genre(name: "Drama", tmdbID: 18)
        model.setBrowseGenre(drama, for: .movie)

        model.setBrowseGenre(nil, for: .movie)

        #expect(model.browseGenre[.movie] == nil)
    }

    // MARK: - Search

    @Test func typingOpensSearchOnce() {
        let model = ShellModel(defaults: freshDefaults())
        model.setSearchQuery("d")
        model.setSearchQuery("du")
        #expect(model.history(for: .home).path == [.search])
    }

    @Test func clearingGoesBack() {
        let model = ShellModel(defaults: freshDefaults())
        model.setSearchQuery("dune")
        model.setSearchQuery("")
        #expect(model.history(for: .home).path.isEmpty)
    }

    @Test func searchOpensOnTheSelectedSection() {
        let model = ShellModel(defaults: freshDefaults())
        model.select(.library)
        model.setSearchQuery("dune")
        #expect(model.history(for: .library).path == [.search])
        #expect(model.history(for: .home).path.isEmpty)
    }

    @Test func aTitleOpenedFromResultsComesBackToResults() {
        let model = ShellModel(defaults: freshDefaults())
        model.setSearchQuery("dune")
        model.open(route("a"))
        #expect(model.history(for: .home).path == [.search, route("a")])

        model.goBack()

        #expect(model.history(for: .home).path == [.search])
    }

    @Test func focusRequestsCount() {
        let model = ShellModel(defaults: freshDefaults())
        #expect(model.searchFocusRequest == 0)
        model.requestSearchFocus()
        model.requestSearchFocus()
        #expect(model.searchFocusRequest == 2)
    }

    // MARK: - Title removal pop

    @Test func aRemovedTitleOnTopIsPopped() {
        let model = ShellModel(defaults: freshDefaults())
        model.select(.library)
        model.open(route("a"))
        model.popTitleIfShowing("a")
        #expect(model.history(for: .library).path.isEmpty)
    }

    @Test func aRemovedTitleNotOnTopIsLeftAlone() {
        let model = ShellModel(defaults: freshDefaults())
        model.select(.library)
        model.open(route("a"))
        model.popTitleIfShowing("b")               // some other title's removal
        #expect(model.history(for: .library).path == [route("a")])
    }

    // MARK: - Trailer overlay

    @Test func presentingATrailerThenPlaybackClosesTheTrailer() {
        let model = ShellModel(defaults: freshDefaults())
        model.presentTrailer(URL(string: "https://example.invalid/t")!, title: "Dune")
        #expect(model.trailer != nil)

        model.present(request("a"))

        #expect(model.trailer == nil)
        #expect(model.playback != nil)
    }

    @Test func noTrailerWhilePlaying() {
        let model = ShellModel(defaults: freshDefaults())
        model.present(request("a"))
        model.presentTrailer(URL(string: "https://example.invalid/t")!, title: "Dune")
        #expect(model.trailer == nil)
    }

    // MARK: - Add by Magnet

    @Test func magnetRequestsCount() {
        let model = ShellModel(defaults: freshDefaults())
        #expect(model.magnetRequest == 0)
        model.requestMagnet()
        model.requestMagnet()
        #expect(model.magnetRequest == 2)
    }

    @Test func titleOnTopReadsTheSelectedSection() {
        let model = ShellModel(defaults: freshDefaults())
        #expect(model.titleOnTop == nil)                // Home's root: no title showing

        model.select(.library)
        model.open(route("a"))
        #expect(model.titleOnTop?.id == "a")

        model.setSearchQuery("dune")                    // pushes .search on top of "a"
        #expect(model.titleOnTop == nil)                 // top of stack is .search, not a title
    }

    // MARK: - Hero flight

    private func sourceFrame() -> CGRect { CGRect(x: 100, y: 200, width: 150, height: 225) }
    private func heroFrame() -> CGRect { CGRect(x: 0, y: 0, width: 1440, height: 533) }

    @Test func openingATitleFromATileFliesForward() {
        let model = ShellModel(defaults: freshDefaults())
        model.windowSize = CGSize(width: 1440, height: 900)
        model.select(.library)
        let tileID = UUID()
        model.pendingFlightSource = FlightSource(tileID: tileID, frame: sourceFrame(), posterURL: nil)

        model.open(route("a"))

        #expect(model.flight?.direction == .forward)
        #expect(model.flight?.routeID == "a")
        #expect(model.flight?.from == sourceFrame())
        #expect(model.flight?.tileID == tileID)
        #expect(model.flight?.landed == false)
    }

    @Test func openingWithoutASourceDoesNotFly() {
        let model = ShellModel(defaults: freshDefaults())
        model.windowSize = CGSize(width: 1440, height: 900)
        model.select(.library)

        model.open(route("a"))

        #expect(model.flight == nil)
    }

    @Test func thePendingSourceIsConsumedEvenWhenNotFlying() {
        let model = ShellModel(defaults: freshDefaults())
        model.select(.library)
        // `windowSize` is left at `.zero` — the plan always cross-fades — but the pending source
        // must still be cleared, or a LATER open (once the window has a size) would wrongly fly
        // from this stale tile.
        model.pendingFlightSource = FlightSource(tileID: UUID(), frame: sourceFrame(), posterURL: nil)

        model.open(route("a"))

        #expect(model.pendingFlightSource == nil)
        #expect(model.flight == nil)
    }

    @Test func goingBackFliesToTheTilesLatestFrame() {
        let model = ShellModel(defaults: freshDefaults())
        model.windowSize = CGSize(width: 1440, height: 900)
        model.select(.library)
        let tileID = UUID()
        model.pendingFlightSource = FlightSource(tileID: tileID, frame: sourceFrame(), posterURL: nil)
        model.open(route("a"))
        model.heroFrame = heroFrame()
        // The grid scrolled while the title page was up: the tile now reports a different frame.
        let movedFrame = CGRect(x: 100, y: 40, width: 150, height: 225)
        model.tileFrames[tileID] = movedFrame

        model.goBack()

        #expect(model.flight?.direction == .back)
        #expect(model.flight?.from == movedFrame)
        #expect(model.flight?.to == heroFrame())
    }

    @Test func goingBackWithTheTileGoneCrossFades() {
        let model = ShellModel(defaults: freshDefaults())
        model.windowSize = CGSize(width: 1440, height: 900)
        model.select(.library)
        let tileID = UUID()
        model.pendingFlightSource = FlightSource(tileID: tileID, frame: sourceFrame(), posterURL: nil)
        model.open(route("a"))
        model.heroFrame = heroFrame()
        model.tileFrames[tileID] = nil          // the tile scrolled out of the grid / was recycled

        model.goBack()

        #expect(model.flight == nil)
        #expect(model.history(for: .library).path.isEmpty)
    }

    @Test func aStaleLandingIsIgnored() {
        let model = ShellModel(defaults: freshDefaults())
        model.windowSize = CGSize(width: 1440, height: 900)
        model.select(.library)
        model.pendingFlightSource = FlightSource(tileID: UUID(), frame: sourceFrame(), posterURL: nil)
        model.open(route("a"))
        let realID = model.flight!.id

        model.landFlight(UUID())                // some other, already-replaced flight's id

        #expect(model.flight?.id == realID)
        #expect(model.flight?.landed == false)
    }

    @Test func aSecondOpenMidFlightReplacesTheFlight() {
        let model = ShellModel(defaults: freshDefaults())
        model.windowSize = CGSize(width: 1440, height: 900)
        model.select(.library)
        model.pendingFlightSource = FlightSource(tileID: UUID(), frame: sourceFrame(), posterURL: nil)
        model.open(route("a"))
        let firstID = model.flight?.id

        model.pendingFlightSource = FlightSource(tileID: UUID(), frame: sourceFrame(), posterURL: nil)
        model.open(route("b"))

        #expect(model.flight?.id != firstID)
        #expect(model.flight?.routeID == "b")
    }
}
