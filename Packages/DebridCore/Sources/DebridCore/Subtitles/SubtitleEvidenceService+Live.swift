import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession lives here on Linux
#endif

public extension SubtitleEvidenceService {
    /// The service as the apps and the web build it. Real-Debrid resolves the links it reads;
    /// OpenSubtitles matching runs only when a key is configured, and needs no account.
    ///
    /// - Parameter resolved: hears each link resolved for a read, with its playable URL, so Play
    ///   can reuse it instead of paying for a second `unrestrict`.
    static func live(torrents: TorrentsClient, openSubtitlesKey: String,
                     directory: URL = SubtitleEvidenceService.defaultDirectory,
                     resolved: (@Sendable (String, URL) async -> Void)? = nil) -> SubtitleEvidenceService {
        var search: Search?
        if !openSubtitlesKey.isEmpty {
            // Asked while a title page opens. The shared session would wait a full minute on a hung
            // OpenSubtitles before the page learned anything from it.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 20
            let provider = OpenSubtitlesProvider(
                apiKey: openSubtitlesKey, credentials: nil,
                http: HTTPClient(session: URLSession(configuration: configuration)))
            search = { query, languages in try await provider.search(query, languages: languages) }
        }
        return SubtitleEvidenceService(
            directory: directory,
            search: search,
            resolve: { link in
                let unrestricted = try await torrents.unrestrict(link: link)
                guard let url = URL(string: unrestricted.download) else { throw URLError(.badURL) }
                await resolved?(link, url)
                return ResolvedLink(url: url, fileName: unrestricted.filename)
            })
    }
}
