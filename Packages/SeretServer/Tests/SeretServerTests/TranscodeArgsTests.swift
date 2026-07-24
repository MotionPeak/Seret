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

    /// Regression: 10-bit HEVC decodes to P010, but h264_vaapi on Gemini Lake only encodes 8-bit.
    /// Without an explicit nv12 conversion in the scaler, ffmpeg dies with
    /// "No usable encoding profile found" on every 2160p Main10 REMUX.
    func testScalerForcesEightBitNV12() {
        let args = TranscodeManager.ffmpegArgs(
            input: "https://rd.example/uhd.mkv", outDir: "/tmp/seret-hls/S2", maxHeight: 1080)
        let vf = args[(args.firstIndex(of: "-vf")! + 1)]
        XCTAssertTrue(vf.contains("format=nv12"), "scale_vaapi must output 8-bit nv12, got: \(vf)")
    }
}
