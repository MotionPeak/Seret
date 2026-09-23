import DebridCore
import Testing
@testable import Seret

@Suite struct TitleMenuTests {
    private static let allCombos: [(kind: MediaKind, owned: Bool, watched: Bool, inMyList: Bool,
                                    canMyList: Bool, hasTrailer: Bool, canMagnet: Bool, canFindVersions: Bool)] = {
        var combos: [(MediaKind, Bool, Bool, Bool, Bool, Bool, Bool, Bool)] = []
        for kind in [MediaKind.movie, .show] {
            for owned in [false, true] {
                for watched in [false, true] {
                    for inMyList in [false, true] {
                        for canMyList in [false, true] {
                            for hasTrailer in [false, true] {
                                for canMagnet in [false, true] {
                                    for canFindVersions in [false, true] {
                                        combos.append((kind, owned, watched, inMyList, canMyList,
                                                       hasTrailer, canMagnet, canFindVersions))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return combos
    }()

    private func make(_ c: (kind: MediaKind, owned: Bool, watched: Bool, inMyList: Bool, canMyList: Bool,
                            hasTrailer: Bool, canMagnet: Bool, canFindVersions: Bool)) -> [[TitleMenuItem]] {
        TitleMenu.make(kind: c.kind, owned: c.owned, watched: c.watched, inMyList: c.inMyList,
                      canMyList: c.canMyList, hasTrailer: c.hasTrailer, canMagnet: c.canMagnet,
                      canFindVersions: c.canFindVersions)
    }

    @Test func removeOnlyWhenOwned() {
        let owned = TitleMenu.make(kind: .movie, owned: true, watched: false, inMyList: false,
                                   canMyList: false, hasTrailer: false, canMagnet: false, canFindVersions: false)
        #expect(owned.flatMap { $0 }.contains(.removeFromLibrary))

        let notOwned = TitleMenu.make(kind: .movie, owned: false, watched: false, inMyList: false,
                                      canMyList: false, hasTrailer: false, canMagnet: false, canFindVersions: false)
        #expect(!notOwned.flatMap { $0 }.contains(.removeFromLibrary))
    }

    @Test func findOtherVersionsIsForFilmsOnly() {
        let film = TitleMenu.make(kind: .movie, owned: true, watched: false, inMyList: false,
                                  canMyList: false, hasTrailer: false, canMagnet: false, canFindVersions: true)
        #expect(film.flatMap { $0 }.contains(.findOtherVersions))

        let show = TitleMenu.make(kind: .show, owned: true, watched: false, inMyList: false,
                                  canMyList: false, hasTrailer: false, canMagnet: false, canFindVersions: true)
        #expect(!show.flatMap { $0 }.contains(.findOtherVersions))
    }

    @Test func showsGetBothMarksFilmsGetOne() {
        let film = TitleMenu.make(kind: .movie, owned: true, watched: false, inMyList: false,
                                  canMyList: false, hasTrailer: false, canMagnet: false, canFindVersions: false)
        let filmMarks = film.flatMap { $0 }.filter { if case .markWatched = $0 { true } else { false } }
        #expect(filmMarks.count == 1)

        let show = TitleMenu.make(kind: .show, owned: true, watched: false, inMyList: false,
                                  canMyList: false, hasTrailer: false, canMagnet: false, canFindVersions: false)
        #expect(show.flatMap { $0 }.contains(.markShowWatched(true)))
        #expect(show.flatMap { $0 }.contains(.markShowWatched(false)))
    }

    @Test func trailerOnlyWhenOneResolved() {
        let with = TitleMenu.make(kind: .movie, owned: true, watched: false, inMyList: false,
                                  canMyList: false, hasTrailer: true, canMagnet: false, canFindVersions: false)
        #expect(with.flatMap { $0 }.contains(.watchTrailer))

        let without = TitleMenu.make(kind: .movie, owned: true, watched: false, inMyList: false,
                                     canMyList: false, hasTrailer: false, canMagnet: false, canFindVersions: false)
        #expect(!without.flatMap { $0 }.contains(.watchTrailer))
    }

    @Test func myListOnlyWhenAvailable() {
        let with = TitleMenu.make(kind: .movie, owned: false, watched: false, inMyList: false,
                                  canMyList: true, hasTrailer: false, canMagnet: false, canFindVersions: false)
        #expect(with.flatMap { $0 }.contains { if case .myList = $0 { true } else { false } })

        let without = TitleMenu.make(kind: .movie, owned: false, watched: false, inMyList: false,
                                     canMyList: false, hasTrailer: false, canMagnet: false, canFindVersions: false)
        #expect(!without.flatMap { $0 }.contains { if case .myList = $0 { true } else { false } })
    }

    @Test func noEmptyGroups() {
        #expect(Self.allCombos.count == 256)
        for combo in Self.allCombos {
            let groups = make(combo)
            for group in groups {
                #expect(!group.isEmpty, "an empty group leaked through for \(combo)")
            }
        }
    }
}
