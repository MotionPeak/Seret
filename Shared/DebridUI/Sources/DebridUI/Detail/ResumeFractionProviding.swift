import DebridCore
import Foundation

/// An optional capability of a `WatchProgressProviding`: where to resume, as a fraction of runtime.
///
/// A fraction rather than seconds because that is what the player wants — it re-reads the resume
/// point at load time and multiplies by the runtime the media itself reports, so a version with a
/// different duration still resumes in the right place.
///
/// Obtained by casting the `watch` seam, exactly like `WatchSummaryProviding` and
/// `WatchRatingProviding`, so no call site threads a second dependency.
public protocol ResumeFractionProviding: Sendable {
    func resumeFraction(forContentKey key: String) async -> Double?
}

extension TraktWatchProvider: ResumeFractionProviding {
    /// Trakt only ever knew a percentage, so this is exactly its existing `fraction` lookup.
    public func resumeFraction(forContentKey key: String) async -> Double? {
        await fraction(forContentKey: key)
    }
}
