import Foundation
import DebridCore

/// Turns a TMDB id into a Letterboxd slug by letting the browser follow `/tmdb/{id}/`.
///
/// DebridCore's resolver does the same thing over plain HTTP, which works on Apple platforms and
/// cannot work here: Cloudflare 403s the Linux client outright — measured on an ordinary film
/// page, with a Chrome User-Agent and a full set of browser headers, so it is the client being
/// refused rather than the request. The browser is already running for the write; it answers this
/// too, and its answer is exact because the id does the matching, not a title.
public struct ChromeFilmResolver: LetterboxdFilmResolving {
    private let chrome: ChromeSession
    private let map: LetterboxdFilmMap
    private let baseURL: String
    private let timeout: Duration
    private let poll: Duration

    public init(chrome: ChromeSession,
                map: LetterboxdFilmMap = LetterboxdFilmMap(),
                baseURL: String = "https://letterboxd.com",
                timeout: Duration = .seconds(30),
                poll: Duration = .milliseconds(250)) {
        self.chrome = chrome
        self.map = map
        self.baseURL = baseURL
        self.timeout = timeout
        self.poll = poll
    }

    public func slug(forTMDB id: Int) async throws -> String {
        if let cached = await map.slug(forTMDB: id) { return cached }

        // Cleared first. The browser is normally sitting on the last film it wrote to, and the
        // redirect target is recognised by its shape, so the page still on screen would answer
        // for it — a wrong slug, written to a real diary.
        try await chrome.navigate(to: "about:blank", timeout: timeout, poll: poll)

        let landed = try await chrome.navigate(to: "\(baseURL)/tmdb/\(id)/",
                                               timeout: timeout, poll: poll,
                                               accepting: Self.isAnswer)

        // Letterboxd bounces an id it does not know to its home page rather than 404ing, so
        // landing anywhere that is not a film page is the id being unknown.
        guard let slug = Self.slug(inHref: landed) else { throw LetterboxdError.filmNotFound }
        await map.store(slug, forTMDB: id)
        return slug
    }

    /// The slug in a Letterboxd `…/film/<slug>/…` address, if it is one.
    static func slug(inHref href: String) -> String? {
        guard let components = URLComponents(string: href), isLetterboxd(components) else { return nil }
        let parts = components.path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "film" else { return nil }
        return String(parts[1])
    }

    /// Either destination settles the question: the film, or the home page it bounces to.
    static func isAnswer(_ href: String) -> Bool {
        if slug(inHref: href) != nil { return true }
        guard let components = URLComponents(string: href), isLetterboxd(components) else { return false }
        return components.path.split(separator: "/").isEmpty
    }

    private static func isLetterboxd(_ components: URLComponents) -> Bool {
        components.host?.hasSuffix("letterboxd.com") == true
    }
}
