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

    /// Width of the text block, from the mockup.
    static let width: CGFloat = 920

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let subject {
                PreviewHeaderContent(subject: subject, art: art)
                    .id(subject.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8))
                            .animation(Theme.Anim.previewIn.delay(0.18)),
                        removal: .opacity.combined(with: .offset(y: 8))
                            .animation(Theme.Anim.previewOut)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PreviewHeaderContent: View {
    let subject: PreviewSubject
    let art: TitleArt?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PreviewLogo(title: subject.title,
                        url: TMDBClient.imageURL(path: art?.logoPath, size: "w500"))
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
/// The text is never left out while a logo loads — an empty header block is worse than a title
/// that turns into its logo — and the page warms the logo before it switches subjects, so the
/// usual case finds it in the cache and draws the logo on the first frame.
private struct PreviewLogo: View {
    let title: String
    let url: URL?

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
            loaded = await ImageMemoryCache.load(url)
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
            items.append("★ " + vote.formatted(.number.precision(.fractionLength(1))))
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
