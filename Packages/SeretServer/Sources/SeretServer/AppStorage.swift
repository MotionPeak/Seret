import Vapor
import DebridCore

private struct TorrentsClientKey: StorageKey { typealias Value = TorrentsClient }

extension Application {
    var torrents: TorrentsClient {
        get {
            guard let c = storage[TorrentsClientKey.self] else {
                fatalError("TorrentsClient not configured")
            }
            return c
        }
        set { storage[TorrentsClientKey.self] = newValue }
    }
}

private struct TranscodeManagerKey: StorageKey { typealias Value = TranscodeManager }

extension Application {
    var transcoder: TranscodeManager {
        get {
            guard let m = storage[TranscodeManagerKey.self] else {
                fatalError("TranscodeManager not configured")
            }
            return m
        }
        set { storage[TranscodeManagerKey.self] = newValue }
    }
}
