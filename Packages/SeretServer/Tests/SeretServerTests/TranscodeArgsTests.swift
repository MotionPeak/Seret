import XCTest
@testable import SeretServer

final class TranscodeArgsTests: XCTestCase {
    func testVaapiArgsShape() {
        let args = TranscodeManager.ffmpegArgs(
            input: "https://rd.example/file.mkv",
            outDir: "/tmp/seret-hls/S1",
            maxHeight: 1080
        )
        // hardware decode + encode, scaled cap, HLS output at the right path
        XCTAssertTrue(args.contains("vaapi"))
        XCTAssertTrue(args.contains("h264_vaapi"))
        XCTAssertTrue(args.contains("https://rd.example/file.mkv"))
        XCTAssertTrue(args.contains("/tmp/seret-hls/S1/index.m3u8"))
        XCTAssertTrue(args.joined(separator: " ").contains("h=min(1080"))
    }
}
