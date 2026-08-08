import DebridCore
import DebridUI
import SwiftUI

/// An actor or director: who they are, and the work of theirs you can watch.
///
/// Deliberately not a biography. The page exists so that "who was that?" ends in playing something,
/// so every credit is a `BrowseTile` — the same poster tile Search uses, opening the same title
/// page whether or not you already own it.
///
/// Sections are split by role rather than merged, because "what have they been in" and "what have
/// they made" are different questions and one person can answer both.
struct PersonScreen: View {
    let ref: TMDBPersonRef

    @Environment(AppSession.self) private var session
    @Environment(TileWatchMarks.self) private var marks
    @State private var store: PersonStore?

    /// `store` is the seam the DEBUG `-uiPreview person` harness loads through. Production passes
    /// nothing and the session builds one on arrival — navigation only carries a ref.
    init(ref: TMDBPersonRef, store: PersonStore? = nil) {
        self.ref = ref
        _store = State(initialValue: store)
    }

    /// Focus is keyed by credit id, and EVERY tile carries the modifier unconditionally — so no
    /// branch can swap a focused view out from under the focus engine.
    @FocusState private var focusedCredit: String?

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 50)]

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                SeretLoader()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanvasBackground())
        .task {
            if store == nil { store = session.makePersonStore(for: ref) }
            await store?.load()
        }
    }

    @ViewBuilder private func content(_ store: PersonStore) -> some View {
        switch store.state {
        case .idle, .loading:
            SeretLoader(label: "Loading \(store.name)…")
        case .failed(let reason):
            message(reason, systemImage: "exclamationmark.triangle")
        case .empty:
            message("Nothing of \(store.name)'s to show.", systemImage: "film")
        case .loaded:
            loaded(store)
        }
    }

    /// The whole page appears in ONE transition, loader → content. A grid that grows empty → full
    /// under a `ScrollView` collapses its height and back, which snaps the page to the top.
    private func loaded(_ store: PersonStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                header(store)
                if !store.acting.isEmpty {
                    section("As Actor", hits: store.acting)
                }
                if !store.directing.isEmpty {
                    section("As Director", hits: store.directing)
                }
            }
            .padding(60)
        }
        // One batched read for everything on the page, so a title you have already seen says so
        // here too — the same call Search and the genre grids make for their tiles.
        .task(id: firstCreditID(store)) {
            await marks.load(store.acting + store.directing)
        }
        // The first credit sits below the header, off-screen on open. Without this the remote is
        // dead — and an .onAppear focus seed does NOT reliably focus an off-screen element.
        .defaultFocus($focusedCredit, firstCreditID(store))
    }

    /// `.loaded` guarantees at least one section is non-empty, so this always names a real tile.
    private func firstCreditID(_ store: PersonStore) -> String {
        store.acting.first?.id ?? store.directing.first?.id ?? ""
    }

    private func header(_ store: PersonStore) -> some View {
        HStack(alignment: .center, spacing: 40) {
            RemoteImage(url: TMDBClient.imageURL(path: store.profilePath, size: "h632")) {
                Theme.Palette.surface2.overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }
            .frame(width: 240, height: 240)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1) }

            VStack(alignment: .leading, spacing: 12) {
                Text(store.name).screenTitle()
                if let knownFor = store.knownFor {
                    Text(knownFor).calloutText().foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Spacer()
        }
    }

    private func section(_ title: String, hits: [SearchHit]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).sectionTitle()
            LazyVGrid(columns: columns, spacing: 50) {
                ForEach(hits) { hit in
                    BrowseTile(hit: hit)
                        .focused($focusedCredit, equals: hit.id)
                }
            }
        }
        // Widen the focus target to the page BEFORE sectioning: a section only counts when its
        // frame intersects the direction of travel, so a narrow one leaves the outer columns of
        // the grid below with nothing above them.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage).font(.system(size: 64))
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(text).sectionTitle().multilineTextAlignment(.center).frame(maxWidth: 700)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
