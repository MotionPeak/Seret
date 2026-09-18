import Foundation
import DebridCore

/// Writes one diary entry by driving the signed-in browser.
///
/// The POST is evaluated inside the film's own page, so it carries the browser's real cookies and
/// fingerprint because it *is* the browser's request. Copying a cookie into an HTTP client does not
/// work and cannot be made to: Cloudflare refuses every non-browser client, measured with a full
/// valid session and Chrome's exact User-Agent.
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

        let page = try await chrome.evaluate(Self.readPage)
        guard let csrf = page["csrf"] as? String, !csrf.isEmpty else {
            throw LetterboxdError.notAuthenticated
        }
        guard let uid = page["uid"] as? String, !uid.isEmpty else {
            throw LetterboxdError.structureChanged
        }

        let fields = LetterboxdDiaryForm.fields(for: entry, filmUid: uid, csrf: csrf)
        let result = try await chrome.evaluate(Self.post(fields: fields))

        let status = (result["status"] as? Int) ?? 0
        let body = (result["body"] as? String) ?? ""

        switch status {
        case 200..<300:
            return
        case 401, 403:
            // A challenge and a dead session need different fixes — re-solving Cloudflare versus
            // signing the container back in. Sending the owner to the wrong one wastes their time.
            throw body.contains("Just a moment") ? LetterboxdError.challenged
                                                 : LetterboxdError.notAuthenticated
        default:
            throw LetterboxdError.transient("save-diary-entry returned \(status)")
        }
    }

    /// Reads a live token and the film's identifier out of the loaded page.
    static let readPage = """
    (() => {
      const csrf = document.querySelector('input[name="__csrf"]')?.value || '';
      const uid = (document.documentElement.innerHTML.match(/film:\\d+/) || [])[0] || '';
      return { csrf, uid };
    })()
    """

    private static func post(fields: [String: String]) -> String {
        let json = String(decoding: (try? JSONSerialization.data(withJSONObject: fields)) ?? Data(),
                          as: UTF8.self)
        return """
        (async () => {
          const body = new URLSearchParams(\(json));
          const r = await fetch('/s/save-diary-entry', {
            method: 'POST',
            credentials: 'include',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded',
                       'X-Requested-With': 'XMLHttpRequest' },
            body
          });
          const text = await r.text();
          return { status: r.status, ok: r.ok, body: text.slice(0, 400) };
        })()
        """
    }
}
