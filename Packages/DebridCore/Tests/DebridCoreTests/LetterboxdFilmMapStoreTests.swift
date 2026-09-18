import Testing
import Foundation
@testable import DebridCore

@Suite struct LetterboxdFilmMapStoreTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lbmap-\(UUID().uuidString).json")
    }

    @Test func savesAndLoadsTheMap() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LetterboxdFilmMapStore(fileURL: url)
        store.save([335984: "blade-runner-2049", 550: "fight-club"])
        #expect(store.load() == [335984: "blade-runner-2049", 550: "fight-club"])
    }

    @Test func aMissingFileLoadsAsEmptyRatherThanThrowing() {
        #expect(LetterboxdFilmMapStore(fileURL: tempURL()).load().isEmpty)
    }

    @Test func aNilLocationDegradesToEmptyAndSavingIsHarmless() {
        let store = LetterboxdFilmMapStore(fileURL: nil)
        store.save([1: "x"])            // must not crash
        #expect(store.load().isEmpty)
    }

    @Test func corruptContentLoadsAsEmpty() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        #expect(LetterboxdFilmMapStore(fileURL: url).load().isEmpty)
    }

    @Test func aSavedMapSeedsAFilmMap() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LetterboxdFilmMapStore(fileURL: url)
        store.save([1637: "speed"])
        let map = LetterboxdFilmMap(seed: store.load())
        #expect(await map.slug(forTMDB: 1637) == "speed")
    }
}
