import DebridCore
import Observation

/// Validation + submit state for pasting a magnet against one title or episode.
///
/// The model owns no download machinery: a valid paste becomes a single `CachedStream` candidate
/// handed to `DownloadStore.request(...)`, so persistence, polling and failure handling are the
/// ones already in use for indexer-sourced downloads.
@MainActor
@Observable
public final class MagnetAddModel {
    public enum State: Equatable {
        case idle
        case invalid
        case ready(displayName: String)
        case submitting
        case submitted
        case failed(String)
    }

    /// What the pasted magnet is *for* — the key it files under and the metadata a tile needs
    /// before the title exists in the library.
    public struct Target: Sendable, Equatable {
        public let contentKey: String
        public let tmdbID: Int
        public let title: String
        public let kind: MediaKind
        public let posterPath: String?

        public init(contentKey: String, tmdbID: Int, title: String,
                    kind: MediaKind, posterPath: String? = nil) {
            self.contentKey = contentKey; self.tmdbID = tmdbID; self.title = title
            self.kind = kind; self.posterPath = posterPath
        }
    }

    public private(set) var state: State = .idle
    private var link: MagnetLink?

    private let target: Target
    private let downloads: DownloadStore

    public init(target: Target, downloads: DownloadStore) {
        self.target = target
        self.downloads = downloads
    }

    public var canSubmit: Bool {
        if case .ready = state { return true }
        return false
    }

    /// Re-validates on every keystroke. An empty field is `.idle`, not `.invalid` — clearing the
    /// box is not an error and should not paint red.
    public func update(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            link = nil; state = .idle; return
        }
        if let parsed = MagnetLink.parse(text) {
            link = parsed
            state = .ready(displayName: parsed.displayName ?? parsed.infoHash)
        } else {
            link = nil
            state = .invalid
        }
    }

    public func submit() async {
        guard let link else { return }
        state = .submitting
        await downloads.request(contentKey: target.contentKey,
                                tmdbID: target.tmdbID,
                                title: target.title,
                                kind: target.kind,
                                candidates: [CachedStream.fromMagnet(link)],
                                posterPath: target.posterPath)
        // `request` never throws — it records the outcome as the content key's status.
        if case .failed(let reason)? = downloads.status(forContentKey: target.contentKey)?.phase {
            state = .failed(reason)
        } else {
            state = .submitted
        }
    }
}
