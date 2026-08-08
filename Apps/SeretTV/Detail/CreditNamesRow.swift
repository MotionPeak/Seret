import DebridCore
import SwiftUI

/// A labelled row of people you can open — "Director: Denis Villeneuve", "Created by: …".
///
/// One control per person rather than one joined string, because each name goes somewhere
/// different. The caller gates on a non-empty list, so the row never appears as a bare label.
struct CreditNamesRow: View {
    let label: String
    let people: [TMDBPersonRef]

    var body: some View {
        HStack(spacing: 16) {
            Text(label)
                .calloutText()
                .foregroundStyle(Theme.Palette.textSecondary)
            ForEach(people) { person in
                NavigationLink(value: BrowseDestination.person(person)) {
                    Text(person.name)
                }
                .buttonStyle(SeretPillStyle(selected: false))
            }
        }
        // Each horizontal row is one target for vertical travel, and a section only counts when
        // its frame intersects the direction of travel — widen to the page, then section.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}

#Preview {
    NavigationStack {
        CreditNamesRow(label: "Director",
                       people: [TMDBPersonRef(id: 137427, name: "Denis Villeneuve")])
            .padding(60)
            .background(CanvasBackground())
    }
}
