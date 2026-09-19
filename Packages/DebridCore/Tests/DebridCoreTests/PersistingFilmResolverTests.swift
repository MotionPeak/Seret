import Testing
import Foundation
@testable import DebridCore

private struct CountingResolver: LetterboxdFilmResolving {
    let map: LetterboxdFilmMap
    let slugs: [Int: String]

    func slug(forTMDB id: Int) async throws -> String {
        if let known = await map.slug(forTMDB: id) { return known }
        guard let slug = slugs[id] else { throw LetterboxdError.filmNotFound }
        await map.store(slug, forTMDB: id)
        return slug
    }
}

struct PersistingFilmResolverTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
    }

    private func resolver(_ url: URL, map: LetterboxdFilmMap) -> PersistingFilmResolver {
        PersistingFilmResolver(resolver: CountingResolver(map: map, slugs: [1: "speed"]),
                               map: map,
                               store: LetterboxdFilmMapStore(fileURL: url))
    }

    @Test func aNewResolutionIsWrittenToDisk() async throws {
        let url = tempFile()
        let map = LetterboxdFilmMap()
        #expect(try await resolver(url, map: map).slug(forTMDB: 1) == "speed")
        #expect(LetterboxdFilmMapStore(fileURL: url).load() == [1: "speed"])
    }

    /// The point of persisting: a second launch seeded from disk answers without a request.
    @Test func aLaterLaunchAnswersFromTheStoredMap() async throws {
        let url = tempFile()
        _ = try await resolver(url, map: LetterboxdFilmMap()).slug(forTMDB: 1)

        let seeded = LetterboxdFilmMap(seed: LetterboxdFilmMapStore(fileURL: url).load())
        let offline = PersistingFilmResolver(resolver: CountingResolver(map: seeded, slugs: [:]),
                                             map: seeded,
                                             store: LetterboxdFilmMapStore(fileURL: url))
        #expect(try await offline.slug(forTMDB: 1) == "speed")
    }

    /// A slug the map already knows must not cost a disk write on every title page.
    @Test func anAlreadyKnownSlugIsNotRewritten() async throws {
        let url = tempFile()
        let map = LetterboxdFilmMap(seed: [1: "speed"])
        _ = try await resolver(url, map: map).slug(forTMDB: 1)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aFailedResolutionWritesNothing() async {
        let url = tempFile()
        _ = try? await resolver(url, map: LetterboxdFilmMap()).slug(forTMDB: 99)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
