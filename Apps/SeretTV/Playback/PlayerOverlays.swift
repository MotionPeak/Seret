import SwiftUI
import DebridUI
import DebridCore

struct LoadingOverlay: View {
    let caption: String
    let title: String
    let backdropURL: URL?
    var body: some View {
        DimBackdrop(url: backdropURL) {
            VStack(spacing: 18) {
                ProgressView().controlSize(.large).tint(Theme.Palette.textPrimary)
                Text(caption)
                    .font(.seret(30, .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(title)
                    .font(.seret(24, .medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
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
            VStack(spacing: 22) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Couldn't play this source")
                    .font(.seret(40, .bold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(reason)
                    .font(.seret(25, .regular))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 800)
                HStack(spacing: 22) {
                    Button("Retry", action: onRetry)
                        .buttonStyle(SeretActionButtonStyle(prominent: true))
                    if canTryAnother {
                        Button("Try another version", action: onTryAnother)
                            .buttonStyle(SeretActionButtonStyle())
                    }
                    Button("Back", action: onBack)
                        .buttonStyle(SeretActionButtonStyle())
                }
                .padding(.top, 12)
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
            // RemoteImage (not AsyncImage): keeps the decoded backdrop in ImageMemoryCache so a
            // retry or an episode-swap reload doesn't re-fetch and re-decode it — the flash 40387ee
            // removed everywhere else in the app.
            if let url { RemoteImage(url: url, contentMode: .fill) { _ in Color.clear } }
            Color.black.opacity(0.72)
            content
        }
        .ignoresSafeArea()
    }
}
