import Foundation

/// Every size the stream cache works to. One value per platform, chosen by the app.
///
/// The numbers are measured, not guessed — see the stream-cache spec: a reconnect to Real-Debrid
/// costs ~460ms, which is what reading a few MB on a live connection costs, hence the 8 MiB wait
/// window; 96 MiB of read-ahead is ~10s of an 80 Mbps remux.
public struct StreamCacheBudget: Sendable, Equatable {
    /// RAM one open file may use: read-ahead plus recent history.
    public var ramBytes: Int
    /// How far ahead of the last read a fetch runs before it is suspended.
    public var readAheadBytes: Int
    public var chunkSize: Int
    /// A fetch that will reach a read within this many bytes is waited for instead of reconnecting.
    public var waitWindowBytes: Int
    /// On a backward miss, how far behind it a second fetch starts, for the demuxer's next steps
    /// back through the file.
    public var lookBehindBytes: Int
    public var maxFetches: Int
    /// Of the chunks read before the first frame (header, keyframe index, resume point), how many
    /// bytes are kept on disk for the next open.
    public var indexHeadBytesPerFile: Int
    public var indexBytesPerFile: Int
    public var indexBytesTotal: Int
    /// The region kept on disk at close, around the last read: where the next resume lands,
    /// including the keyframe before it.
    public var resumeBehindBytes: Int
    public var resumeAheadBytes: Int

    public init(ramBytes: Int, readAheadBytes: Int,
                chunkSize: Int = 1 << 20,
                waitWindowBytes: Int = 8 << 20,
                lookBehindBytes: Int = 8 << 20,
                maxFetches: Int = 2,
                indexHeadBytesPerFile: Int = 8 << 20,
                indexBytesPerFile: Int = 64 << 20,
                indexBytesTotal: Int = 2 << 30,
                resumeBehindBytes: Int = 48 << 20,
                resumeAheadBytes: Int = 8 << 20) {
        self.ramBytes = ramBytes
        self.readAheadBytes = readAheadBytes
        self.chunkSize = chunkSize
        self.waitWindowBytes = waitWindowBytes
        self.lookBehindBytes = lookBehindBytes
        self.maxFetches = maxFetches
        self.indexHeadBytesPerFile = indexHeadBytesPerFile
        self.indexBytesPerFile = indexBytesPerFile
        self.indexBytesTotal = indexBytesTotal
        self.resumeBehindBytes = resumeBehindBytes
        self.resumeAheadBytes = resumeAheadBytes
    }

    /// The Apple TV: playback measured 457 MB on the device, and jetsam never chose Seret at ~830 MB.
    ///
    /// Only a quarter is read-ahead because history is counted back from where libvlc READS, and
    /// libvlc reads ~45 MB ahead of the picture — so a rewind needs the bigger share. Measured in the
    /// tvOS simulator on The Shining: with 96 MiB of read-ahead a −10s rewind missed its keyframe
    /// and took 1.06s from RD; with 48 MiB it lands in 0.14s from RAM, and +10s stays ~0.2s.
    public static let tvOS = StreamCacheBudget(ramBytes: 192 << 20, readAheadBytes: 48 << 20)
    public static let iOS = StreamCacheBudget(ramBytes: 384 << 20, readAheadBytes: 160 << 20)
}
