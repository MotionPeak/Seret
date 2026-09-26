import SwiftUI

#if canImport(UIKit)
import UIKit

/// Hosts the view `VLCKitVideoPlayerEngine` renders into.
///
/// Not called `VLCVideoView`: VLCKit's macOS build exports an Objective-C `VLCVideoView : NSView`,
/// which a local type of the same name would only shadow.
struct VideoSurface: UIViewRepresentable {
    let videoView: UIView
    func makeUIView(context: Context) -> UIView { videoView }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
#else
import AppKit

/// Hosts the view `VLCKitVideoPlayerEngine` renders into (see the UIKit variant for the name).
struct VideoSurface: NSViewRepresentable {
    let videoView: NSView
    func makeNSView(context: Context) -> NSView { videoView }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
