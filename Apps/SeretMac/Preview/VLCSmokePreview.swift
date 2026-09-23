#if DEBUG
import DebridCore
import SwiftUI

/// `-uiPreview vlcsmoke [-smokeURL <url>]` — plays a real stream through `VLCKitVideoPlayerEngine`
/// into an AppKit view and shows its state and clock. VLCKit on macOS is the biggest risk in the Mac
/// app; this retires it before any player UI exists. The default stream is Apple's public HLS
/// example, which needs no account; pass `-smokeURL` to try anything else.
struct VLCSmokePreview: View {
    /// Built once, in `.task` — never as a `@State` default, which would construct a libvlc
    /// instance on every re-render (a crash this codebase has already had).
    @State private var engine: VLCKitVideoPlayerEngine?
    @State private var status = "loading"
    let url: URL

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if let engine { VideoSurface(videoView: engine.videoView) }
            Text(status)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                .padding(16)
        }
        .task {
            let engine = VLCKitVideoPlayerEngine()
            self.engine = engine
            engine.load(url: url, headers: [:], audioLanguage: nil, audioTrackID: nil)
            engine.play()
            for await event in engine.events {
                switch event {
                case .state(let state): status = "state \(state)"
                case .time(let time): status = String(format: "playing %.1f of %.1f s", time.position, time.duration)
                case .tracksChanged: continue
                }
                print("[vlcsmoke] \(status)")
            }
        }
        .onDisappear { engine?.stop() }
    }

    // `nonisolated`: `View` conformance infers `@MainActor` for the whole type, but these are pure
    // and `VLCSmokePreviewTests` calls them from ordinary (non-`@MainActor`) `@Test` functions —
    // without this they only compile with a same-actor-context warning at each call site.
    nonisolated static let defaultURL = URL(string:
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8")!

    nonisolated static func url(from arguments: [String]) -> URL {
        guard let index = arguments.firstIndex(of: "-smokeURL"), index + 1 < arguments.count,
              let url = URL(string: arguments[index + 1]) else { return defaultURL }
        return url
    }
}
#endif
