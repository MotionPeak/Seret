import SwiftUI

/// Placeholder for a library section until 8b wires the real adaptive grid.
struct SectionStub: View {
    let section: MainShell.Section

    var body: some View {
        ContentUnavailableView(
            "\(section.title) lands in 8b",
            systemImage: section.icon,
            description: Text("Your \(section.title.lowercased()) library will appear here."))
    }
}
