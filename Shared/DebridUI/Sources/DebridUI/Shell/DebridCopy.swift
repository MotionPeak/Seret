import DebridCore

/// The words every app uses for the debrid accounts, so add, download and delete copy names the
/// account the action really touches. With Real-Debrid and TorBox both signed in, "Added to
/// Real-Debrid" for an add that went to TorBox — or "deletes it from your Real-Debrid account" for
/// a TorBox torrent — is simply false.
public enum DebridCopy {
    /// Shown when an add or download has no account to go to.
    public static let notSignedIn = "Sign in to Real-Debrid or TorBox first."

    /// "Real-Debrid", "TorBox", or "Real-Debrid and TorBox" — in `DebridProvider.allCases` order.
    public static func names(_ providers: some Sequence<DebridProvider>) -> String {
        let set = Set(providers)
        let ordered = DebridProvider.allCases.filter(set.contains).map(\.displayName)
        return ordered.isEmpty ? "your debrid account" : ordered.joined(separator: " and ")
    }

    /// "your TorBox account", or "your Real-Debrid and TorBox accounts".
    public static func accounts(_ providers: some Sequence<DebridProvider>) -> String {
        let set = Set(providers)
        guard !set.isEmpty else { return "your debrid account" }
        return "your \(names(set)) account\(set.count > 1 ? "s" : "")"
    }

    /// Every account a title draws from: a movie's versions, and every version of every episode.
    public static func providers(of item: MediaItem) -> Set<DebridProvider> {
        var ids = item.sources.map(\.torrentID)
        for season in item.seasons {
            for episode in season.episodes { ids += episode.sources.map(\.torrentID) }
        }
        return Set(ids.map(DebridProvider.of(torrentID:)))
    }

    /// The Accounts footer while fewer than both accounts are signed in. With one signed in it
    /// names the other — "Sign in to Real-Debrid and TorBox" read as if neither were.
    public static func addAccountHint(signedIn: some Sequence<DebridProvider>) -> String {
        let set = Set(signedIn)
        let others = DebridProvider.allCases.filter { !set.contains($0) }
        guard set.count == 1, others.count == 1, let other = others.first else {
            return "Sign in to \(names(DebridProvider.allCases)) to see titles from both in one library."
        }
        return "Sign in to \(other.displayName) too to see titles from both accounts."
    }

    public static func provider(of source: MediaSource) -> DebridProvider {
        .of(torrentID: source.torrentID)
    }
}

extension DownloadStatus {
    /// The account this download runs on. A status filed before its torrent exists has no id yet;
    /// it is going to the add target, which the caller passes.
    public func provider(orElse addTarget: DebridProvider) -> DebridProvider {
        torrentID.isEmpty ? addTarget : .of(torrentID: torrentID)
    }
}
