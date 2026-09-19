import Foundation

/// The body of `POST /api/v0/production-log-entries`, as read off the signed-in site on 2026-09-19.
///
/// Letterboxd's diary write is a JSON API. The old `/s/save-diary-entry` form endpoint is gone —
/// the `action` attribute is still in their template and 404s on every shape of request — so the
/// field names here come from their own `_composeCreateLogEntryRequest`, not from the markup.
public enum LetterboxdLogEntry {
    /// `YYYY-MM-DD` in the viewer's own calendar.
    ///
    /// A watch date is a local-day fact: finishing a film at half past midnight is that day where
    /// the viewer is, whatever UTC calls it.
    public static func dateString(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The request body for one write — everything except `productionId`.
    ///
    /// The production is named in the page, because only the loaded page knows the film's uid.
    /// Guessing it here would risk writing a rating onto the wrong film.
    public static func json(for write: LetterboxdWrite,
                            timeZone: TimeZone = .current) throws -> String {
        var body: [String: Any] = ["tags": [], "like": false]

        if let watchedAt = write.watchedAt {
            // Omitted entirely without a date, exactly as their builder does: there is no diary
            // entry to describe, and an empty object is not the same thing as an absent one.
            body["diaryDetails"] = ["diaryDate": dateString(watchedAt, timeZone: timeZone),
                                    "rewatch": write.rewatch]
        }
        // 🚨 Out of five, not ten. Their response handler doubles it coming back.
        if let rating = write.rating, let stars = LetterboxdRating.stars(fromSeret: rating) {
            body["rating"] = stars
        }

        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
