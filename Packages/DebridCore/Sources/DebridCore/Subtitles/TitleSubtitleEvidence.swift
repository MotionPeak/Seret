import Foundation

/// Everything a title page shows about Hebrew subtitles: the evidence for each version, and what
/// OpenSubtitles has for the film.
public struct TitleSubtitleEvidence: Sendable, Equatable {
    public let evidence: SubtitleEvidenceSet
    public let hebrewResults: [SubtitleResult]?

    public init(evidence: SubtitleEvidenceSet, hebrewResults: [SubtitleResult]?) {
        self.evidence = evidence
        self.hebrewResults = hebrewResults
    }
}

public extension SubtitleEvidenceService {
    /// A title's evidence as soon as it can be had, and never later than `limit`: what is ready by
    /// then, else what earlier visits stored. The header reads and the search carry on behind the
    /// answer, so the next ask has them. For a page that must not wait on either — the web's.
    func titleEvidence(for sources: [MediaSource], contentKey: String, query: SubtitleQuery?,
                       originalLanguage: String?, within limit: Duration) async -> TitleSubtitleEvidence {
        // Both paths rank with the same language, so which one answered cannot change the pick.
        var language = LanguageCode.normalize(originalLanguage)
        if language == nil { language = await storedLanguage(for: contentKey) }
        let originalLanguage = language
        let gather = Task { () -> TitleSubtitleEvidence in
            async let records = self.records(for: sources)
            var results: [SubtitleResult]?
            if let query {
                results = await self.hebrewResults(contentKey: contentKey, query: query,
                                                   originalLanguage: originalLanguage)
            }
            return TitleSubtitleEvidence(
                evidence: .owned(sources, records: await records, hebrewResults: results ?? [],
                                 originalLanguage: originalLanguage),
                hebrewResults: results)
        }
        if let ready = await valueIfReady(of: gather, within: limit) { return ready }
        let stored = await storedEvidence(for: sources, contentKey: contentKey)
        return TitleSubtitleEvidence(
            evidence: SubtitleEvidenceSet(byVersion: stored.byVersion, originalLanguage: originalLanguage),
            hebrewResults: await storedHebrewResults(contentKey: contentKey))
    }
}
