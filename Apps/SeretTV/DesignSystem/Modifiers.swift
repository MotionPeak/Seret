import SwiftUI

extension View {
    /// Soft gold bloom behind a view. A `radius` of 0 disables it.
    func goldGlow(_ radius: CGFloat, opacity: Double = 0.5) -> some View {
        shadow(color: Theme.Palette.gold.opacity(radius > 0 ? opacity : 0), radius: radius)
    }
}

/// An image that crossfades in from a dark surface placeholder — no hard pop-in (the #1 source of
/// the "jumpy / loads pages" feel). The default placeholder is an on-brand surface with a gold
/// spinner; pass a custom one (e.g. a titled fallback) when needed. Wrap with `.frame`/`.clipShape`
/// at the call site exactly like `AsyncImage`.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: Theme.Anim.imageFade)) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: contentMode).transition(.opacity)
            } else {
                placeholder()
            }
        }
    }
}

extension RemoteImage where Placeholder == PosterPlaceholder {
    /// Convenience: the standard dark poster/backdrop placeholder.
    init(url: URL?, contentMode: ContentMode = .fill) {
        self.init(url: url, contentMode: contentMode) { PosterPlaceholder() }
    }
}

/// The default loading tile for posters/backdrops — a palette surface + gold spinner, so empty
/// tiles read as "loading" and stay on-brand instead of flashing a raw system grey.
struct PosterPlaceholder: View {
    var body: some View {
        ZStack {
            Theme.Palette.surface2
            ProgressView().tint(Theme.Palette.gold)
        }
    }
}

/// A centered, on-brand loading state (gold spinner + optional label) for full-screen waits.
struct SeretLoader: View {
    var label: String?
    var body: some View {
        VStack(spacing: 20) {
            ProgressView().tint(Theme.Palette.gold).controlSize(.large)
            if let label {
                Text(label).calloutText().foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
