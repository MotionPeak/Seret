import Foundation
import DebridCore

/// What running an import looks like to a view. Injected so the model is testable without a
/// network or a database.
public typealias LetterboxdImportRunning =
    @Sendable (_ profileID: String,
               _ onProgress: @Sendable @escaping (LetterboxdImporter.Progress) -> Void)
    async throws -> LetterboxdImporter.Summary

/// Drives an import for a view, and refuses to start one that would write somewhere useless.
@MainActor
@Observable
public final class LetterboxdImportModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case running(done: Int, total: Int)
        case finished(LetterboxdImporter.Summary)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    public var settings: LetterboxdSettings

    private let settingsStore: any LetterboxdSettingsStoring
    private let run: LetterboxdImportRunning

    public init(settingsStore: any LetterboxdSettingsStoring, run: @escaping LetterboxdImportRunning) {
        self.settingsStore = settingsStore
        self.run = run
        self.settings = settingsStore.load()
    }

    public func update(_ settings: LetterboxdSettings) {
        self.settings = settings
        settingsStore.save(settings)
    }

    public func importNow(profileID: String?) async {
        // A nil or empty profile means profiles have not resolved yet. Writing under "" produces
        // rows nothing ever reads back — that exact orphan made resume look broken for a day.
        guard let profileID, !profileID.isEmpty else { return }
        guard settings.isEnabled, !settings.username.isEmpty else { return }
        if case .running = phase { return }           // one at a time
        await start(profileID: profileID)
    }

    private func start(profileID: String) async {
        phase = .running(done: 0, total: 0)
        do {
            let summary = try await run(profileID) { [weak self] progress in
                Task { @MainActor in
                    guard let self, case .running = self.phase else { return }
                    self.phase = .running(done: progress.done, total: progress.total)
                }
            }
            phase = .finished(summary)
            var updated = settings
            updated.lastImportAt = Date()
            update(updated)
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    /// Names the actual fault. A private profile is not a network problem and should not be
    /// reported as one — the owner would go looking in the wrong place.
    static func message(for error: any Error) -> String {
        switch error {
        case LetterboxdError.profileUnavailable:
            return "That Letterboxd profile is private, renamed or gone."
        case LetterboxdError.structureChanged:
            return "Letterboxd changed its page layout — the import needs updating."
        default:
            return "Import failed. Check your connection and try again."
        }
    }
}
