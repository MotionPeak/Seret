import SwiftUI
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
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: active ? 12 : 6)
                    Capsule().fill(.white).frame(width: geo.size.width * frac, height: active ? 12 : 6)
                    if active {
                        Text(Timecode.format(shown))
                            .font(.callout.monospacedDigit().bold())
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .offset(x: max(0, min(geo.size.width - 80, geo.size.width * frac - 40)), y: -42)
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
