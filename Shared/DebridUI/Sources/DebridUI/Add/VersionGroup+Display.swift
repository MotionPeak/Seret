import DebridCore

/// How a version list's two blocks are headed, the same in every app.
public extension VersionGroup.Availability {
    var title: String { self == .instant ? "Instant" : "Download" }

    var caption: String {
        self == .instant ? "Plays right away."
                         : "Downloads to Real\u{2011}Debrid first, then plays."
    }

    var systemImage: String { self == .instant ? "bolt.fill" : "arrow.down.circle.fill" }
}
