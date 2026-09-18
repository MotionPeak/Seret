import DebridCore
import DebridUI
import SwiftUI

/// Letterboxd import, Apple TV side.
///
/// The username is read-only here on purpose: typing one on a remote is a punishment, and the
/// setting is the same `UserDefaults` key the iPhone writes. Set it there, import from either.
struct LetterboxdCard: View {
    @Bindable var model: LetterboxdImportModel
    let profileID: String?

    private var canImport: Bool {
        model.settings.isEnabled && !model.settings.username.isEmpty && profileID?.isEmpty == false
    }

    var body: some View {
        SettingsCard(title: "Letterboxd", icon: "film.stack") {
            VStack(alignment: .leading, spacing: 12) {
                if model.settings.username.isEmpty {
                    Text("Set your Letterboxd username on your iPhone, in Seret → Settings.")
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Text(model.settings.username)
                        .foregroundStyle(Theme.Palette.textPrimary)
                }

                switch model.phase {
                case .idle:
                    Button("Import Ratings") {
                        Task { await model.importNow(profileID: profileID) }
                    }
                    .buttonStyle(SeretActionButtonStyle())
                    .disabled(!canImport)

                case .running(let done, let total):
                    Text(total > 0 ? "Matching \(done) of \(total)…" : "Reading your profile…")
                        .foregroundStyle(Theme.Palette.textSecondary)

                case .finished(let summary):
                    Text(summary.written == 0
                         ? "Nothing new to fill in"
                         : "Filled in \(summary.written) rating\(summary.written == 1 ? "" : "s")")
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if summary.conflicts > 0 {
                        Text("\(summary.conflicts) rated differently here — kept yours")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Button("Import Again") {
                        Task { await model.importNow(profileID: profileID) }
                    }
                    .buttonStyle(SeretActionButtonStyle())
                    .disabled(!canImport)

                case .failed(let message):
                    Text(message).foregroundStyle(.red)
                    Button("Try Again") {
                        Task { await model.importNow(profileID: profileID) }
                    }
                    .buttonStyle(SeretActionButtonStyle())
                    .disabled(!canImport)
                }
            }
        }
    }
}
