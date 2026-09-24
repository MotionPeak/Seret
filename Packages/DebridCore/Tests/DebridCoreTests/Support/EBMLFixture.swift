@testable import DebridCore

/// Builds Matroska byte streams for tests: just enough EBML to exercise `MatroskaTrackReader`.
enum EBML {
    typealias ID = MatroskaTrackReader.ID

    static func element(_ id: UInt32, _ payload: [UInt8]) -> [UInt8] {
        idBytes(id) + size(payload.count) + payload
    }

    static func idBytes(_ id: UInt32) -> [UInt8] {
        var bytes: [UInt8] = []
        var value = id
        while value > 0 { bytes.insert(UInt8(value & 0xFF), at: 0); value >>= 8 }
        return bytes
    }

    /// Sizes in the 8-byte form, as mkvmerge writes them for large elements.
    static func size(_ n: Int) -> [UInt8] {
        [0x01] + stride(from: 48, through: 0, by: -8).map { UInt8((n >> $0) & 0xFF) }
    }

    static let unknownSize: [UInt8] = [0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]

    static func uint(_ id: UInt32, _ value: UInt64) -> [UInt8] {
        var payload: [UInt8] = []
        var v = value
        repeat { payload.insert(UInt8(v & 0xFF), at: 0); v >>= 8 } while v > 0
        return element(id, payload)
    }

    /// Always eight payload bytes, so a SeekHead's size does not depend on the offset it holds.
    static func uint64(_ id: UInt32, _ value: UInt64) -> [UInt8] {
        element(id, stride(from: 56, through: 0, by: -8).map { UInt8((value >> UInt64($0)) & 0xFF) })
    }

    static func string(_ id: UInt32, _ text: String) -> [UInt8] { element(id, Array(text.utf8)) }

    static func header(docType: String = "matroska") -> [UInt8] {
        element(ID.ebml, string(ID.docType, docType))
    }

    struct Track {
        var type: UInt64
        var language: String? = nil
        var bcp47: String? = nil
        var codec: String = "S_TEXT/UTF8"
        var name: String? = nil
        var forced = false
        var frameDuration: UInt64? = nil
    }

    static func trackEntry(_ t: Track) -> [UInt8] {
        var payload = uint(ID.trackType, t.type) + string(ID.codecID, t.codec)
        if let language = t.language { payload += string(ID.language, language) }
        if let bcp47 = t.bcp47 { payload += string(ID.languageBCP47, bcp47) }
        if let name = t.name { payload += string(ID.name, name) }
        if t.forced { payload += uint(ID.flagForced, 1) }
        if let d = t.frameDuration { payload += uint(ID.defaultDuration, d) }
        return element(ID.trackEntry, payload)
    }

    static func tracks(_ entries: [Track]) -> [UInt8] {
        element(ID.tracks, entries.flatMap(trackEntry))
    }

    /// A whole file: header, then a Segment of unknown size (as live muxers write it) holding an
    /// optional SeekHead, Info, `padding` bytes of Void, the Tracks, and a first Cluster.
    static func file(tracks entries: [Track], padding: Int = 0, seekHead: Bool = false,
                     docType: String = "matroska") -> [UInt8] {
        let info = element(0x1549A966, uint(0x2AD7B1, 1_000_000))
        let void = padding > 0 ? element(0xEC, [UInt8](repeating: 0, count: padding)) : []
        func seekHeadBytes(position: UInt64) -> [UInt8] {
            element(ID.seekHead, element(ID.seek, element(ID.seekID, idBytes(ID.tracks))
                                        + uint64(ID.seekPosition, position)))
        }
        var children: [UInt8] = []
        if seekHead {
            let position = UInt64(seekHeadBytes(position: 0).count + info.count + void.count)
            children += seekHeadBytes(position: position)
        }
        children += info + void + tracks(entries)
        return header(docType: docType) + idBytes(ID.segment) + unknownSize + children
            + element(ID.cluster, [0x81])
    }
}
