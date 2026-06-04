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
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                HStack {
                    Text(model.label).font(.headline)
                    Spacer()
                    Button { onOpenTracks() } label: {
                        Label("Subtitles & Audio", systemImage: "captions.bubble")
                    }
                    .buttonStyle(.bordered)
                }
                HStack(spacing: 12) {
                    Text(timecode(model.position)).font(.caption.monospacedDigit())
                    ProgressView(value: model.duration > 0 ? model.position / model.duration : 0)
                    Text("-" + timecode(max(0, model.duration - model.position)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .background(LinearGradient(colors: [.black.opacity(0.85), .clear],
                                       startPoint: .bottom, endPoint: .top))
        }
    }
    private func timecode(_ s: Double) -> String {
        let t = Int(s), h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
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
