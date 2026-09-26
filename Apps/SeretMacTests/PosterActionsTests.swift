import DebridCore
import Testing
@testable import Seret

@Suite struct PosterActionsTests {
    private static let allCombos: [(kind: MediaKind, owned: Bool, watched: Bool, onWatchlist: Bool)] = {
        var combos: [(MediaKind, Bool, Bool, Bool)] = []
        for kind in [MediaKind.movie, .show] {
            for owned in [false, true] {
                for watched in [false, true] {
                    for onWatchlist in [false, true] {
                        combos.append((kind, owned, watched, onWatchlist))
                    }
                }
            }
        }
        return combos
    }()

    @Test func everyHoverActionIsAlsoInTheMenu() {
        #expect(Self.allCombos.count == 16)
        for combo in Self.allCombos {
            let actions = PosterActions.make(kind: combo.kind, owned: combo.owned,
                                             watched: combo.watched, onWatchlist: combo.onWatchlist)
            let menuFlat = Set(actions.menu.flatMap { $0 })
            for action in actions.hover {
                #expect(menuFlat.contains(action), "\(action) missing from menu for \(combo)")
            }
        }
    }

    @Test func hoverIsPlayThenWatchlistThenMark() {
        let owned = PosterActions.make(kind: .movie, owned: true, watched: false, onWatchlist: false)
        #expect(owned.hover == [.play, .watchlist(adding: true), .markWatched(true)])
    }

    @Test func aTitleYouDoNotOwnHasNoPlayAndNoRemove() {
        let actions = PosterActions.make(kind: .movie, owned: false, watched: false, onWatchlist: false)
        #expect(!actions.hover.contains(.play))
        #expect(!actions.menu.flatMap { $0 }.contains(.play))
        #expect(!actions.menu.flatMap { $0 }.contains(.removeFromLibrary))
    }

    @Test func showsGetBothMarksInTheMenuAndOneOnHover() {
        let actions = PosterActions.make(kind: .show, owned: true, watched: false, onWatchlist: false)
        #expect(actions.hover == [.play, .markShowWatched(true)])
        let menuFlat = actions.menu.flatMap { $0 }
        #expect(menuFlat.contains(.markShowWatched(true)))
        #expect(menuFlat.contains(.markShowWatched(false)))
    }

    @Test func theWatchlistIsForFilmsOnly() {
        let show = PosterActions.make(kind: .show, owned: true, watched: false, onWatchlist: false)
        #expect(!show.hover.contains { if case .watchlist = $0 { true } else { false } })
        #expect(!show.menu.flatMap { $0 }.contains { if case .watchlist = $0 { true } else { false } })
    }

    @Test func removeIsLastAndOnlyForOwnedTitles() {
        let owned = PosterActions.make(kind: .movie, owned: true, watched: false, onWatchlist: false)
        #expect(owned.menu.last == [.removeFromLibrary])

        let notOwned = PosterActions.make(kind: .movie, owned: false, watched: false, onWatchlist: false)
        #expect(!notOwned.menu.flatMap { $0 }.contains(.removeFromLibrary))
    }

    @Test func openIsAlwaysOffered() {
        for combo in Self.allCombos {
            let actions = PosterActions.make(kind: combo.kind, owned: combo.owned,
                                             watched: combo.watched, onWatchlist: combo.onWatchlist)
            #expect(actions.menu.flatMap { $0 }.contains(.open))
        }
    }
}
