import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession/URLRequest/URLResponse live here on Linux, not in Foundation
#endif

/// The OpenSubtitles movie hash: file size plus the sum of every little-endian `UInt64` word in
/// the first and last 64 KB, wrapping on overflow, as 16 lowercase hex characters.
///
/// Why it matters: a subtitle uploaded against this hash was timed against **this exact file**, so
/// it is a perfect-sync guarantee rather than a filename heuristic. Because only 128 KB is needed,
/// it can be computed against a remote RD stream with two HTTP range requests.
///
/// The arithmetic here was verified against the published `breakdance.avi` vector
/// (`8e245d9679d31e12`) fetched over HTTP range requests — the same path it takes against an RD
/// link. Do not alter it.
public enum MovieHash {
    public static let chunkSize = 65_536

    /// Pure: the hash from a file size and its first/last 64 KB. Returns nil if either chunk is
    /// short (a file smaller than 128 KB has no meaningful hash).
    public static func compute(fileSize: UInt64, head: Data, tail: Data) -> String? {
        guard head.count == chunkSize, tail.count == chunkSize else { return nil }
        var hash = fileSize
        for chunk in [head, tail] {
            chunk.withUnsafeBytes { raw in
                for offset in stride(from: 0, to: chunkSize, by: 8) {
                    hash &+= UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: offset,
                                                                    as: UInt64.self))
                }
            }
        }
        return String(format: "%016llx", hash)
    }

    /// Compute the hash of a remote file using two HTTP range requests (~128 KB total).
    /// Returns nil when the server does not report a length, does not honour ranges, or the file
    /// is too small — the caller then simply searches without a hash.
    public static func remote(url: URL, session: URLSession = .shared) async -> String? {
        guard let size = await contentLength(of: url, session: session),
              size >= UInt64(chunkSize) * 2 else { return nil }
        async let head = range(url, from: 0, to: UInt64(chunkSize) - 1, session: session)
        async let tail = range(url, from: size - UInt64(chunkSize), to: size - 1, session: session)
        guard let h = await head, let t = await tail else { return nil }
        return compute(fileSize: size, head: h, tail: t)
    }

    private static func contentLength(of url: URL, session: URLSession) async -> UInt64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200, http.expectedContentLength > 0 else { return nil }
        return UInt64(http.expectedContentLength)
    }

    private static func range(_ url: URL, from: UInt64, to: UInt64,
                              session: URLSession) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(from)-\(to)", forHTTPHeaderField: "Range")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 206,               // 200 means ranges were ignored
              data.count == chunkSize else { return nil }
        return data
    }
}
