import Testing
@testable import DebridUI

@Suite struct RailFocusNeighbourTests {
    private let old = ["cw/a", "cw/b", "cw/c", "dl/x", "movies/1", "movies/2", "shows/s"]

    /// A tile from the middle of a rail: the one that slid into its place.
    @Test func aMiddleTileHandsOnToTheOneAfterIt() {
        let new = old.filter { $0 != "cw/b" }
        #expect(RailFocusNeighbour.of("cw/b", old: old, new: new) == "cw/c")
    }

    /// The last tile of a rail: the new last, never a tile in another rail.
    @Test func theLastTileHandsOnToTheNewLast() {
        let new = old.filter { $0 != "cw/c" }
        #expect(RailFocusNeighbour.of("cw/c", old: old, new: new) == "cw/b")
    }

    /// A show's card moving on to its next episode: a new key at the same place.
    @Test func aReplacedTileHandsOnToItsReplacement() {
        let new = ["cw/a", "cw/b2", "cw/c", "dl/x", "movies/1", "movies/2", "shows/s"]
        #expect(RailFocusNeighbour.of("cw/b", old: old, new: new) == "cw/b2")
    }

    /// The rail's only tile: the first tile of the rail below, before the one above.
    @Test func anEmptiedRailHandsOnBelowBeforeAbove() {
        let new = old.filter { $0 != "dl/x" }
        #expect(RailFocusNeighbour.of("dl/x", old: old, new: new) == "movies/1")
    }

    /// The bottom rail emptied: nothing below, so the nearest rail above.
    @Test func anEmptiedBottomRailHandsOnAbove() {
        let new = old.filter { $0 != "shows/s" }
        #expect(RailFocusNeighbour.of("shows/s", old: old, new: new) == "movies/1")
    }

    /// The rail below went too, in the same change: the next one down that still has tiles.
    @Test func skipsRailsThatAreAlsoGone() {
        let new = ["cw/a", "cw/b", "cw/c", "shows/s"]
        #expect(RailFocusNeighbour.of("dl/x", old: old, new: new) == "shows/s")
    }

    /// The last tile on the page: nothing to hand on to.
    @Test func nothingLeftIsNil() {
        #expect(RailFocusNeighbour.of("cw/a", old: ["cw/a"], new: []) == nil)
    }
}
