import DebridCore
import Foundation

/// The strings every download surface shows. One place, so the Home rail, the library strip and
/// Detail can never drift apart.
public enum DownloadProgressText {
    public static func percent(_ fraction: Double) -> String {
        "\(Int(max(0, min(1, fraction)) * 100))%"
    }

    /// A stable remaining-time phrase, or nil when the estimate is unknown.
    ///
    /// Quantized deliberately: rendered to the second, this visibly twitches on every poll even
    /// when the underlying estimate is steady. Under 90 seconds it stops counting altogether —
    /// the download is nearly done and the exact number helps no one.
    public static func remaining(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        if seconds < 90 { return "less than a minute left" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min left" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr left" : "\(hours) hr \(rest) min left"
    }

    /// The one-line status shown under a download card.
    public static func line(for status: DownloadStatus) -> String {
        switch status.phase {
        case .queued:
            return "Starting…"
        case .ready:
            return "Ready"
        case .failed:
            return "Couldn't download"
        case .downloading:
            let pct = percent(status.fraction)
            if let left = remaining(status.secondsRemaining) { return "\(pct) · \(left)" }
            if status.seeders == 0 { return "\(pct) · no seeders" }
            return pct
        }
    }
}
