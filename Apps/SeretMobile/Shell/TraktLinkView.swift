import SwiftUI
import DebridUI
import DebridCore

/// Device-code link screen for Trakt, pushed from Settings. Trakt is the watch-state source of
/// truth (watched history, resume position, ratings), so until a device links, Detail shows "Play"
/// instead of "Resume" and Continue Watching stays empty.
struct TraktLinkView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var model: TraktAuthModel?

    var body: some View {
        List {
            Section {
                switch model?.phase {
                case .awaiting(let code):
                    VStack(alignment: .leading, spacing: 12) {
                        Text("On any device, open").font(.footnote)
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Text(displayURL(code.verificationURL))
                            .font(.headline).foregroundStyle(Theme.Palette.textPrimary)
                        Text("and enter this code:").font(.footnote)
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Text(code.userCode)
                            .font(.system(.largeTitle, design: .monospaced).weight(.heavy))
                            .textSelection(.enabled)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Button("Open trakt.tv to enter it") {
                            if let url = URL(string: code.verificationURL) { openURL(url) }
                        }
                        .tint(Theme.Palette.gold)
                        Label("Waiting for authorization…", systemImage: "hourglass")
                            .font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    .padding(.vertical, 4)
                case .failed(let message):
                    Text(message).foregroundStyle(Theme.Palette.textSecondary)
                    Button("Try Again") { model?.retry() }.tint(Theme.Palette.gold)
                case .linked:
                    Label("Linked!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Palette.gold)
                default:
                    Label("Contacting Trakt…", systemImage: "hourglass")
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            } header: {
                Text("Link Trakt").foregroundStyle(Theme.Palette.gold)
            } footer: {
                Text("Syncs your watched history, resume position, and ratings across every device.")
                    .font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
            }
            .listRowBackground(Theme.Palette.surface1)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.canvas.ignoresSafeArea())
        .navigationTitle("Trakt")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if model == nil { model = session.makeTraktAuthModel() } }
        .task(id: model?.attempt) {
            guard let model else { return }
            await model.run()
            if case .linked = model.phase { dismiss() }
        }
    }

    private func displayURL(_ raw: String) -> String {
        raw.replacingOccurrences(of: "https://", with: "")
           .replacingOccurrences(of: "http://", with: "")
    }
}
