import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

final class FakeLetterboxdSettingsStore: LetterboxdSettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: LetterboxdSettings

    init(_ v: LetterboxdSettings) { value = v }

    func load() -> LetterboxdSettings {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func save(_ s: LetterboxdSettings) {
        lock.lock(); defer { lock.unlock() }
        value = s
    }
}

final class RanFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func set() { lock.lock(); defer { lock.unlock() }; flag = true }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

@MainActor
@Suite struct LetterboxdImportModelTests {
    let summary = LetterboxdImporter.Summary(scanned: 10, needingWork: 4, written: 3,
                                             conflicts: 1, unresolved: 0)

    @Test func aSuccessfulImportEndsFinishedAndStampsTheDate() async {
        let store = FakeLetterboxdSettingsStore(
            LetterboxdSettings(username: "thebigshin", isEnabled: true))
        let model = LetterboxdImportModel(settingsStore: store) { _, progress in
            progress(LetterboxdImporter.Progress(done: 1, total: 4))
            return self.summary
        }
        await model.importNow(profileID: "owner")
        #expect(model.phase == .finished(summary))
        #expect(store.load().lastImportAt != nil)
    }

    @Test func aFailureIsReportedAndDoesNotStampTheDate() async {
        let store = FakeLetterboxdSettingsStore(
            LetterboxdSettings(username: "thebigshin", isEnabled: true))
        let model = LetterboxdImportModel(settingsStore: store) { _, _ in
            throw LetterboxdError.profileUnavailable
        }
        await model.importNow(profileID: "owner")
        if case .failed = model.phase {} else { Issue.record("expected .failed, got \(model.phase)") }
        #expect(store.load().lastImportAt == nil)
    }

    /// The orphan-profile bug: a write under "" is never read back.
    @Test func itRefusesToRunBeforeTheProfileHasResolved() async {
        let store = FakeLetterboxdSettingsStore(
            LetterboxdSettings(username: "thebigshin", isEnabled: true))
        let ran = RanFlag()
        let model = LetterboxdImportModel(settingsStore: store) { _, _ in
            ran.set(); return self.summary
        }
        await model.importNow(profileID: nil)
        #expect(ran.value == false)
        #expect(model.phase == .idle)
    }

    @Test func itRefusesToRunWithoutAUsername() async {
        let store = FakeLetterboxdSettingsStore(LetterboxdSettings(username: "", isEnabled: true))
        let ran = RanFlag()
        let model = LetterboxdImportModel(settingsStore: store) { _, _ in
            ran.set(); return self.summary
        }
        await model.importNow(profileID: "owner")
        #expect(ran.value == false)
    }

    @Test func itRefusesToRunWhenDisabled() async {
        let store = FakeLetterboxdSettingsStore(
            LetterboxdSettings(username: "thebigshin", isEnabled: false))
        let ran = RanFlag()
        let model = LetterboxdImportModel(settingsStore: store) { _, _ in
            ran.set(); return self.summary
        }
        await model.importNow(profileID: "owner")
        #expect(ran.value == false)
    }

    @Test func aProfileUnavailableErrorSaysWhatIsActuallyWrong() {
        let message = LetterboxdImportModel.message(for: LetterboxdError.profileUnavailable)
        #expect(message.lowercased().contains("private") || message.lowercased().contains("gone"))
        // Not a generic "check your connection" — the profile being private is not a network fault.
        #expect(!message.lowercased().contains("connection"))
    }
}

@Suite struct UbiquitousLetterboxdSettingsStoreTests {
    /// iCloud may be unavailable — no account, offline, or a first launch before any sync. The
    /// username still has to work on the device where it was typed.
    @Test func aValueSurvivesWhenICloudHasNothing() {
        let defaults = UserDefaults(suiteName: "lbtest-\(UUID().uuidString)")!
        let store = UbiquitousLetterboxdSettingsStore(local: defaults)
        store.save(LetterboxdSettings(username: "thebigshin", isEnabled: true))
        #expect(store.load().username == "thebigshin")
        #expect(store.load().isEnabled)
    }

    /// The local mirror is written on every save, so the device that typed it never depends on sync.
    @Test func everySaveAlsoLandsInLocalDefaults() {
        let defaults = UserDefaults(suiteName: "lbtest-\(UUID().uuidString)")!
        UbiquitousLetterboxdSettingsStore(local: defaults)
            .save(LetterboxdSettings(username: "thebigshin", isEnabled: true))
        #expect(defaults.data(forKey: "letterboxd.settings") != nil)
    }
}
