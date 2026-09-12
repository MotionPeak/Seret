import Testing
import Foundation
@testable import DebridCore

/// Where the app is allowed to keep files, which is not where it assumed.
///
/// Read off a real Apple TV: the app container's `Library/` holds exactly `Caches`,
/// `HTTPStorages`, `Preferences` and `SplashBoard`. There is no `Application Support`, and creating
/// it fails with EPERM — `NSCocoaErrorDomain 513, "You don't have permission to save the file
/// 'SeretSubtitles' in the folder 'Application Support'"`. Three things were filed there and all
/// three failed silently on that device: every subtitle download, the library snapshot + OMDb
/// ratings, and the profile/download SwiftData stores (which fell back to memory, so nothing
/// survived a relaunch).
///
/// So a location is only usable once it has actually been created. Preference order still puts
/// Application Support first, because on iOS it is durable and `Caches` is purgeable.
@Suite struct WritableStorageTests {

    /// A directory that exists but refuses to be written into — a tvOS `Application Support` in
    /// everything that matters here.
    private func unwritableDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "readonly-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: url.path)
        return url
    }

    private func writableDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "writable-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func thePreferredLocationIsUsedWhenItWorks() throws {
        let preferred = try writableDirectory()
        let fallback = try writableDirectory()
        defer { try? FileManager.default.removeItem(at: preferred) }
        defer { try? FileManager.default.removeItem(at: fallback) }

        let resolved = WritableStorage.directory(named: "SeretSubtitles",
                                            candidates: [preferred, fallback])

        #expect(resolved?.standardizedFileURL.path == preferred.appending(path: "SeretSubtitles").path)
        #expect(FileManager.default.fileExists(atPath: resolved!.path))
    }

    /// The tvOS case. Returning the unusable URL is what shipped: nothing failed until the first
    /// write, by which time the error was five layers away from the viewer.
    @Test func anUnwritableLocationIsSkippedForTheNextOne() throws {
        let refusing = try unwritableDirectory()
        let fallback = try writableDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: refusing.path)
            try? FileManager.default.removeItem(at: refusing)
            try? FileManager.default.removeItem(at: fallback)
        }

        let resolved = WritableStorage.directory(named: "SeretSubtitles",
                                            candidates: [refusing, fallback])

        #expect(resolved?.standardizedFileURL.path == fallback.appending(path: "SeretSubtitles").path)
        #expect(FileManager.default.fileExists(atPath: resolved!.path))
    }

    /// A directory already in use must be returned as-is, not treated as a failure — every launch
    /// after the first takes this path.
    @Test func anExistingDirectoryIsReusedRatherThanRejected() throws {
        let base = try writableDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let first = WritableStorage.directory(named: "Seret", candidates: [base])
        let marker = first!.appending(path: "library.json")
        try Data("{}".utf8).write(to: marker)
        let second = WritableStorage.directory(named: "Seret", candidates: [base])

        #expect(second == first)
        #expect(FileManager.default.fileExists(atPath: marker.path))   // nothing was wiped
    }

    @Test func nothingUsableYieldsNil() throws {
        let refusing = try unwritableDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: refusing.path)
            try? FileManager.default.removeItem(at: refusing)
        }

        #expect(WritableStorage.directory(named: "Seret", candidates: [refusing]) == nil)
    }

    /// A store file sits DIRECTLY in the base, with no folder of ours between.
    ///
    /// The first cut of this filed the SwiftData stores under a new `Seret/` subfolder. On iOS,
    /// where Application Support has always worked, that would have orphaned every existing
    /// profile, watch position, rating and download — a silent wipe dressed up as a bug fix.
    @Test func aStoreFileKeepsThePathItAlreadyHad() throws {
        let base = try writableDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let url = WritableStorage.file(named: "SeretProfiles.store", candidates: [base])

        #expect(url?.path == base.appending(path: "SeretProfiles.store").path)
    }

    @Test func aStoreFileFallsBackWhenTheBaseRefusesIt() throws {
        let refusing = try unwritableDirectory()
        let fallback = try writableDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: refusing.path)
            try? FileManager.default.removeItem(at: refusing)
            try? FileManager.default.removeItem(at: fallback)
        }

        let url = WritableStorage.file(named: "SeretProfiles.store", candidates: [refusing, fallback])

        #expect(url?.path == fallback.appending(path: "SeretProfiles.store").path)
    }

    /// The real platform list, exercised on whatever this is running on: it must produce a
    /// directory that can actually be written to.
    @Test func thePlatformDefaultResolvesToSomethingWritable() throws {
        let dir = try #require(WritableStorage.directory(named: "SeretStorageProbe"))
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appending(path: "probe.txt")
        try Data("ok".utf8).write(to: file)

        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
