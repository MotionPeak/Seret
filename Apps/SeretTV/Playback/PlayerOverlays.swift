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
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                HStack {
                    Text(model.label).font(.headline)
                    Spacer()
                    // Visual hint only — a focusable button here would steal focus and break
                    // swipe-to-skip. The panel opens via swipe-down (onMoveCommand .down).
                    Label("Swipe down for Subtitles & Audio", systemImage: "captions.bubble")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Text(Timecode.format(model.position)).font(.caption.monospacedDigit())
                    ProgressView(value: model.duration > 0 ? model.position / model.duration : 0)
                    Text("-" + Timecode.format(max(0, model.duration - model.position)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .background(LinearGradient(colors: [.black.opacity(0.85), .clear],
                                       startPoint: .bottom, endPoint: .top))
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
