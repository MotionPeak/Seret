import SwiftUI

/// What a section shows until its phase builds it (M2 replaces these with the real screens). Pads
/// itself by the sidebar clearance — `MainShell` no longer pads pages, so full-bleed art can run
/// under the sidebar once a page needs to.
struct SectionPlaceholder: View {
    let section: SidebarSection
    @Environment(\.pageLeadingInset) private var pageLeadingInset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title).font(.system(size: 34, weight: .heavy))
            Text("Arrives in the next phase.").font(Theme.Typo.body())
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 54)
        .padding(.leading, pageLeadingInset)
        .padding(.trailing, 28)
    }
}
