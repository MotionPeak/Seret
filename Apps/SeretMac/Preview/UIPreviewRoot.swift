#if DEBUG
import SwiftUI

/// DEBUG only: `-uiPreview <case>` boots straight into one screen with fixture data, so every screen
/// can be screenshot-verified without signing in or walking the UI (the tvOS lesson). Each task that
/// adds a screen adds its case here.
struct UIPreviewRoot: View {
    let target: String

    var body: some View {
        Group {
            switch target {
            default:
                Text("Unknown -uiPreview case: \(target)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .preferredColorScheme(.dark)
    }
}
#endif
