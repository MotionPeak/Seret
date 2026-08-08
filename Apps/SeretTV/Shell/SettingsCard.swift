import SwiftUI
import DebridUI

/// One settings section.
///
/// Every section on the screen is one of these, at one width and one left edge. That uniformity is
/// the point: the screen previously mixed carded sections at 700pt with uncarded ones at 900pt, so
/// headings started at different x positions down the page and the whole thing read as unfinished.
struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    static var width: CGFloat { 1180 }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(title, systemImage: icon)
                .font(.seret(.title3, .bold))
                .foregroundStyle(Theme.Palette.gold)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(36)
        .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: 28))
        .frame(width: Self.width, alignment: .leading)
        // Each card is its own focus target, so DOWN between cards is unambiguous rather than
        // depending on which control happens to sit nearest the travel rectangle.
        .focusSection()
    }
}

/// Secondary explanatory text. One definition so every caption on the screen matches.
extension View {
    func settingsCaption() -> some View {
        font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
    }
}

/// A one-line state readout — connected, syncing, on-device-only.
struct SettingsStatus: View {
    let text: String
    let good: Bool

    var body: some View {
        Label(text, systemImage: good ? "checkmark.circle.fill" : "circle.dashed")
            .font(.seret(.callout, .semibold))
            .foregroundStyle(good ? Theme.Palette.gold : Theme.Palette.textSecondary)
    }
}
