import DebridCore
import DebridUI

/// What the sidebar's downloads card shows, worked out once from the active tiles — pure so the
/// ring fraction, the lead line and the help text are all unit-tested without a real `DownloadStore`.
struct DownloadsSummary: Equatable {
    let count: Int
    /// The ring: mean fraction across every active tile, 0...1.
    let fraction: Double
    /// Nearest done: highest fraction; ties settle by title order (stable, and never flickers
    /// between two downloads polling in the same tick).
    let lead: DownloadTile?
    /// The accounts the downloads run on, read off their torrent ids. A download filed before its
    /// torrent exists has no id yet and names no account.
    let providers: Set<DebridProvider>

    init(tiles: [DownloadTile]) {
        count = tiles.count
        providers = Set(tiles.map(\.status.torrentID).filter { !$0.isEmpty }.map(DebridProvider.of(torrentID:)))
        fraction = tiles.isEmpty ? 0 : tiles.reduce(0) { $0 + $1.status.fraction } / Double(tiles.count)
        lead = tiles.sorted {
            if $0.status.fraction != $1.status.fraction { return $0.status.fraction > $1.status.fraction }
            return $0.title < $1.title
        }.first
    }

    var leadLine: String? {
        guard let lead else { return nil }
        return "\(lead.title) \u{00B7} \(DownloadProgressText.line(for: lead.status))"
    }

    var helpText: String {
        "\(count) downloading" + (providers.isEmpty ? "" : " to \(DebridCopy.names(providers))")
    }
}
