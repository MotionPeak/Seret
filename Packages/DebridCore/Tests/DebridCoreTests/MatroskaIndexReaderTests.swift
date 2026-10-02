import Testing
import Foundation
@testable import DebridCore

@Suite struct MatroskaIndexReaderTests {
    typealias T = EBML.Track
    typealias C = EBML.Cue

    private func bytes(at offset: Int?, of file: [UInt8]) -> [UInt8] {
        Array(file[(offset ?? 0)...])
    }

    @Test func theSeekHeadSaysWhereTheTracksChaptersAndIndexAre() throws {
        let file = EBML.indexedFile(tracks: [T(type: 17, number: 3)], cues: [C(time: 1000, track: 3)],
                                    chapters: [[(0, "One")]], timecodeScale: 500_000, mediaBytes: 4096)
        let layout = try #require(MatroskaIndexReader.layout(file))
        #expect(layout.timecodeScale == 500_000)
        #expect(MatroskaIndexReader.elementLength(bytes(at: layout.tracksAt, of: file),
                                                  expecting: MatroskaTrackReader.ID.tracks) != nil)
        #expect(MatroskaIndexReader.elementLength(bytes(at: layout.chaptersAt, of: file),
                                                  expecting: MatroskaIndexReader.ID.chapters) != nil)
        #expect(MatroskaIndexReader.elementLength(bytes(at: layout.cuesAt, of: file),
                                                  expecting: MatroskaIndexReader.ID.cues) != nil)
    }

    @Test func aFileWithNoIndexHasNoCuesPosition() throws {
        let file = EBML.indexedFile(tracks: [T(type: 17, number: 3)], cues: nil)
        #expect(try #require(MatroskaIndexReader.layout(file)).cuesAt == nil)
    }

    @Test func anMP4HasNoLayout() {
        #expect(MatroskaIndexReader.layout(Array("....ftypisom....moov".utf8)) == nil)
    }

    /// The index addresses tracks by NUMBER; the track list is what says which number is English.
    @Test func subtitleTracksAreKeyedByTheirNumber() {
        let tracksBytes = EBML.tracks([
            T(type: 1, codec: "V_MPEGH/ISO/HEVC", number: 1),
            T(type: 17, language: "heb", number: 4),
            T(type: 17, language: "eng", name: "English (SDH)", number: 5),
        ])
        let tracks = MatroskaIndexReader.subtitleTracks(tracksBytes)
        #expect(tracks.keys.sorted() == [4, 5])
        #expect(tracks[5]?.language == "en")
        #expect(tracks[5]?.name == "English (SDH)")
    }

    /// A line ends where it starts plus its recorded duration, in the file's own time scale.
    @Test func eachIndexedLineEndsAfterItsDuration() {
        let cuesBytes = EBML.cues([
            C(time: 61_000, track: 3, duration: 2_500),
            C(time: 1_000, track: 1),                       // video: kept, but under its own track
            C(time: 7_000, track: 3),
            C(time: 90_000, track: 4, duration: 1_000),
        ])
        let ends = MatroskaIndexReader.lineEnds(cuesBytes, timecodeScale: 1_000_000)
        #expect(ends[3] == [7, 63.5])                       // sorted, seconds
        #expect(ends[4] == [91])
        #expect(ends[1] == [1])
    }

    @Test func theTimecodeScaleIsApplied() {
        let ends = MatroskaIndexReader.lineEnds(EBML.cues([C(time: 100, track: 3)]),
                                                timecodeScale: 10_000_000)
        #expect(ends[3] == [1])
    }

    /// Discs with more than one edition (theatrical, extended) list each one's chapters; the first
    /// is the default.
    @Test func chaptersComeFromTheFirstEditionInSeconds() {
        let bytes = EBML.chapters([
            [(0, "Chapter 1"), (8_433_100_000_000, "End Credits")],
            [(0, "Extended 1"), (9_000_000_000_000, "Extended credits")],
        ])
        let chapters = MatroskaIndexReader.chapters(bytes)
        #expect(chapters == [.init(start: 0, title: "Chapter 1"), .init(start: 8433.1, title: "End Credits")])
    }

    @Test func truncatedBytesAreReadAsFarAsTheyGoWithoutCrashing() {
        let cuesBytes = EBML.cues((0..<50).map { C(time: UInt64($0) * 1000, track: 3) })
        for cut in stride(from: 0, to: cuesBytes.count, by: 7) {
            _ = MatroskaIndexReader.lineEnds(Array(cuesBytes.prefix(cut)), timecodeScale: 1_000_000)
            _ = MatroskaIndexReader.chapters(Array(cuesBytes.prefix(cut)))
            _ = MatroskaIndexReader.layout(Array(cuesBytes.prefix(cut)))
        }
    }
}

extension MockTests {
    @Suite struct ContainerIndexProbeTests {
        typealias T = EBML.Track
        init() { MockURLProtocol.handler = nil }

        final class RangeLog: @unchecked Sendable {
            private let lock = NSLock()
            private var ranges: [String] = []
            func add(_ range: String?) { lock.lock(); ranges.append(range ?? ""); lock.unlock() }
            var all: [String] { lock.lock(); defer { lock.unlock() }; return ranges }
        }

        private let url = URL(string: "https://example.download.real-debrid.com/d/ABC/Movie.mkv")!

        private func probe() -> ContainerProbe {
            ContainerProbe(configuration: {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [MockURLProtocol.self]
                return configuration
            })
        }

        private static func serve(_ file: [UInt8], log: RangeLog) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
            { request in
                let range = request.value(forHTTPHeaderField: "Range")
                log.add(range)
                let bounds = (range ?? "").replacingOccurrences(of: "bytes=", with: "")
                    .split(separator: "-").compactMap { Int($0) }
                guard let start = bounds.first, start < file.count else {
                    return (HTTPURLResponse(url: request.url!, statusCode: 416, httpVersion: nil,
                                            headerFields: nil)!, Data())
                }
                let end = min(bounds.count > 1 ? bounds[1] : file.count - 1, file.count - 1)
                return (HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: nil,
                                        headerFields: nil)!, Data(file[start...end]))
            }
        }

        /// A film's worth of media between the header and the index, as in every real file: the
        /// index has to be fetched from the far end, and nothing in between is read.
        @Test func readsTheIndexFromTheEndOfTheFileWithoutTheMedia() async throws {
            let lines = (0..<400).map { EBML.Cue(time: UInt64($0) * 15_000, track: 3, duration: 2_000) }
            let file = EBML.indexedFile(
                tracks: [T(type: 1, codec: "V_MPEGH/ISO/HEVC", number: 1),
                         T(type: 17, language: "eng", name: "English", number: 3)],
                cues: lines, chapters: [[(0, "Chapter 1"), (6_100_000_000_000, "End Credits")]],
                mediaBytes: 3 * ContainerProbe.window)
            let log = RangeLog()
            MockURLProtocol.handler = Self.serve(file, log: log)

            let index = try #require(await probe().index(at: url))

            #expect(index.subtitles.count == 1)
            #expect(index.subtitles.first?.track.language == "en")
            let lastLine: Double = index.subtitles.first?.lineEnds.last ?? 0
            #expect(abs(lastLine - 5987) < 0.001)       // 399 × 15s + its 2s on screen
            #expect(index.chapters.last == .init(start: 6100, title: "End Credits"))
            // The first window, then the index — never the media.
            #expect(log.all.count == 2)
            let bytesRead = log.all.compactMap { range -> Int? in
                let b = range.replacingOccurrences(of: "bytes=", with: "").split(separator: "-").compactMap { Int($0) }
                return b.count == 2 ? min(b[1], file.count - 1) - b[0] + 1 : nil
            }.reduce(0, +)
            #expect(bytesRead < file.count / 2)
        }

        /// An index longer than one window is read whole, in a second request sized to it.
        @Test func aLargeIndexIsReadInFull() async throws {
            let lines = (0..<30_000).map { EBML.Cue(time: UInt64($0) * 300, track: 3) }
            let file = EBML.indexedFile(tracks: [T(type: 17, language: "eng", number: 3)], cues: lines,
                                        mediaBytes: 1000)
            MockURLProtocol.handler = Self.serve(file, log: RangeLog())

            let index = try #require(await probe().index(at: url))

            #expect(index.subtitles.first?.lineEnds.count == 30_000)
        }

        @Test func aFileWithNoIndexHasNone() async {
            let file = EBML.indexedFile(tracks: [T(type: 17, language: "eng", number: 3)], cues: nil)
            MockURLProtocol.handler = Self.serve(file, log: RangeLog())
            #expect(await probe().index(at: url) == nil)
        }

        /// A corrupt size must not turn into a gigabyte download in the middle of a film.
        @Test func anIndexClaimingToBeHugeIsNotRead() async {
            let claimed = EBML.idBytes(MatroskaIndexReader.ID.cues) + EBML.size(1 << 30) + [0xBB, 0x80]
            let file = EBML.indexedFile(tracks: [T(type: 17, language: "eng", number: 3)], cues: [],
                                        cuesPayloadOverride: claimed)
            let log = RangeLog()
            MockURLProtocol.handler = Self.serve(file, log: log)
            #expect(await probe().index(at: url) == nil)
            #expect(log.all.count <= 2)
        }
    }
}
