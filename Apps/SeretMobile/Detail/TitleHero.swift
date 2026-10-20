import DebridCore
import DebridUI
import SwiftUI

/// What the action row's Trailer circle can do — the hero owns the trailer, the row only asks.
struct TrailerAction {
    /// A trailer exists: a stream to play in-app, or at least a YouTube key to hand over.
    let isAvailable: Bool
    let play: () -> Void
}

/// The title page's measurements, shared by the movie and show pages so they line up.
enum TitlePageMetrics {
    /// The page's leading text edge — the same line Home and the browse rails use.
    static func margin(regular: Bool) -> CGFloat { regular ? 40 : Theme.Space.xl }
    /// The sections under the hero stay a readable column on iPad rather than a stretched phone
    /// page (audit: 780pt version rows).
    static let readableWidth: CGFloat = 900
    /// iPad: the left-hand preview over the art.
    static let regularInfoWidth: CGFloat = 520
    /// The art's height as a share of the visible page, and its iPad ceiling.
    static func artHeight(_ container: CGFloat, regular: Bool) -> CGFloat {
        regular ? min(container * 0.74, 720) : container * 0.62
    }
}

/// The top of a title page, both layouts (g3):
///
/// - **compact** (iPhone) — full-bleed art under the status bar and the glass navigation bar,
///   fading into the canvas; over its foot the logo (else the name), the metadata row and the chips;
///   then, on the canvas, the white Play pill and the row of labelled glass circles.
/// - **regular** (iPad) — the art runs the page's width; logo, metadata, chips, Play and the circles
///   sit on the LEFT over a leading shade, the way the Apple TV and Home's iPad hero do. Not a
///   stretched phone column.
///
/// About four seconds in, the art cross-fades to the muted, looping trailer when autoplay is on
/// (Settings), as the old banner did; tapping the art — or the Trailer circle — plays it full-screen
/// with sound. The hero owns that model, so the page never resolves a trailer twice.
struct TitleHero<Info: View, Buttons: View>: View {
    let tmdbID: Int?
    let kind: MediaKind
    let backdropPath: String?
    let posterFallback: String?
    let regular: Bool
    @ViewBuilder let info: Info
    @ViewBuilder let buttons: (TrailerAction) -> Buttons

    @Environment(AppSession.self) private var session
    @State private var model: TrailerModel?
    @State private var showVideo = false
    @State private var muted = true
    @State private var expand = false

    var body: some View {
        Group {
            if regular { regularLayout } else { compactLayout }
        }
        .task(id: tmdbID) { await prepare() }
        .onDisappear { showVideo = false }
        .fullScreenCover(isPresented: $expand) { trailerCover }
    }

    // MARK: Layouts

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 22) {
            ZStack(alignment: .bottomLeading) {
                art(leadingShade: false)
                    .containerRelativeFrame(.vertical) { h, _ in
                        TitlePageMetrics.artHeight(h, regular: false)
                    }
                info
                    .padding(.horizontal, TitlePageMetrics.margin(regular: false))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            buttons(trailerAction)
                .padding(.horizontal, TitlePageMetrics.margin(regular: false))
        }
    }

    private var regularLayout: some View {
        ZStack(alignment: .bottomLeading) {
            art(leadingShade: true)
                .containerRelativeFrame(.vertical) { h, _ in
                    TitlePageMetrics.artHeight(h, regular: true)
                }
            VStack(alignment: .leading, spacing: 20) {
                info
                buttons(trailerAction)
            }
            .frame(maxWidth: TitlePageMetrics.regularInfoWidth, alignment: .leading)
            .padding(.leading, TitlePageMetrics.margin(regular: true))
            .padding(.trailing, Theme.Space.xl)
            .padding(.bottom, Theme.Space.xl)
        }
    }

    // MARK: Art

    private func art(leadingShade: Bool) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .overlay { backdrop }
            .overlay {
                if showVideo, let url = model?.streamURL {
                    InlineMutedTrailer(url: url, muted: $muted).transition(.opacity)
                }
            }
            .clipped()
            .overlay { fade }
            .overlay {
                if leadingShade {
                    LinearGradient(stops: [.init(color: Theme.Palette.canvas.opacity(0.78), location: 0),
                                           .init(color: Theme.Palette.canvas.opacity(0.35), location: 0.42),
                                           .init(color: .clear, location: 0.75)],
                                   startPoint: .leading, endPoint: .trailing)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if model?.streamURL != nil { expand = true } }
            .overlay(alignment: regular ? .topTrailing : .trailing) {
                if showVideo { trailerControls }
            }
            .animation(.easeInOut(duration: 0.6), value: showVideo)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var backdrop: some View {
        if let url = TMDBClient.imageURL(path: backdropPath, size: "w1280")
            ?? TMDBClient.imageURL(path: posterFallback, size: "w780") {
            RemoteImage(url: url) { Theme.Palette.surface1 }
        } else {
            LinearGradient(colors: [Theme.Palette.surface1, Theme.Palette.canvas],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    /// A shade at the top so the status bar and the glass bar buttons read over bright art, then a
    /// long fade into the canvas under the logo and chips — the art never ends in a hard edge.
    private var fade: some View {
        LinearGradient(stops: [
            .init(color: Theme.Palette.shadeInk.opacity(0.45), location: 0),
            .init(color: .clear, location: 0.22),
            .init(color: .clear, location: 0.40),
            .init(color: Theme.Palette.canvas.opacity(0.70), location: 0.72),
            .init(color: Theme.Palette.canvas, location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .allowsHitTesting(false)
    }

    /// Mute and full-screen, while the inline trailer plays.
    private var trailerControls: some View {
        GlassGroup(spacing: 6) {
            VStack(spacing: 10) {
                GlassCircleButton(systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                  label: muted ? "Unmute Trailer" : "Mute Trailer", size: 38) {
                    muted.toggle()
                }
                GlassCircleButton(systemImage: "arrow.up.left.and.arrow.down.right",
                                  label: "Play Trailer Full Screen", size: 38) { expand = true }
            }
        }
        .padding(.trailing, Theme.Space.lg)
        .padding(.top, regular ? 96 : 0)
        .transition(.opacity)
    }

    // MARK: Trailer

    private var trailerAction: TrailerAction {
        TrailerAction(isAvailable: model?.streamURL != nil || model?.youTubeKey != nil,
                      play: { expand = true })
    }

    @ViewBuilder private var trailerCover: some View {
        if let url = model?.streamURL {
            FullScreenTrailer(url: url)
        } else {
            // Extraction failed but there is a key: hand over to YouTube, then close again.
            Color.black.ignoresSafeArea()
                .onAppear {
                    if let key = model?.youTubeKey,
                       let url = URL(string: "https://www.youtube.com/watch?v=\(key)") {
                        UIApplication.shared.open(url)
                    }
                    expand = false
                }
        }
    }

    private func prepare() async {
        guard let tmdbID, model == nil, let m = session.makeTrailerModel() else { return }
        model = m
        async let delay: () = Task.sleep(for: .seconds(4))
        await m.prepare(tmdbID: tmdbID, kind: kind)
        try? await delay
        guard m.autoplayAllowed, !Task.isCancelled else { return }
        showVideo = true
    }
}

// MARK: - Pieces

/// The hero's metadata row — "2016  1h 42m  ★ 7.3  Western · Crime" — wrapping rather than
/// truncating at large text sizes. A part starting with "★" is drawn as the star rating.
struct TitleMetaRow: View {
    let parts: [String]

    var body: some View {
        FlowLayout(spacing: 12) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if part.hasPrefix("★") {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.system(size: 13))
                        Text(part.dropFirst())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Rated \(part.dropFirst()) out of 10")
                } else {
                    Text(part)
                }
            }
        }
        .font(.system(size: 16, weight: .medium).monospacedDigit())
        .foregroundStyle(Theme.Palette.textPrimary.opacity(0.88))
        .shadow(color: .black.opacity(0.45), radius: 6)
    }

    static func rating(_ value: Double?) -> String? {
        value.flatMap { $0 > 0 ? String(format: "★%.1f", $0) : nil }
    }

    /// "1h 42m", "45m", "2h".
    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

/// The overview, capped at four lines with a "More" that opens it in place — for shows too, whose
/// synopsis used to be cut at four lines with no way to read the rest (audit parity gap).
struct ExpandableOverview: View {
    let text: String
    var lineLimit = 4
    @State private var expanded = false
    @State private var truncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Palette.textPrimary.opacity(0.85))
                .lineSpacing(3)
                .lineLimit(expanded ? nil : lineLimit)
                .background {
                    // The same text unconstrained, measured off-screen: "More" only when there IS more.
                    Text(text).font(.system(size: 16)).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full in
                            truncated = full > CGFloat(lineLimit) * 24 + 2
                        }
                }
            if truncated {
                Button(expanded ? "Less" : "More") {
                    withAnimation(Theme.Motion.standard) { expanded.toggle() }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A section's heading under the hero: title-case white, as the rails on Home.
struct TitleSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.Typo.railTitle())
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Space.md)
            trailing
        }
    }
}

extension TitleSectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// The action row: labelled glass circles spread across the width on iPhone (g3), packed to the
/// left under the Play pill on iPad.
struct TitleActionRow<Content: View>: View {
    let regular: Bool
    @ViewBuilder var content: Content

    var body: some View {
        GlassGroup(spacing: 8) {
            if regular {
                HStack(alignment: .top, spacing: Theme.Space.xl) { content }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    // Spread, not packed: five circles fill an iPhone's width as g3 draws them,
                    // and three still sit evenly rather than huddling left.
                    Group { content }.frame(maxWidth: .infinity)
                }
            }
        }
    }
}

extension View {
    /// The page under the hero: a readable column on iPad, the page margin on iPhone.
    func titleColumn(regular: Bool) -> some View {
        self
            .frame(maxWidth: regular ? TitlePageMetrics.readableWidth : .infinity, alignment: .leading)
            .padding(.horizontal, TitlePageMetrics.margin(regular: regular))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Reports whether the page has scrolled past the top of the hero's info — the moment the glass
    /// navigation bar takes the title and (on iOS 18) a frosted background.
    func titlePageScroll(_ scrolled: Binding<Bool>) -> some View {
        onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top > geo.containerSize.height * 0.25
        } action: { _, past in
            scrolled.wrappedValue = past
        }
    }
}

extension View {
    /// The title page's navigation bar: never a painted background — the art runs under it at
    /// rest, and DetailScreen's shade takes over once the page scrolls. iOS 26 draws the buttons on
    /// Liquid Glass; iOS 18 gets the toolkit's glass circles (`ToolbarGlassIcon`).
    @ViewBuilder
    func titlePageBar() -> some View {
        if #available(iOS 26, *), !GlassSupport.forceFallback {
            self
        } else {
            toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
