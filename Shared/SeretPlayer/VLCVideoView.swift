import SwiftUI
import DebridUI

/// Hosts the UIView that `VLCKitVideoPlayerEngine` renders into.
struct VLCVideoView: UIViewRepresentable {
    let videoView: UIView
    func makeUIView(context: Context) -> UIView { videoView }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
