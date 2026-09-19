import Foundation
import DebridCore

/// Writes one diary entry by driving the signed-in browser.
///
/// The POST is evaluated inside the film's own page, so it carries the browser's real cookies and
/// fingerprint because it *is* the browser's request. Copying a cookie into an HTTP client does not
/// work and cannot be made to: Cloudflare refuses every non-browser client, measured with a full
/// valid session and Chrome's exact User-Agent.
///
/// The write itself is `POST /api/v0/production-log-entries`, a JSON API authenticated by the
/// session cookie and an `X-CSRF-TOKEN` header. The form at `/s/save-diary-entry` that the page
/// still renders has no endpoint behind it any more — every shape of request 404s.
public struct LetterboxdDiaryWriter: Sendable {
    private let chrome: ChromeSession
    private let resolver: any LetterboxdFilmResolving
    private let baseURL: String

    public init(chrome: ChromeSession,
                resolver: any LetterboxdFilmResolving,
                baseURL: String = "https://letterboxd.com") {
        self.chrome = chrome
        self.resolver = resolver
        self.baseURL = baseURL
    }

    public func write(_ entry: LetterboxdWrite) async throws {
        let slug = try await resolver.slug(forTMDB: entry.tmdbID)
        try await chrome.navigate(to: "\(baseURL)/film/\(slug)/")

        let body = try LetterboxdLogEntry.json(for: entry)
        let result = try await chrome.evaluate(Self.post(slug: slug, body: body))

        let status = (result["status"] as? Int) ?? 0
        let text = (result["body"] as? String) ?? ""

        switch status {
        case 200..<300:
            return
        case 0:
            // The page could not tell us who it was, which is what being signed out looks like
            // from in here.
            throw LetterboxdError.notAuthenticated
        case 401, 403:
            // Three things arrive as one status and need three different fixes: re-solve a
            // Cloudflare challenge, reload for a fresh token, or sign the container back in.
            if text.contains("Just a moment") { throw LetterboxdError.challenged }
            if text.localizedCaseInsensitiveContains("csrf") {
                throw LetterboxdError.transient("Letterboxd rejected the page's CSRF token")
            }
            throw LetterboxdError.notAuthenticated
        default:
            throw LetterboxdError.transient("production-log-entries returned \(status)")
        }
    }

    /// Reads the film's own metadata for the token and uid, then posts the entry.
    ///
    /// One evaluate does both so they cannot get out of step, and `/film/{slug}/json/` hands over
    /// `csrf` and `uid` together — which is also why nothing here scrapes the DOM.
    private static func post(slug: String, body: String) -> String {
        """
        (async () => {
          const meta = await (await fetch('/film/\(slug)/json/', { credentials: 'include' })).json();
          if (!meta || !meta.csrf || !meta.lid) return { status: 0, body: 'no session metadata' };
          // The LID, not the uid. `film:51977` is rejected outright - "Object not found due to
          // error for ID: film:51977" - while `2bdo` is accepted. Measured against the live API.
          const payload = Object.assign({ productionId: meta.lid }, \(body));
          const r = await fetch('/api/v0/production-log-entries', {
            method: 'POST',
            credentials: 'include',
            headers: { 'Content-Type': 'application/json',
                       'Accept': 'application/json',
                       'X-CSRF-TOKEN': meta.csrf },
            body: JSON.stringify(payload)
          });
          const text = await r.text();
          return { status: r.status, body: text.slice(0, 400) };
        })()
        """
    }
}
