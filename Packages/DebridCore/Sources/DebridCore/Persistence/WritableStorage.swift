import Foundation

/// Where this app is allowed to keep files — resolved by actually creating the directory, never by
/// assuming a search path exists.
///
/// The assumption cost a lot. `Application Support` was chosen for everything that had to survive a
/// relaunch, because tvOS purges `Caches/`. But a **tvOS app container has no `Application Support`
/// at all, and creating it fails with EPERM**. Read off a real Apple TV, its `Library/` holds
/// exactly four entries — `Caches`, `HTTPStorages`, `Preferences`, `SplashBoard` — and the app's
/// own diagnostics log caught the failure verbatim:
///
///     NSCocoaErrorDomain 513 "You don't have permission to save the file "SeretSubtitles"
///     in the folder "Application Support"" … NSPOSIXErrorDomain 1 "Operation not permitted"
///
/// Three things were filed there, and all three failed silently on that device for as long as it
/// has been shipping: every subtitle download, the library snapshot + OMDb ratings, and the
/// profile/download SwiftData stores — which fell back to an in-memory container, so nothing they
/// held survived a relaunch.
///
/// Application Support is still preferred, because where it exists it is durable and `Caches` is
/// purgeable. The difference is that it now has to prove it.
public enum WritableStorage {

    /// The platform's locations in order of preference. Only the ones that exist are usable, and
    /// only `directory(named:)` can tell which those are.
    public static var defaultCandidates: [URL] {
        let fm = FileManager.default
        return [.applicationSupportDirectory, .cachesDirectory]
            .compactMap { fm.urls(for: $0, in: .userDomainMask).first }
            + [fm.temporaryDirectory]
    }

    /// A directory named `name` inside the first candidate that will actually take it, created if
    /// it is not there yet. nil when nowhere will — in which case the caller has no disk at all and
    /// should degrade rather than throw.
    ///
    /// An existing directory is reused as it stands: every launch after the first arrives here, and
    /// treating "already there" as a failure would throw away the very cache this exists to keep.
    public static func directory(named name: String,
                                 candidates: [URL] = WritableStorage.defaultCandidates) -> URL? {
        for base in candidates {
            let url = base.appending(path: name, directoryHint: .isDirectory)
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                continue                     // this location refuses us — try the next one
            }
            guard FileManager.default.isWritableFile(atPath: url.path) else { continue }
            return url
        }
        return nil
    }

    /// The first candidate this app can actually write into, created if it is not there yet.
    ///
    /// Deliberately the BARE base rather than a folder of our own: on iOS `Application Support` is
    /// writable and already holds this app's SwiftData stores, so filing them under a new subfolder
    /// would orphan every existing profile, watch position and download. The rule throughout is the
    /// same path as before wherever the old code worked, and a different one only where it could
    /// not write at all.
    public static func baseDirectory(candidates: [URL] = WritableStorage.defaultCandidates) -> URL? {
        for base in candidates {
            do {
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            } catch {
                continue                     // this location refuses us — try the next one
            }
            guard FileManager.default.isWritableFile(atPath: base.path) else { continue }
            return base
        }
        return nil
    }

    /// A FILE at `name`, directly inside the first writable base — for a store that is one file
    /// rather than a folder. The parent is created; the file itself is not.
    public static func file(named name: String,
                            candidates: [URL] = WritableStorage.defaultCandidates) -> URL? {
        baseDirectory(candidates: candidates)?.appending(path: name)
    }
}
