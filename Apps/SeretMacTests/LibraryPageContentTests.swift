import DebridCore
import DebridUI
import Testing
@testable import Seret

@Suite struct LibraryPageContentTests {
    private func item(_ id: String, kind: MediaKind = .movie) -> MediaItem {
        MediaItem(id: id, kind: kind, title: "Title \(id)", year: 2024, sources: [], seasons: [])
    }

    @Test func loadingShowsSkeletons() {
        #expect(LibraryPageContent.make(state: .loading, items: [], kind: .movie, accounts: [.realDebrid]) == .skeleton)
    }

    @Test func failureCarriesTheStoresMessage() {
        #expect(LibraryPageContent.make(state: .failed("offline"), items: [], kind: .movie, accounts: [.realDebrid]) == .failed("offline"))
    }

    @Test func anEmptyLibrarySaysSo() {
        #expect(LibraryPageContent.make(state: .empty, items: [], kind: .movie, accounts: [.realDebrid]) ==
               .empty(title: "Nothing in your library yet",
                     detail: "Add something to your Real-Debrid account and it appears here."))
        #expect(LibraryPageContent.make(state: .empty, items: [], kind: .movie, accounts: [.realDebrid, .torBox]) ==
               .empty(title: "Nothing in your library yet",
                     detail: "Add something to your Real-Debrid and TorBox accounts and it appears here."))
    }

    @Test func noShowsYetWhenOnlyFilmsAreOwned() {
        #expect(LibraryPageContent.make(state: .loaded, items: [], kind: .show, accounts: [.realDebrid]) ==
               .empty(title: "No shows yet", detail: nil))
    }

    @Test func aLoadedKindWithItemsIsAGrid() {
        #expect(LibraryPageContent.make(state: .loaded, items: [item("a")], kind: .movie, accounts: [.realDebrid]) == .grid)
    }
}
