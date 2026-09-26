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

    init(tiles: [DownloadTile]) {
        count = tiles.count
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
        count == 1 ? "1 downloading to Real\u{2011}Debrid" : "\(count) downloading to Real\u{2011}Debrid"
    }
}
