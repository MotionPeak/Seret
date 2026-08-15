import Foundation

/// A magnet link (or bare infohash) the user pasted, reduced to what Real-Debrid needs.
///
/// RD's `addMagnet` takes an infohash, so parsing normalises every accepted form to lowercase
/// 40-hex. Base32 (32-char) infohashes appear in older links and decode to the same 20 bytes.
/// Anything else returns nil — there is no partial credit here, because a subtly wrong hash
/// produces a torrent that silently never resolves rather than an error the user can act on.
public struct MagnetLink: Sendable, Equatable {
    /// Lowercase 40-hex infohash.
    public let infoHash: String
    /// The `dn` display name when the link carried a non-empty one.
    public let displayName: String?

    public init(infoHash: String, displayName: String? = nil) {
        self.infoHash = infoHash
        self.displayName = displayName
    }

    public static func parse(_ raw: String) -> MagnetLink? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // A bare infohash pasted on its own. Checked first; no magnet URI is 40 hex chars.
        if let bare = normalizedHash(text) { return MagnetLink(infoHash: bare) }

        guard text.lowercased().hasPrefix("magnet:"),
              let comps = URLComponents(string: text),
              let items = comps.queryItems,
              let xt = items.first(where: { $0.name.lowercased() == "xt" })?.value,
              xt.lowercased().hasPrefix("urn:btih:"),
              let hash = normalizedHash(String(xt.dropFirst("urn:btih:".count)))
        else { return nil }

        return MagnetLink(infoHash: hash, displayName: displayName(from: items))
    }

    /// `URLComponents` percent-decodes query values but leaves `+`, which in a `dn` means space.
    private static func displayName(from items: [URLQueryItem]) -> String? {
        guard let dn = items.first(where: { $0.name.lowercased() == "dn" })?.value else { return nil }
        let name = dn.replacingOccurrences(of: "+", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// 40-hex → lowercased; 32-char base32 → decoded to 40-hex; anything else → nil.
    static func normalizedHash(_ s: String) -> String? {
        if s.count == 40, s.allSatisfy(\.isHexDigit) { return s.lowercased() }
        if s.count == 32 { return hexFromBase32(s) }
        return nil
    }

    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// RFC 4648 base32 → hex. 32 chars × 5 bits = 160 bits = the 20 bytes of an infohash.
    static func hexFromBase32(_ s: String) -> String? {
        var bits = 0
        var value = 0
        var bytes: [UInt8] = []
        for ch in s.uppercased() {
            guard let idx = base32Alphabet.firstIndex(of: ch) else { return nil }
            value = (value << 5) | idx
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        guard bytes.count == 20 else { return nil }
        // Stdlib radix conversion rather than String(format:) — this package must compile for
        // Linux (SeretServer), where format strings go through corelibs-foundation's CVarArg
        // path. Zero-padding by hand keeps it locale-free and dependency-free.
        return bytes.map { byte in
            let hex = String(byte, radix: 16)
            return byte < 0x10 ? "0" + hex : hex
        }.joined()
    }
}
