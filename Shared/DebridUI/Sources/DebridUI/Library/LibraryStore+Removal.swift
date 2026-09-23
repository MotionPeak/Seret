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
}
