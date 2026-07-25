import Testing
import Foundation
import UIKit
import MediaPlayer
@testable import DebridUI

/// Guards the crash-on-entering-any-title regression (fixed in `4712bd6`).
///
/// MediaPlayer rasterises Now Playing artwork on its OWN private queue — `-[MPMediaItemArtwork
/// jpegDataWithSize:]`, reached from `-[MPNowPlayingInfoCenter _onQueue_pushNowPlayingInfoAndRetry:]`.
/// If the `requestHandler` closure carries `@MainActor` isolation (which it does *by inference* when
/// it is written inside a `@MainActor` type), Swift injects an isolation check that calls
/// `dispatch_assert_queue(main)`. Off the main queue that check fails and the process dies with
/// SIGTRAP in `_dispatch_assert_queue_fail` — which is what shipped, killing the app a few seconds
/// into every title, the moment the poster finished downloading.
///
/// **Why this lives here and not in `swift test`:** `NowPlayingCenter` sits behind
/// `#if canImport(MediaPlayer) && canImport(UIKit)`, so it is not compiled at all in the macOS
/// package test build, and `NowPlayingTests` only exercises `PlayerModel` against a *fake*
/// `NowPlayingControlling`. 262 green package tests said nothing about a crash on every title.
/// Platform-framework glue has to be tested on the platform.
///
/// **How this fails:** against unfixed code it does not report a failure — it CRASHES the test
/// runner (SIGTRAP is not catchable in-process). A dead runner is the signal.
@Suite struct NowPlayingArtworkTests {

    /// The exact call MediaPlayer makes, from the kind of queue MediaPlayer makes it on.
    @Test func artworkRequestHandlerSurvivesBeingCalledOffTheMainActor() async {
        let source = Self.solidImage()
        let artwork = NowPlayingCenter.artwork(for: source)

        let rendered: UIImage? = await withCheckedContinuation { continuation in
            // Deliberately NOT the main queue: this is what `*/accessQueue` looked like in the
            // crash report. With a main-actor-isolated handler this line traps.
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: artwork.image(at: CGSize(width: 40, height: 40)))
            }
        }

        #expect(rendered != nil, "MediaPlayer must be able to rasterise the artwork off-main")
    }

    /// The handler must also survive the main actor — the fix must not merely move the crash.
    @Test @MainActor func artworkRequestHandlerAlsoWorksOnTheMainActor() {
        let artwork = NowPlayingCenter.artwork(for: Self.solidImage())
        #expect(artwork.image(at: CGSize(width: 40, height: 40)) != nil)
    }

    /// A tiny opaque image — `UIImage(systemName:)` can be nil in a test host, and a zero-size
    /// image makes `image(at:)` unreliable for reasons unrelated to isolation.
    private static func solidImage() -> UIImage {
        let size = CGSize(width: 60, height: 90)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
