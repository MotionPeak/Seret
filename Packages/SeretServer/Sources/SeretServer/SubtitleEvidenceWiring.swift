import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import DebridCore

/// The Hebrew-subtitle evidence service as the web builds it: Real-Debrid resolves the links it
/// reads, and OpenSubtitles matching runs only when a key is configured.
func makeSubtitleEvidence(torrents: TorrentsClient, openSubtitlesKey: String) -> SubtitleEvidenceService {
    var search: SubtitleEvidenceService.Search?
    if !openSubtitlesKey.isEmpty {
        let provider = OpenSubtitlesProvider(apiKey: openSubtitlesKey, credentials: nil)
        search = { query, languages in try await provider.search(query, languages: languages) }
    }
    return SubtitleEvidenceService(
        directory: SubtitleEvidenceService.defaultDirectory,
        search: search,
        resolve: { link in
            let unrestricted = try await torrents.unrestrict(link: link)
            guard let url = URL(string: unrestricted.download) else { throw URLError(.badURL) }
            return ResolvedLink(url: url, fileName: unrestricted.filename)
        })
}
