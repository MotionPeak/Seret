import AVKit
import DebridUI
import SwiftUI

/// The full-window "Watch Trailer" presentation, a shell overlay like playback rather than a
/// window or sheet: `AVPlayerView` with native floating controls and sound, over black. Esc or the
/// glass ✕ (placed like the player's own back button) close it.
struct TrailerOverlay: View {
    let presentation: ShellModel.TrailerPresentation
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            AVPlayerViewRepresentable(url: presentation.url)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(width: 32, height: 32)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, PlayerHUDMetrics.topBarLeadingWindowed)
            .padding(.top, PlayerHUDMetrics.topBarTop)
        }
        .onExitCommand(perform: onClose)
        .onKeyPress(.escape) { onClose(); return .handled }
    }
}

/// `AVPlayerView` (`.floating` controls), full sound, torn down on dismantle.
private struct AVPlayerViewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        let player = AVPlayer(url: url)
        player.isMuted = false
        view.player = player
        player.play()
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}
