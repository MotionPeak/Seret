import Foundation

enum Timecode {
    /// `h:mm:ss` (or `m:ss` under an hour).
    static func format(_ seconds: Double) -> String {
        let s = Int(seconds), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
