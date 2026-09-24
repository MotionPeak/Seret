import DebridCore
import DebridUI
import SwiftUI

extension EnvironmentValues {
    /// One `SearchStore` per window (Decision 4) — two windows must not overwrite each other's
    /// results. `MainShell` builds it once from the session and injects it here; the harness
    /// injects its own the same way.
    @Entry var searchStore: SearchStore? = nil
}

/// The glass search capsule, top-right in every window (mockups 1-A / 2) — not `.searchable` or a
/// real toolbar (Decision 3: a toolbar moves the title bar, exactly where the traffic lights are
/// re-placed). ⌘F focuses it; typing drives `ShellModel.setSearchQuery`, which pushes/pops the
/// `.search` route; Esc clears it and steps back.
struct SearchField: View {
    @Bindable var model: ShellModel

    @FocusState private var focused: Bool

    private var query: Binding<String> {
        Binding(get: { model.searchQuery }, set: { model.setSearchQuery($0) })
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
            TextField("Search films & shows", text: query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.textPrimary)
                .focused($focused)
            trailing
        }
        .padding(.horizontal, 12)
        .frame(width: 280, height: 32)
        .glassEffect(.regular.interactive(), in: Capsule())
        .onChange(of: model.searchFocusRequest) { _, _ in focused = true }
        // A result opened: hand the keyboard to the page (its 1–0 rating keys, Esc, arrows).
        .onChange(of: model.searchBlurRequest) { _, _ in focused = false }
        .onKeyPress(.escape) {
            model.exitSearch()
            focused = false
            return .handled
        }
    }

    @ViewBuilder private var trailing: some View {
        if model.searchQuery.isEmpty {
            if !focused {
                Text("\u{2318}F")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        } else {
            Button { model.exitSearch() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }
}
