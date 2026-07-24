import XCTest
@testable import SeretServer

final class MediaProbeTests: XCTestCase {
    private func json(container: String, video: String, audio: String) -> Data {
        Data("""
        {"format":{"format_name":"\(container)"},
         "streams":[{"codec_type":"video","codec_name":"\(video)"},
                    {"codec_type":"audio","codec_name":"\(audio)"}]}
        """.utf8)
    }

    private let mp4 = "mov,mp4,m4a,3gp,3g2,mj2"

    func testMp4H264AacIsDirectPlay() throws {
        let p = try MediaProbe.parse(json(container: mp4, video: "h264", audio: "aac"))
        XCTAssertEqual(p.decision, .direct)
    }

    func testMkvTranscodes() throws {
        let p = try MediaProbe.parse(json(container: "matroska,webm", video: "h264", audio: "aac"))
        XCTAssertEqual(p.decision, .transcode)
    }

    func testHevcTranscodes() throws {
        let p = try MediaProbe.parse(json(container: mp4, video: "hevc", audio: "aac"))
        XCTAssertEqual(p.decision, .transcode)
    }

    func testDtsAudioTranscodes() throws {
        let p = try MediaProbe.parse(json(container: mp4, video: "h264", audio: "dts"))
        XCTAssertEqual(p.decision, .transcode)
    }

    func testParsesCodecFields() throws {
        let p = try MediaProbe.parse(json(container: mp4, video: "h264", audio: "aac"))
        XCTAssertEqual(p.videoCodec, "h264")
        XCTAssertEqual(p.audioCodec, "aac")
    }
}
