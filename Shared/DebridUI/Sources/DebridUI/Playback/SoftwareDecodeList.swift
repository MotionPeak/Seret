import Foundation

/// The files whose video the hardware decoder could not keep decoding, so they open decoded in
/// software from the start — see `PlayerModel.recoverFromVideoDecoderFailure`.
///
/// Keyed by `WatchKey.source`: the failure belongs to one file's bitstream, not to a title (its
/// other versions decode fine). Device-local and bounded — a remembered file costs nothing but a
/// little more CPU, and the oldest entries are the least likely to be played again.
@MainActor
public final class SoftwareDecodeList {
    public static let shared = SoftwareDecodeList()
    static let limit = 200
    private static let key = "seret.softwareVideoSources"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func contains(_ sourceKey: String) -> Bool {
        stored.contains(sourceKey)
    }

    func add(_ sourceKey: String) {
        var keys = stored.filter { $0 != sourceKey }
        keys.append(sourceKey)
        defaults.set(Array(keys.suffix(Self.limit)), forKey: Self.key)
    }

    private var stored: [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }
}
