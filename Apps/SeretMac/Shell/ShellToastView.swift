import SwiftUI

/// One toast for the whole window — a removal, a watchlist change, a mark-watched outcome, all
/// surface through `ShellModel.showToast(_:isFailure:)` instead of each screen growing its own.
struct ShellToastView: View {
    let model: ShellModel
    @Environment(\.pageLeadingInset) private var pageLeadingInset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let toast = model.toast {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    capsule(for: toast)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 28)
            }
            .padding(.leading, pageLeadingInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            .task(id: toast.id) {
                guard let lingers = model.toastLingers else { return }   // nil pins it (harness only)
                try? await Task.sleep(for: lingers)
                model.dismissToast(toast.id)
            }
        }
    }

    private func capsule(for toast: ShellModel.ShellToast) -> some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isFailure ? Theme.Palette.destructive : Theme.Palette.gold)
            Text(toast.message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                // Two lines, not one: a failure's reason comes last ("Couldn't remove “…”. Please
                // try again…") and one line cut exactly that off for any long title.
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: 520)
    }
}
