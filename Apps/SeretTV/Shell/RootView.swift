import SwiftUI
import DebridUI

/// Resolves launch state, then routes between sign-in and the library shell.
struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        switch session.state {
        case .unknown:
            ProgressView()
                .task { await session.resolve() }
        case .signedOut:
            if let model = session.signInModel {
                SignInView(model: model)
            }
        case .signedIn:
            LibraryShell()
        }
    }
}
