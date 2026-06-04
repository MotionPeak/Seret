import UIKit
import TVVLCKit
import DebridCore

/// Adapter from VLCKit to DebridCore's `VideoPlayerEngine`. Fleshed out in Task 2.
@MainActor
final class VLCKitVideoPlayerEngine: NSObject {
    let videoView = UIView()
    private let player = VLCMediaPlayer()

    override init() {
        super.init()
        player.drawable = videoView
    }
}
