import SwiftUI

/// Full-screen "preparing / buffering" overlay over a dimmed backdrop (initial load only).
struct LoadingOverlay: View {
    let caption: String
    let title: String
    let backdropURL: URL?
    var body: some View {
        DimBackdrop(url: backdropURL) {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(.white)
                Text(caption).font(.headline)
                Text(title).font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
        }
    }
}

/// Playback-failure overlay: Retry / Try another version / Back.
struct ErrorOverlay: View {
    let reason: String
    let canTryAnother: Bool
    let backdropURL: URL?
    let onRetry: () -> Void
    let onTryAnother: () -> Void
    let onBack: () -> Void
    var body: some View {
        DimBackdrop(url: backdropURL) {
            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 48))
                Text("Couldn't play this source").font(.title2.bold())
                Text(reason).font(.callout).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                HStack(spacing: 14) {
                    Button("Retry", action: onRetry).buttonStyle(.borderedProminent)
                    if canTryAnother { Button("Try another", action: onTryAnother).buttonStyle(.bordered) }
                    Button("Back", action: onBack).buttonStyle(.bordered)
                }
                .tint(.white)
            }
            .foregroundStyle(.white)
            .padding()
        }
    }
}

private struct DimBackdrop<Content: View>: View {
    let url: URL?
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Color.black
            if let url {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
            }
            Color.black.opacity(0.7)
            content
        }
        .ignoresSafeArea()
    }
}
