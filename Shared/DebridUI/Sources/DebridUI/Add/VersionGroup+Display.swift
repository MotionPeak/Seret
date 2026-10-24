import DebridCore

/// How a version list's two blocks are headed, the same in every app.
public extension VersionGroup.Availability {
    var title: String { self == .instant ? "Instant" : "Download" }

    /// - Parameter addTarget: where a download goes — the account the caption names.
    func caption(downloadsTo addTarget: DebridProvider) -> String {
        self == .instant ? "Plays right away."
                         : "Downloads to \(addTarget.displayName) first, then plays."
    }

    var systemImage: String { self == .instant ? "bolt.fill" : "arrow.down.circle.fill" }
}
