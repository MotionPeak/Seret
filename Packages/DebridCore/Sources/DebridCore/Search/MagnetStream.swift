import Foundation

public extension CachedStream {
    /// Presents a pasted magnet as an acquisition candidate, so it flows through the same
    /// `DownloadStore.request(...)` path as an indexer result. `isCached` is false because a
    /// pasted hash carries no instant-availability claim — RD may already hold it, in which case
    /// the download simply completes immediately.
    static func fromMagnet(_ link: MagnetLink,
                           parser: FilenameParser = FilenameParser(),
                           languages: LanguageDetector = LanguageDetector()) -> CachedStream {
        let name = link.displayName ?? link.infoHash
        return CachedStream(infoHash: link.infoHash,
                            fileIdx: nil,
                            rawTitle: name,
                            parsed: parser.parse(name),
                            languages: languages.detect(in: name),
                            sizeBytes: nil,
                            sourceName: "Magnet",
                            isCached: false)
    }
}
