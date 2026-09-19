import Foundation
import DebridCore

/// Adds or removes one film on the owner's Letterboxd watchlist by driving the signed-in browser.
///
/// The same shape as `LetterboxdDiaryWriter`, and for the same reason: the PATCH is evaluated
/// inside the film's own page so it carries the browser's real cookies and fingerprint, because it
/// *is* the browser's request. Cloudflare refuses every non-browser client regardless of headers.
///
/// The call is `PATCH /api/v0/me/watchlist/{lid}` with `{"inWatchlist": <bool>}`, authenticated by
/// the session cookie and an `X-CSRF-TOKEN` header — the site's API client is built with no
/// `authorization` function at all, so the cookie is the whole story.
public struct LetterboxdWatchlistWriter: Sendable {
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
        guard let body = LetterboxdWatchlistEntry.json(for: entry) else {
            // No change asked for. Nothing to send, and nothing failed.
            return
        }

        let slug = try await resolver.slug(forTMDB: entry.tmdbID)
        try await chrome.navigate(to: "\(baseURL)/film/\(slug)/")

        let result = try await chrome.evaluate(Self.patch(slug: slug, body: body))
        let status = (result["status"] as? Int) ?? 0
        let text = (result["body"] as? String) ?? ""

        switch status {
        case 200..<300:
            return
        case 0:
            // The page could not say who it was, which is what being signed out looks like here.
            throw LetterboxdError.notAuthenticated
        case 400:
            // The API validates the body and names the offending property. That is a contract
            // change on their side, not a transient fault, and retrying cannot fix it — so it is
            // surfaced rather than queued for another six hours of the same 400.
            throw LetterboxdError.transient("Letterboxd rejected the watchlist body: \(text)")
        case 401, 403:
            if text.contains("Just a moment") { throw LetterboxdError.challenged }
            if text.localizedCaseInsensitiveContains("csrf") {
                throw LetterboxdError.transient("Letterboxd rejected the page's CSRF token")
            }
            throw LetterboxdError.notAuthenticated
        default:
            throw LetterboxdError.transient("me/watchlist returned \(status)")
        }
    }

    /// Reads the film's own metadata for the token and LID, then PATCHes.
    ///
    /// One evaluate does both so they cannot get out of step, and `/film/{slug}/json/` hands over
    /// `csrf` and `lid` together — which is also why nothing here scrapes the DOM.
    ///
    /// The page also carries a `watchlistAction` of `/film/{slug}/add-to-watchlist/`. It is not
    /// used: it is a static template value (it reads "add" whatever the current state is), and an
    /// action attribute with nothing behind it is exactly what `/s/save-diary-entry` turned out
    /// to be.
    private static func patch(slug: String, body: String) -> String {
        """
        (async () => {
          const meta = await (await fetch('/film/\(slug)/json/', { credentials: 'include' })).json();
          if (!meta || !meta.csrf || !meta.lid) return { status: 0, body: 'no session metadata' };
          const r = await fetch('/api/v0/me/watchlist/' + meta.lid, {
            method: 'PATCH',
            credentials: 'include',
            headers: { 'Content-Type': 'application/json; charset=UTF-8',
                       'Accept': 'application/json',
                       'X-CSRF-TOKEN': meta.csrf },
            body: JSON.stringify(\(body))
          });
          const text = await r.text();
          return { status: r.status, body: text.slice(0, 400) };
        })()
        """
    }
}
