import Foundation

/// Turns the address someone typed into a URL.
///
/// One definition, because the relay and the connection test must agree about what an address
/// means. If they disagreed, a test could pass against a URL the relay never actually posts to —
/// which is worse than having no test.
///
/// The typed form is a bare `host:port`; a scheme is accepted but not required, since nobody types
/// one into a settings field on a phone.
public enum SeretServerAddress {
    /// Nil for an address that is empty or cannot be made into a URL.
    public static func url(_ address: String, path: String) -> URL? {
        var trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // `hasPrefix("http")` would treat a host called `httpbin` as though it carried a scheme
        // and leave it unparseable, so the separator is what's looked for.
        if !trimmed.contains("://") { trimmed = "http://" + trimmed }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }

        return URL(string: trimmed + path)
    }
}
