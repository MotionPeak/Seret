import Foundation

/// The one `Library/Caches/vlc.log` everything writes to: libvlc (through the engine's file
/// logger), the engine's `[seret]` markers, and the stream cache's `[proxy]` lines.
///
/// One handle for all of them: two FileHandles opened on the same file each keep their own write
/// position, and would overwrite each other's lines.
final class DiagnosticsLog: @unchecked Sendable {
    static let shared = DiagnosticsLog()
    private let lock = NSLock()
    private var handle: FileHandle?

    /// Rotate when the file is past its cap, then return the handle to write through. Called once
    /// per player, so every play starts with a size check.
    func prepare() -> FileHandle? {
        lock.lock(); defer { lock.unlock() }
        if let current = handle,
           (try? current.offset()) ?? 0 > VLCKitVideoPlayerEngine.diagnosticsRotateBytes {
            try? current.close()
            handle = nil
        }
        if handle == nil { handle = VLCKitVideoPlayerEngine.openDiagnosticsLog() }
        return handle
    }

    /// One timestamped line.
    func write(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        if handle == nil { handle = VLCKitVideoPlayerEngine.openDiagnosticsLog() }
        try? handle?.write(contentsOf: Data("\(VLCKitVideoPlayerEngine.timestamp()) \(line)\n".utf8))
    }
}
