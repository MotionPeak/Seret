import SwiftUI

/// An image that cross-fades in from its placeholder, backed by `ImageMemoryCache`. Wrap it with
/// `.frame` and `.clipShape` at the call site exactly like `AsyncImage`.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var loaded: DecodedImage?
    /// The url this view wants now. A task that was already cancelled cannot see it any other way.
    @State private var wanted: URL?
    /// Folded into the `.task` id: only an id change can start another load after a cancellation.
    @State private var attempt = 0

    var body: some View {
        // Synchronous cache check first → no placeholder flash when a page reappears.
        let image = url.flatMap { ImageMemoryCache.shared.object(forKey: $0 as NSURL) } ?? loaded
        return Group {
            if let image {
                Image(decorative: image.cgImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .animation(Theme.Motion.fade, value: image != nil)
        .onChange(of: url, initial: true) { wanted = url; loaded = nil; attempt = 0 }
        .task(id: RemoteImageLoad.Key(url: url, attempt: attempt)) { await load() }
    }

    private func load() async {
        guard let url else { return }
        // Record a cache hit rather than only rendering it: NSCache may evict the entry later, and a
        // tile that merely read it would be left on its placeholder with no load behind it.
        if let hit = ImageMemoryCache.shared.object(forKey: url as NSURL) { loaded = hit; return }
        if let image = await ImageMemoryCache.load(url) { loaded = image; return }
        if RemoteImageLoad.resolve(cancelled: Task.isCancelled, stillWanted: wanted == url,
                                   attempt: attempt) == .retry {
            attempt += 1
        }
    }
}

/// What a load that produced no image means for its tile (port of the iPhone/tvOS logic).
enum RemoteImageLoad {
    struct Key: Equatable { let url: URL?; let attempt: Int }
    enum Resolution: Equatable { case settle, retry, ignore }
    static let maxRetries = 3

    static func resolve(cancelled: Bool, stillWanted: Bool, attempt: Int,
                        maxRetries: Int = maxRetries) -> Resolution {
        guard cancelled else { return .settle }        // the fetch itself failed — that is real
        guard stillWanted else { return .ignore }      // this tile is showing another image now
        return attempt < maxRetries ? .retry : .settle
    }
}

extension RemoteImage where Placeholder == MediaPlaceholder {
    init(url: URL?, contentMode: ContentMode = .fill) {
        self.init(url: url, contentMode: contentMode) { MediaPlaceholder() }
    }
}

/// The standard tile shown while an image loads: a dark surface with a film glyph.
struct MediaPlaceholder: View {
    var body: some View {
        ZStack {
            Theme.Palette.surface2
            Image(systemName: "film").foregroundStyle(Theme.Palette.textTertiary)
        }
    }
}
