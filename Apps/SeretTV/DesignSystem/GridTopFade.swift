import SwiftUI

extension View {
    /// Fades a scroll view's top band into the canvas, so a row crossing the top edge dissolves
    /// instead of being cut in half.
    ///
    /// Every grid in the app scrolls under a pinned header (the Movies/Shows pills, the genre
    /// strip). A raw `ScrollView` clips at its bounds, which reads as a rendering bug: half a
    /// poster, hard-edged, flush against the header.
    ///
    /// The gradient is deliberately **vertical only and full width**. A horizontal component would
    /// dim the outermost posters in every row and clip their focus scale — the same edge-clipping
    /// the rails already work around with negative horizontal padding.
    ///
    /// `height` is the fade band in points, measured from the top. 100pt was chosen against the
    /// `-uiPreview gridfade` harness: it dissolves roughly the top third of a 330pt poster, which
    /// reads as a soft edge rather than a dimmed row. A focused row is always fully scrolled into
    /// view, so it is never touched.
    func gridTopFade(_ height: CGFloat = 100) -> some View {
        mask {
            GeometryReader { geo in
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: min(1, height / max(geo.size.height, 1))),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
        }
    }
}
