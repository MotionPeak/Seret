import Foundation

/// What a Matroska file's own index says about its subtitles and chapters.
///
/// mkvmerge writes a `Cues` entry for every subtitle line it muxes — the file's own timetable of
/// when each line is on screen, in perfect sync with the video because it IS the video's timeline.
/// It sits at the end of the file and is small (40 KB–2 MB measured across 43 real releases), so
/// reading it costs one ranged request rather than the film.
public struct MatroskaIndex: Sendable, Equatable {
    public struct SubtitleTrack: Sendable, Equatable {
        public let track: ContainerTrack
        /// When each indexed line leaves the screen (its start plus its duration, when the index
        /// records one), in seconds, ascending.
        public let lineEnds: [Double]

        public init(track: ContainerTrack, lineEnds: [Double]) {
            self.track = track
            self.lineEnds = lineEnds
        }
    }

    public struct Chapter: Sendable, Equatable {
        public let start: Double
        public let title: String?

        public init(start: Double, title: String?) {
            self.start = start
            self.title = title
        }
    }

    public let subtitles: [SubtitleTrack]
    /// The default edition's chapters, in file order.
    public let chapters: [Chapter]

    public init(subtitles: [SubtitleTrack], chapters: [Chapter]) {
        self.subtitles = subtitles
        self.chapters = chapters
    }
}

/// Parses the pieces of a Matroska file that make up a `MatroskaIndex`. Pure and bounds-checked,
/// like `MatroskaTrackReader`: bytes from the network must come back as "can't tell", never a crash.
public enum MatroskaIndexReader {
    typealias R = MatroskaTrackReader

    enum ID {
        static let info: UInt32 = 0x1549A966
        static let timecodeScale: UInt32 = 0x2AD7B1
        static let cues: UInt32 = 0x1C53BB6B
        static let cuePoint: UInt32 = 0xBB
        static let cueTime: UInt32 = 0xB3
        static let cueTrackPositions: UInt32 = 0xB7
        static let cueTrack: UInt32 = 0xF7
        static let cueDuration: UInt32 = 0xB2
        static let chapters: UInt32 = 0x1043A770
        static let editionEntry: UInt32 = 0x45B9
        static let chapterAtom: UInt32 = 0xB6
        static let chapterTimeStart: UInt32 = 0x91
        static let chapterDisplay: UInt32 = 0x80
        static let chapString: UInt32 = 0x85
        static let trackNumber: UInt32 = 0xD7
    }

    /// Where the parts of a file live, from its first bytes.
    public struct Layout: Sendable, Equatable {
        /// Absolute file offsets, from the SeekHead.
        public let tracksAt: Int?
        public let cuesAt: Int?
        public let chaptersAt: Int?
        /// Nanoseconds per timestamp tick. Matroska's default is a millisecond.
        public let timecodeScale: UInt64
    }

    /// Read the layout from a prefix of the file (it must start at byte 0). nil when it is not
    /// Matroska or its Segment cannot be found.
    public static func layout(_ bytes: [UInt8]) -> Layout? {
        guard let ebml = R.header(bytes, at: 0), ebml.id == R.ID.ebml, let ebmlSize = ebml.size,
              let segment = R.header(bytes, at: ebml.dataOffset + ebmlSize), segment.id == R.ID.segment
        else { return nil }
        let segmentStart = segment.dataOffset
        let segmentEnd = segment.size.map { segmentStart + $0 } ?? Int.max
        var tracksAt: Int?, cuesAt: Int?, chaptersAt: Int?
        var scale: UInt64 = 1_000_000

        func absolute(_ position: Int?) -> Int? {
            guard let position, position <= R.maxFileOffset else { return nil }
            let (offset, overflow) = segmentStart.addingReportingOverflow(position)
            return overflow ? nil : offset
        }

        var cursor = segmentStart
        while cursor < min(segmentEnd, bytes.count), let element = R.header(bytes, at: cursor) {
            if element.id == R.ID.cluster { break }
            guard let size = element.size else { break }
            let end = element.dataOffset + size
            let readable = min(end, bytes.count)
            switch element.id {
            case R.ID.seekHead:
                // The first SeekHead to name an element wins; a second one at the end of the file
                // only repeats it.
                tracksAt = tracksAt ?? absolute(R.seekPosition(of: R.ID.tracks, in: bytes,
                                                               from: element.dataOffset, to: readable))
                cuesAt = cuesAt ?? absolute(R.seekPosition(of: ID.cues, in: bytes,
                                                           from: element.dataOffset, to: readable))
                chaptersAt = chaptersAt ?? absolute(R.seekPosition(of: ID.chapters, in: bytes,
                                                                   from: element.dataOffset, to: readable))
            case ID.info:
                R.children(bytes, from: element.dataOffset, to: readable) { field, fieldEnd in
                    if field.id == ID.timecodeScale,
                       let value = R.uint(bytes, from: field.dataOffset, to: fieldEnd), value > 0 {
                        scale = value
                    }
                }
            case R.ID.tracks:
                tracksAt = tracksAt ?? cursor
            case ID.chapters:
                chaptersAt = chaptersAt ?? cursor
            default:
                break
            }
            cursor = end
        }
        return Layout(tracksAt: tracksAt, cuesAt: cuesAt, chaptersAt: chaptersAt, timecodeScale: scale)
    }

    /// The size of the element starting at `bytes[0]`, header included, when it is `id`. What a
    /// caller needs to know how much more to read.
    public static func elementLength(_ bytes: [UInt8], expecting id: UInt32) -> Int? {
        guard let header = R.header(bytes, at: 0), header.id == id, let size = header.size else { return nil }
        let (total, overflow) = header.dataOffset.addingReportingOverflow(size)
        return overflow ? nil : total
    }

    /// Subtitle tracks by track number, from bytes that start AT a Tracks element.
    public static func subtitleTracks(_ bytes: [UInt8]) -> [UInt64: ContainerTrack] {
        guard let element = R.header(bytes, at: 0), element.id == R.ID.tracks, let size = element.size
        else { return [:] }
        var out: [UInt64: ContainerTrack] = [:]
        for (number, track) in R.numberedEntries(in: bytes, from: element.dataOffset,
                                                 to: min(element.dataOffset + size, bytes.count))
        where track.kind == .subtitle {
            if let number { out[number] = track }
        }
        return out
    }

    /// When each indexed block of each track ENDS, in seconds — from bytes that start AT a Cues
    /// element. A block with no recorded duration ends where it starts.
    public static func lineEnds(_ bytes: [UInt8], timecodeScale: UInt64) -> [UInt64: [Double]] {
        guard let element = R.header(bytes, at: 0), element.id == ID.cues, let size = element.size
        else { return [:] }
        let seconds = Double(timecodeScale) / 1e9
        var out: [UInt64: [Double]] = [:]
        R.children(bytes, from: element.dataOffset, to: min(element.dataOffset + size, bytes.count)) { point, pointEnd in
            guard point.id == ID.cuePoint else { return }
            var time: UInt64?
            var positions: [(track: UInt64, duration: UInt64)] = []
            R.children(bytes, from: point.dataOffset, to: pointEnd) { field, fieldEnd in
                switch field.id {
                case ID.cueTime:
                    time = R.uint(bytes, from: field.dataOffset, to: fieldEnd)
                case ID.cueTrackPositions:
                    var track: UInt64?
                    var duration: UInt64 = 0
                    R.children(bytes, from: field.dataOffset, to: fieldEnd) { inner, innerEnd in
                        if inner.id == ID.cueTrack { track = R.uint(bytes, from: inner.dataOffset, to: innerEnd) }
                        if inner.id == ID.cueDuration {
                            duration = R.uint(bytes, from: inner.dataOffset, to: innerEnd) ?? 0
                        }
                    }
                    if let track { positions.append((track, duration)) }
                default:
                    break
                }
            }
            guard let time else { return }
            for position in positions {
                let (end, overflow) = time.addingReportingOverflow(position.duration)
                out[position.track, default: []].append(Double(overflow ? time : end) * seconds)
            }
        }
        return out.mapValues { $0.sorted() }
    }

    /// The first edition's chapters, from bytes that start AT a Chapters element.
    public static func chapters(_ bytes: [UInt8]) -> [MatroskaIndex.Chapter] {
        guard let element = R.header(bytes, at: 0), element.id == ID.chapters, let size = element.size
        else { return [] }
        var out: [MatroskaIndex.Chapter] = []
        var editionRead = false
        R.children(bytes, from: element.dataOffset, to: min(element.dataOffset + size, bytes.count)) { edition, editionEnd in
            guard edition.id == ID.editionEntry, !editionRead else { return }
            editionRead = true
            R.children(bytes, from: edition.dataOffset, to: editionEnd) { atom, atomEnd in
                guard atom.id == ID.chapterAtom else { return }
                var start: UInt64?
                var title: String?
                R.children(bytes, from: atom.dataOffset, to: atomEnd) { field, fieldEnd in
                    if field.id == ID.chapterTimeStart { start = R.uint(bytes, from: field.dataOffset, to: fieldEnd) }
                    if field.id == ID.chapterDisplay, title == nil {
                        title = R.string(child: ID.chapString, in: bytes, from: field.dataOffset, to: fieldEnd)
                    }
                }
                // ChapterTimeStart is always nanoseconds, whatever the timecode scale.
                if let start { out.append(.init(start: Double(start) / 1e9, title: title)) }
            }
        }
        return out
    }
}
