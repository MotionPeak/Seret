import Foundation

/// Errors from the high-level RD add flow (`TorrentsClient.add`).
public enum RDAddError: Error, Equatable, Sendable {
    /// Added + selected, but it did not reach `downloaded` within the poll budget —
    /// it wasn't actually instantly cached. `torrentID` lets the caller remove it.
    case notInstant(torrentID: String)
    /// RD reported a terminal error status (e.g. "error", "magnet_error", "dead", "virus").
    case failed(status: String, torrentID: String)
    /// RD refused the torrent as copyright-infringing (HTTP 451 `infringing_file`, error_code 35).
    /// It's on RD's blocklist — no retry or other version of the same flagged torrent will work.
    case blocked
}
