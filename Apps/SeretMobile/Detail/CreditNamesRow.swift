import DebridCore
import SwiftUI

/// A labelled row of people you can open — "Dir. Denis Villeneuve", "By David Benioff, …".
///
/// One control per person rather than one joined string, because each name goes somewhere
/// different. It wraps, so a show with four creators does not run off the edge of an iPhone.
/// The caller gates on a non-empty list, so the row never appears as a bare label.
struct CreditNamesRow: View {
    let label: String
    let people: [TMDBPersonRef]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
            Text(label)
                .font(Theme.Typo.body())
                .foregroundStyle(Theme.Palette.textSecondary)
            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                NavigationLink {
                    PersonScreen(ref: person)
                } label: {
                    Text(index == people.count - 1 ? person.name : "\(person.name),")
                        .font(Theme.Typo.body())
                        .foregroundStyle(Theme.Palette.gold)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}
