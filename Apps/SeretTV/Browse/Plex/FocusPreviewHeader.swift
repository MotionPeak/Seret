import DebridCore
import DebridUI
import SwiftUI

/// The top of a browse page: what the focused tile is — its logo (or title), the episode line,
/// a metadata row and two lines of synopsis — laid out like Plex's preview.
///
/// Pure presentation: the page decides WHICH subject and art to show (debounced, so gliding along
/// a rail never re-renders this per tile) and this cross-fades between them — the old text leaves
/// (`previewOut`), then the new rises 8pt into place (`previewIn`).
struct FocusPreviewHeader: View {
    let subject: PreviewSubject?
    let art: TitleArt?
    /// Leave the title slot empty for now: the page is giving the logo a moment to arrive, so a
    /// title does not appear only to be replaced by its logo a beat later. Never longer than the
    /// page's logo budget; everything else in the header shows regardless.
    var holdTitle = false

    /// Width of the text block, from the mockup.
    static let width: CGFloat = 920

    /// Whether a subject was already on screen. The first one (a page appearing, or
    /// `showImmediately` onto an empty header) is drawn at once; only a change of subject fades.
    @State private var hadSubject = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let subject {
                PreviewHeaderContent(subject: subject, art: art, holdTitle: holdTitle)
                    .id(subject.id)
                    .transition(hadSubject ? Self.change : .identity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: subject?.id, initial: true) { _, id in hadSubject = id != nil }
    }

    /// The old text leaves, then the new rises 8pt into place.
    private static let change = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 8)).animation(Theme.Anim.previewIn.delay(0.18)),
        removal: .opacity.combined(with: .offset(y: 8)).animation(Theme.Anim.previewOut))
}

private struct PreviewHeaderContent: View {
    let subject: PreviewSubject
    let art: TitleArt?
    let holdTitle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PreviewLogo(title: subject.title,
                        url: TMDBClient.imageURL(path: art?.logoPath, size: "w500"),
                        holdTitle: holdTitle)
                .frame(height: 170, alignment: .bottomLeading)

            if let episode = subject.episodeLine {
                Text(episode)
                    .font(.seret(32, .bold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .padding(.top, 26)
            }

            let meta = PreviewMeta.items(subject: subject, art: art)
            if !meta.isEmpty {
                HStack(spacing: 18) {
                    ForEach(Array(meta.enumerated()), id: \.offset) { Text($0.element) }
                }
                .font(.seret(23, .medium))
                .foregroundStyle(Theme.Palette.textPrimary.opacity(0.9))
                .lineLimit(1)
                .padding(.top, 14)
            }

            if let overview = subject.overview {
                Text(overview)
                    .font(.seret(25))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.Palette.textPrimary.opacity(0.82))
                    .lineLimit(2)
                    .padding(.top, 14)
            }
        }
        .frame(width: FocusPreviewHeader.width, alignment: .leading)
    }
}

/// The title's logo art, or its name as text until (or unless) the logo can be drawn.
///
/// While a logo is on its way the page may hold the slot empty for a moment (`holdTitle`, at most
/// its 200ms logo budget, which the header's own fade mostly hides). After that the title shows
/// as text, and a logo that arrives later cross-fades in over it — an empty header block is worse
/// than a title that turns into its logo.
private struct PreviewLogo: View {
    let title: String
    let url: URL?
    let holdTitle: Bool

    @State private var loaded: UIImage?

    var body: some View {
        let image = url.flatMap { ImageMemoryCache.shared.object(forKey: $0 as NSURL) } ?? loaded
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 600, maxHeight: 170, alignment: .bottomLeading)
                    .transition(.opacity)
            } else if holdTitle {
                Color.clear
            } else {
                // Leading-aligned and never forced left-to-right: a Hebrew title lays out
                // right-to-left within its line, as it should.
                Text(title)
                    .font(.seret(64, .heavy))
                    .tracking(-1)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                    .frame(width: FocusPreviewHeader.width, alignment: .bottomLeading)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Anim.imageFade, value: image != nil)
        .task(id: url) {
            loaded = nil
            guard let url else { return }
            let image = await ImageMemoryCache.load(url)
            // A cancelled load belongs to a url this view no longer shows.
            guard !Task.isCancelled else { return }
            loaded = image
        }
    }
}

/// The metadata row's items, in order: year · kind · ★ rating · runtime or seasons · time left ·
/// up to two genres. Anything unknown is simply left out.
enum PreviewMeta {
    static func items(subject: PreviewSubject, art: TitleArt?) -> [String] {
        var items: [String] = []
        if let year = subject.year { items.append(String(year)) }
        items.append(subject.kind == .movie ? "Movie" : "Series")
        if let vote = art?.voteAverage, vote > 0 {
            items.append("★ " + vote.formatted(Self.rating))
        }
        switch subject.kind {
        case .movie:
            if let runtime = art?.runtimeMinutes, runtime > 0 { items.append(duration(runtime)) }
        case .show:
            if let seasons = art?.seasonCount, seasons > 0 {
                items.append(seasons == 1 ? "1 Season" : "\(seasons) Seasons")
            }
        }
        if let left = minutesLeft(subject: subject, art: art), left > 0 {
            items.append(duration(left) + " left")
        }
        items.append(contentsOf: (art?.genres ?? []).prefix(2))
        return items
    }

    /// One decimal, always with a point ("8.4", never "8,4" under a comma-decimal region).
    private static let rating = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(1))
        .locale(Locale(identifier: "en_US_POSIX"))

    /// The subject's own figure when it has one; otherwise, for a film part-watched, the share of
    /// the runtime still to go.
    static func minutesLeft(subject: PreviewSubject, art: TitleArt?) -> Int? {
        if let left = subject.remainingMinutes { return left }
        guard subject.kind == .movie, let fraction = subject.fraction, fraction > 0, fraction < 1,
              let runtime = art?.runtimeMinutes, runtime > 0 else { return nil }
        return Int((Double(runtime) * (1 - fraction)).rounded())
    }

    /// "47m", "1h 47m", "2h".
    static func duration(_ minutes: Int) -> String {
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
