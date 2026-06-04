import SwiftUI
import CoreGraphics
import DebridCore

struct LoadingOverlay: View {
    let caption: String
    let title: String
    let backdropURL: URL?
    var body: some View {
        DimBackdrop(url: backdropURL) {
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text(caption).font(.title3)
                Text(title).font(.headline).foregroundStyle(.secondary)
            }
        }
    }
}

struct ErrorOverlay: View {
    let reason: String
    let canTryAnother: Bool
    let backdropURL: URL?
    let onRetry: () -> Void
    let onTryAnother: () -> Void
    let onBack: () -> Void
    var body: some View {
        DimBackdrop(url: backdropURL) {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 54))
                Text("Couldn't play this source").font(.title2.bold())
                Text(reason).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 800)
                HStack(spacing: 24) {
                    Button("Retry", action: onRetry)
                    if canTryAnother { Button("Try another version", action: onTryAnother) }
                    Button("Back", action: onBack)
                }
            }
        }
    }
}

struct TransportOverlay: View {
    @Bindable var model: PlayerModel
    let onOpenTracks: () -> Void
    @Namespace private var focusScope

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            HStack {
                Text(model.label).font(.title3.bold())
                Spacer()
                // Click up from the scrubber to reach this; press to open the Subtitles & Audio panel.
                Button { model.showControls(); onOpenTracks() } label: {
                    Label("Subtitles & Audio", systemImage: "captions.bubble")
                }
                .buttonStyle(.bordered)
            }
            .opacity(model.isScrubbing ? 0 : 1)   // clear the way for the preview window while scrubbing
            // Scrubber. The focusable ScrubPad (a UIView) sits over the bar visuals and receives the
            // remote's trackpad swipes: a horizontal swipe glides a fast preview across the whole clip
            // and lifting seeks there. Click up to reach the Subtitles button.
            ScrubBar(model: model)
                .overlay {
                    ScrubPad(model: model)
                        .prefersDefaultFocus(in: focusScope)   // land here when controls appear
                }
        }
        .padding(48)
        .background(LinearGradient(colors: [.black.opacity(0.9), .clear],
                                   startPoint: .bottom, endPoint: .top))
        .focusScope(focusScope)
    }
}

/// The progress bar. Grows + shows a timecode preview bubble when the scrub surface is focused.
private struct ScrubBar: View {
    @Bindable var model: PlayerModel

    var body: some View {
        // While scrubbing (or merely focused on the ScrubPad overlay), the bar follows the preview
        // marker and shows the tall/bubble treatment.
        let active = model.scrubberFocused || model.isScrubbing
        let shown = model.isScrubbing ? model.scrubTarget : model.position
        let frac = model.duration > 0 ? min(1, max(0, shown / model.duration)) : 0
        let previewWidth: CGFloat = 240
        VStack(spacing: 10) {
            GeometryReader { geo in
                let headX = geo.size.width * frac
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: active ? 10 : 6)
                    Capsule().fill(.white).frame(width: headX, height: active ? 10 : 6)
                    if active {
                        // The scrubber head.
                        Circle().fill(.white).frame(width: 22, height: 22)
                            .offset(x: min(geo.size.width - 22, max(0, headX - 11)))
                    }
                    if model.isScrubbing {
                        // Frame-preview window centered above the scrubber head.
                        ScrubPreview(image: model.scrubPreviewImage, time: shown, width: previewWidth)
                            .offset(x: max(0, min(geo.size.width - previewWidth, headX - previewWidth / 2)), y: -120)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 44)
            HStack {
                Text(Timecode.format(shown)).font(.caption.monospacedDigit())
                Spacer()
                Text("-" + Timecode.format(max(0, model.duration - shown)))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

/// The scrub preview window: a 16:9 video frame (best-effort) with the target time overlaid,
/// or a spinner while the frame is being fetched.
private struct ScrubPreview: View {
    let image: CGImage?
    let time: Double
    let width: CGFloat
    private var height: CGFloat { width * 9 / 16 }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack { Color.black.opacity(0.7); ProgressView().controlSize(.small) }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.3), lineWidth: 1))
        .overlay(alignment: .bottom) {
            Text(Timecode.format(time))
                .font(.callout.monospacedDigit().bold())
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.black.opacity(0.65), in: Capsule())
                .padding(8)
        }
        .shadow(radius: 12)
    }
}

private struct DimBackdrop<Content: View>: View {
    let url: URL?
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Color.black
            if let url { AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear } }
            Color.black.opacity(0.7)
            content
        }
        .ignoresSafeArea()
    }
}
