import DebridCore

extension LibraryStore {
    /// Removes `item` and hands back the store's user-facing message on failure — `nil` on
    /// success. Either way `removal` is left `.idle`, so the caller's next screen does not
    /// re-show a failure it already reported.
    ///
    /// Lifted out of tvOS's `LibraryRemovalConfirmation` (the "remove, then surface and clear the
    /// failure" pattern every screen offering removal wants) so the Mac's shared confirmation
    /// alert can call one thing instead of reaching into `removal` itself.
    public func removeReportingFailure(_ item: MediaItem) async -> String? {
        await remove(item)
        if case .failed(let message) = removal {
            clearRemovalError()
            return message
        }
        return nil
    }

    /// Removes one version and hands back what happened: `.removed(wasLast:)` on success —
    /// `wasLast` tells the caller whether the whole title just left the library, the same way
    /// tvOS's `DetailView.performVersionRemove` computed it before dismissing — or `.failed` with
    /// the store's user-facing message, already cleared from `removal` so the next screen does
    /// not re-show it.
    public func removeVersionReportingFailure(_ item: MediaItem,
                                              source: MediaSource) async -> VersionRemoval {
        let wasLast = item.sources.filter { $0 != source }.isEmpty
        await removeVersion(item, source: source)
        if case .failed(let message) = removal {
            clearRemovalError()
            return .failed(message)
        }
        return .removed(wasLast: wasLast)
    }
}

public enum VersionRemoval: Equatable {
    case removed(wasLast: Bool)
    case failed(String)
}

extension MediaSource {
    /// A version in words, for the delete confirmation and the Versions list — tvOS's
    /// `DetailView.describe`, moved so both platforms use the same wording:
    /// "1080p · TELESYNC · x264", or "This version" when nothing parsed.
    public var versionSummary: String {
        let parts = [parsed.resolution, parsed.source, parsed.videoCodec].compactMap { $0 }
        return parts.isEmpty ? "This version" : parts.joined(separator: " · ")
    }
}
