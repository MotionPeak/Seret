#if os(macOS)
import AppKit
import Foundation
import MediaPlayer
import Testing
@testable import DebridUI

/// The macOS twin of the tvOS-hosted `NowPlayingArtworkTests`. MediaPlayer rasterises artwork on its
/// own queue; a handler that inherits main-actor isolation traps there (SIGTRAP — the runner dies).
@Suite struct NowPlayingCenterMacTests {
    @Test func artworkSurvivesBeingRenderedOffTheMainActor() async {
        let artwork = NowPlayingCenter.artwork(for: Self.solidImage())
        let rendered: NSImage? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: artwork.image(at: CGSize(width: 40, height: 40)))
            }
        }
        #expect(rendered != nil)
    }

    @Test func macOSIsToldWhetherWeArePlaying() {
        #expect(NowPlayingCenter.playbackState(rate: 1) == .playing)
        #expect(NowPlayingCenter.playbackState(rate: 1.5) == .playing)
        #expect(NowPlayingCenter.playbackState(rate: 0) == .paused)
    }

    private static func solidImage() -> NSImage {
        NSImage(size: NSSize(width: 60, height: 90), flipped: false) { rect in
            NSColor.darkGray.setFill()
            rect.fill()
            return true
        }
    }
}
#endif
