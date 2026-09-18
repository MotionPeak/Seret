import Foundation

/// The `/s/save-diary-entry` form, as captured from the signed-in site on 2026-09-18.
///
/// The field names live here and nowhere else. They were read out of the real form over the
/// DevTools protocol rather than guessed from a logged-out page, because a wrong name fails
/// silently and writes junk into a real diary.
public enum LetterboxdDiaryForm {
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

    /// The form fields for one diary entry. `filmUid` is Letterboxd's own `film:1620206`.
    public static func fields(for write: LetterboxdWrite,
                              filmUid: String,
                              csrf: String,
                              timeZone: TimeZone = .current) -> [String: String] {
        var fields = [
            "__csrf": csrf,
            "viewingableUid": filmUid,
            // Empty creates a new entry. Seret only ever appends — it must never edit one the
            // owner made themselves.
            "viewingId": ""
        ]

        if let watchedAt = write.watchedAt {
            fields["specifiedDate"] = "true"
            fields["viewingDateStr"] = dateString(watchedAt, timeZone: timeZone)
        }
        // An unchecked checkbox is absent from a form post, not "false".
        if write.rewatch { fields["rewatch"] = "true" }
        if let rating = write.rating { fields["rating"] = String(rating) }

        return fields
    }
}
