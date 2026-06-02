import Testing
import Foundation
@testable import DebridCore

@Suite struct LibrarySnapshotStoreTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "seret-snap-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sampleItems() -> [MediaItem] {
        [MediaItem(id: "movie:tmdb:1", kind: .movie, title: "A", year: 2020,
                   sources: [MediaSource(torrentID: "T", fileID: 1, restrictedLink: "https://rd/a",
                                         parsed: ParsedRelease(title: "A"))],
                   seasons: [], tmdbID: 1, posterPath: "/p.jpg", overview: "o")]
    }

    @Test func savesAndLoadsRoundTrip() throws {
        let store = LibrarySnapshotStore(directory: tempDir())
        let snap = LibrarySnapshot(items: sampleItems())
        try store.save(snap)
        let loaded = store.load()
        #expect(loaded?.items == sampleItems())
        #expect(loaded?.schemaVersion == LibrarySnapshot.currentSchemaVersion)
    }

    @Test func loadReturnsNilWhenMissing() {
        #expect(LibrarySnapshotStore(directory: tempDir()).load() == nil)
    }

    @Test func loadReturnsNilOnCorruptData() throws {
        let dir = tempDir()
        let store = LibrarySnapshotStore(directory: dir)
        try Data("not json".utf8).write(to: dir.appending(path: "library.json"))
        #expect(store.load() == nil)
    }

    @Test func loadReturnsNilOnSchemaMismatch() throws {
        let dir = tempDir()
        let store = LibrarySnapshotStore(directory: dir)
        // hand-write a snapshot whose version is in the future
        let future = #"{"schemaVersion":999,"builtAt":0,"items":[]}"#
        try Data(future.utf8).write(to: dir.appending(path: "library.json"))
        #expect(store.load() == nil)
    }

    @Test func saveOverwritesAtomically() throws {
        let store = LibrarySnapshotStore(directory: tempDir())
        try store.save(LibrarySnapshot(items: sampleItems()))
        try store.save(LibrarySnapshot(items: []))     // overwrite
        #expect(store.load()?.items.isEmpty == true)
    }
}
