import Foundation

/// The body of `PATCH /api/v0/me/watchlist/{lid}`, as measured against the signed-in API on
/// 2026-09-19.
///
/// 🚨 The wire property is `inWatchlist`. The site's own component calls its state `isInWatchlist`
/// and maps it on the way out — sending that name back gets
/// `400 {"error":true,"message":"Unknown property at: isInWatchlist"}`. Verified both ways against
/// the live account: `{"inWatchlist":true}` added a film and `{"inWatchlist":false}` removed it,
/// each 200, each reflected on the watchlist page.
///
/// `{lid}` is the film's LID — the same `meta.lid` the diary write uses, not the `film:NNNNN` uid.
public enum LetterboxdWatchlistEntry {
    /// Nil when the write asks for no change, which is not something to send.
    public static func json(for write: LetterboxdWrite) -> String? {
        guard let inWatchlist = write.inWatchlist else { return nil }
        return #"{"inWatchlist":\#(inWatchlist)}"#
    }
}
