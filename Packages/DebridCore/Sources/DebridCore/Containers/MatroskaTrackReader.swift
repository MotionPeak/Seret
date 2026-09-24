import Foundation

/// Reads the track list out of the first bytes of a Matroska (MKV/WebM) file.
///
/// Matroska is EBML: a tree of elements, each an ID, a size and a payload. The track list lives in
/// the Segment's `Tracks` element, which every common muxer writes near the start (mkvmerge right
/// after `Info`, a few KB in). When something large sits in front of it, the `SeekHead` says where
/// it is, and one more read at that offset finds it.
///
/// Bounds-checked throughout: these are bytes from the network, and a malformed file must come
/// back as "can't tell", never as a crash.
public enum MatroskaTrackReader {

    public enum Result: Sendable, Equatable {
        case tracks([ContainerTrack])
        /// The Tracks element starts at this absolute file offset, past the bytes given.
        case tracksAt(offset: Int)
        case notMatroska
        /// A Matroska file whose track list could not be found in the bytes given.
        case incomplete
    }

    /// Scan a prefix of a file (it must start at byte 0).
    public static func read(_ bytes: [UInt8]) -> Result {
        guard let ebml = header(bytes, at: 0), ebml.id == ID.ebml, let ebmlSize = ebml.size else {
            return .notMatroska
        }
        let ebmlEnd = ebml.dataOffset + ebmlSize
        if let docType = string(child: ID.docType, in: bytes, from: ebml.dataOffset,
                                to: min(ebmlEnd, bytes.count)),
           docType != "matroska", docType != "webm" {
            return .notMatroska
        }
        guard let segment = header(bytes, at: ebmlEnd) else { return .incomplete }
        guard segment.id == ID.segment else { return .notMatroska }
        let segmentStart = segment.dataOffset
        let segmentEnd = segment.size.map { segmentStart + $0 } ?? Int.max
        var tracksAt: Int?
        var cursor = segmentStart
        while cursor < min(segmentEnd, bytes.count), let element = header(bytes, at: cursor) {
            if element.id == ID.cluster { break }               // media data: the header is over
            guard let size = element.size else { break }        // only Segment and Cluster may be unsized
            let end = element.dataOffset + size
            if element.id == ID.seekHead,
               let position = seekPosition(of: ID.tracks, in: bytes, from: element.dataOffset,
                                           to: min(end, bytes.count)) {
                tracksAt = segmentStart + position
            }
            if element.id == ID.tracks {
                guard end <= bytes.count else { return .tracksAt(offset: cursor) }
                return .tracks(entries(in: bytes, from: element.dataOffset, to: end))
            }
            cursor = end
        }
        if let tracksAt { return .tracksAt(offset: tracksAt) }
        return .incomplete
    }

    /// Parse bytes that start AT a Tracks element: the second read, at the SeekHead's offset.
    /// nil when it is not a Tracks element or is cut off.
    public static func readTracksElement(_ bytes: [UInt8]) -> [ContainerTrack]? {
        guard let element = header(bytes, at: 0), element.id == ID.tracks, let size = element.size,
              element.dataOffset + size <= bytes.count else { return nil }
        return entries(in: bytes, from: element.dataOffset, to: element.dataOffset + size)
    }

    // MARK: - Element IDs

    enum ID {
        static let ebml: UInt32 = 0x1A45DFA3
        static let docType: UInt32 = 0x4282
        static let segment: UInt32 = 0x18538067
        static let seekHead: UInt32 = 0x114D9B74
        static let seek: UInt32 = 0x4DBB
        static let seekID: UInt32 = 0x53AB
        static let seekPosition: UInt32 = 0x53AC
        static let tracks: UInt32 = 0x1654AE6B
        static let trackEntry: UInt32 = 0xAE
        static let trackType: UInt32 = 0x83
        static let codecID: UInt32 = 0x86
        static let language: UInt32 = 0x22B59C
        static let languageBCP47: UInt32 = 0x22B59D
        static let name: UInt32 = 0x536E
        static let flagForced: UInt32 = 0x55AA
        static let defaultDuration: UInt32 = 0x23E383
        static let cluster: UInt32 = 0x1F43B675
    }

    // MARK: - EBML

    struct Header {
        let id: UInt32
        let dataOffset: Int
        /// nil when the file declares the size unknown.
        let size: Int?
    }

    static func header(_ bytes: [UInt8], at offset: Int) -> Header? {
        guard let id = vint(bytes, at: offset, keepMarker: true), id.length <= 4,
              let size = vint(bytes, at: offset + id.length, keepMarker: false) else { return nil }
        let allOnes = (UInt64(1) << (7 * UInt64(size.length))) - 1
        let declared: Int? = size.value == allOnes ? nil : Int(exactly: size.value)
        return Header(id: UInt32(id.value), dataOffset: offset + id.length + size.length, size: declared)
    }

    /// An EBML variable-length integer: the count of leading zero bits in the first byte gives its
    /// length. IDs keep the length-marker bit; sizes drop it.
    static func vint(_ bytes: [UInt8], at offset: Int, keepMarker: Bool) -> (value: UInt64, length: Int)? {
        guard offset >= 0, offset < bytes.count, bytes[offset] != 0 else { return nil }
        let first = bytes[offset]
        let length = first.leadingZeroBitCount + 1
        guard offset + length <= bytes.count else { return nil }
        var value = UInt64(keepMarker ? first : first & (0xFF >> length))
        for i in 1..<length { value = (value << 8) | UInt64(bytes[offset + i]) }
        return (value, length)
    }

    /// Visit the direct children of the payload `from..<to`, stopping at the first one cut off.
    static func children(_ bytes: [UInt8], from: Int, to: Int, _ body: (Header, Int) -> Void) {
        var cursor = from
        while cursor < to, let child = header(bytes, at: cursor), let size = child.size {
            let end = child.dataOffset + size
            guard end <= to else { return }
            body(child, end)
            cursor = end
        }
    }

    static func uint(_ bytes: [UInt8], from: Int, to: Int) -> UInt64? {
        guard to - from >= 1, to - from <= 8 else { return nil }
        return bytes[from..<to].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    static func text(_ bytes: [UInt8], from: Int, to: Int) -> String? {
        guard to > from else { return nil }
        let raw = String(decoding: bytes[from..<to], as: UTF8.self)
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespaces))
        return trimmed.isEmpty ? nil : trimmed
    }

    static func string(child id: UInt32, in bytes: [UInt8], from: Int, to: Int) -> String? {
        var found: String?
        children(bytes, from: from, to: to) { child, end in
            if child.id == id, found == nil { found = text(bytes, from: child.dataOffset, to: end) }
        }
        return found
    }

    /// Where the SeekHead says `target` begins, relative to the Segment's payload.
    static func seekPosition(of target: UInt32, in bytes: [UInt8], from: Int, to: Int) -> Int? {
        var result: Int?
        children(bytes, from: from, to: to) { seek, seekEnd in
            guard seek.id == ID.seek, result == nil else { return }
            var seekID: UInt64?
            var position: UInt64?
            children(bytes, from: seek.dataOffset, to: seekEnd) { field, fieldEnd in
                if field.id == ID.seekID { seekID = uint(bytes, from: field.dataOffset, to: fieldEnd) }
                if field.id == ID.seekPosition { position = uint(bytes, from: field.dataOffset, to: fieldEnd) }
            }
            if seekID == UInt64(target), let position { result = Int(exactly: position) }
        }
        return result
    }

    static func entries(in bytes: [UInt8], from: Int, to: Int) -> [ContainerTrack] {
        var tracks: [ContainerTrack] = []
        children(bytes, from: from, to: to) { entry, entryEnd in
            guard entry.id == ID.trackEntry else { return }
            var type: UInt64?
            var codec: String?
            var language: String?
            var bcp47: String?
            var name: String?
            var forced = false
            var frameDuration: UInt64?
            children(bytes, from: entry.dataOffset, to: entryEnd) { field, fieldEnd in
                let start = field.dataOffset
                switch field.id {
                case ID.trackType: type = uint(bytes, from: start, to: fieldEnd)
                case ID.codecID: codec = text(bytes, from: start, to: fieldEnd)
                case ID.language: language = text(bytes, from: start, to: fieldEnd)
                case ID.languageBCP47: bcp47 = text(bytes, from: start, to: fieldEnd)
                case ID.name: name = text(bytes, from: start, to: fieldEnd)
                case ID.flagForced: forced = (uint(bytes, from: start, to: fieldEnd) ?? 0) != 0
                case ID.defaultDuration: frameDuration = uint(bytes, from: start, to: fieldEnd)
                default: break
                }
            }
            let kind: ContainerTrack.Kind
            switch type {
            case 1: kind = .video
            case 2: kind = .audio
            case 17: kind = .subtitle
            default: return                                   // logos, buttons, control tracks
            }
            // BCP 47 is the newer, more specific tag, and wins when a muxer writes both. A missing
            // Language element means "eng" by the spec's default, but claiming English on silence
            // would be a guess, so an untagged track falls through to its NAME instead.
            let code = LanguageCode.normalize(bcp47) ?? LanguageCode.normalize(language)
                ?? LanguageCode.fromName(name)
            var fps: Double?
            if kind == .video, let frameDuration, frameDuration > 0 {
                fps = ((1e9 / Double(frameDuration)) * 1000).rounded() / 1000
            }
            tracks.append(ContainerTrack(kind: kind, language: code, codec: codec, name: name,
                                         isForced: forced, frameRate: fps))
        }
        return tracks
    }
}
