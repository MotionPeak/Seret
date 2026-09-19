import Testing
import Foundation
@testable import DebridCore

@Suite struct LetterboxdLoggedFilmsTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("logged-\(UUID().uuidString).json")
    }

    @Test func remembersWhatTheImportSaw() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        LetterboxdLoggedFilms(fileURL: url).save([73, 550])

        let reopened = LetterboxdLoggedFilms(fileURL: url)
        #expect(reopened.contains(tmdbID: 73))
        #expect(reopened.contains(tmdbID: 550))
        #expect(!reopened.contains(tmdbID: 999))
    }

    /// Never synced is not the same as "never watched". An empty set answers "I don't know" the
    /// only way it can, and the rewatch rule falls back to the local play count.
    @Test func anAbsentFileKnowsNothingRatherThanCrashing() {
        #expect(LetterboxdLoggedFilms(fileURL: tempFile()).load().isEmpty)
        #expect(!LetterboxdLoggedFilms(fileURL: nil).contains(tmdbID: 73))
    }
}
