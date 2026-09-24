import Foundation

/// A `Range:` request header, in the forms libvlc sends — and the ones we refuse.
enum RangeRequest: Equatable, Sendable {
    /// No header: the whole file.
    case whole
    /// `bytes=N-` — every request libvlc makes.
    case from(Int64)
    /// `bytes=N-M`, inclusive.
    case span(Int64, Int64)
    /// Suffix ranges, multi-ranges, malformed input: answered 416.
    case unsatisfiable

    static func parse(_ header: String?) -> RangeRequest {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else {
            return .whole
        }
        guard header.lowercased().hasPrefix("bytes="), !header.contains(",") else {
            return .unsatisfiable
        }
        let spec = header.dropFirst("bytes=".count)
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let start = Int64(parts[0].trimmingCharacters(in: .whitespaces)), start >= 0
        else { return .unsatisfiable }
        let endText = parts[1].trimmingCharacters(in: .whitespaces)
        if endText.isEmpty { return .from(start) }
        guard let end = Int64(endText), end >= start else { return .unsatisfiable }
        return .span(start, end)
    }

    /// The inclusive byte range to send for a file of `total` bytes, or nil for a 416.
    func resolve(total: Int64) -> ClosedRange<Int64>? {
        guard total > 0 else { return nil }
        switch self {
        case .whole: return 0...(total - 1)
        case .from(let start): return start < total ? start...(total - 1) : nil
        case .span(let start, let end): return start < total ? start...min(end, total - 1) : nil
        case .unsatisfiable: return nil
        }
    }
}
