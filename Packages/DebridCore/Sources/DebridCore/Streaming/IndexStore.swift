import Foundation

/// What the disk holds for one file: its size and which chunks.
struct IndexEntry: Sendable, Equatable {
    let totalSize: Int64
    let chunks: Set<Int>
}

/// Per-file chunks kept on disk ACROSS sessions — only the ones that make reopening fast.
///
/// Two groups per file. HEAD: what libvlc read before the first frame (header, keyframe index,
/// the resume point's region). RESUME: the region around the last read at close, where the next
/// resume will land. Rewind history deliberately stays in RAM: 2 GB of disk is minutes of a 4K
/// remux, and streaming every byte through the Apple TV's flash would write ~36 GB an hour.
///
/// Layout: `<directory>/<fnv-1a of fileKey>/meta.json` plus one `<index>.chunk` per chunk.
actor IndexStore {
    private let directory: URL
    private let chunkSize: Int
    private let perFileLimit: Int
    private let totalLimit: Int
    private let files = FileManager.default

    private struct Meta: Codable {
        var fileKey: String
        var totalSize: Int64
        var lastOpened: Date
        var head: [Int]
        var resume: [Int]
        var all: Set<Int> { Set(head).union(resume) }
    }

    init(directory: URL, chunkSize: Int, perFileLimit: Int, totalLimit: Int) {
        self.directory = directory
        self.chunkSize = chunkSize
        self.perFileLimit = perFileLimit
        self.totalLimit = totalLimit
    }

    /// The file's entry, marking it the most recently opened. nil when nothing is stored.
    func open(fileKey: String) -> IndexEntry? {
        guard var meta = readMeta(fileKey) else { return nil }
        meta.lastOpened = Date()
        writeMeta(meta)
        return IndexEntry(totalSize: meta.totalSize, chunks: meta.all)
    }

    func loadChunk(fileKey: String, index: Int) -> Data? {
        try? Data(contentsOf: chunkURL(fileKey, index))
    }

    func saveHead(fileKey: String, totalSize: Int64, chunks: [(Int, Data)]) {
        save(fileKey: fileKey, totalSize: totalSize, chunks: chunks, isHead: true)
    }

    func saveResume(fileKey: String, totalSize: Int64, chunks: [(Int, Data)]) {
        save(fileKey: fileKey, totalSize: totalSize, chunks: chunks, isHead: false)
    }

    func discard(fileKey: String) {
        try? files.removeItem(at: folder(fileKey))
    }

    // MARK: - Private

    private func save(fileKey: String, totalSize: Int64, chunks: [(Int, Data)], isHead: Bool) {
        var meta = readMeta(fileKey) ?? Meta(fileKey: fileKey, totalSize: totalSize,
                                            lastOpened: Date(), head: [], resume: [])
        if meta.totalSize != totalSize {                // another file under this key: start over
            discard(fileKey: fileKey)
            meta = Meta(fileKey: fileKey, totalSize: totalSize, lastOpened: Date(), head: [], resume: [])
        }
        let maxChunks = perFileLimit / chunkSize
        let kept = isHead ? [] : meta.head              // the head outranks the resume region
        let room = max(0, maxChunks - kept.count)
        let incoming = Array(chunks.filter { !kept.contains($0.0) }.prefix(room))
        try? files.createDirectory(at: folder(fileKey), withIntermediateDirectories: true)
        for (index, data) in incoming { try? data.write(to: chunkURL(fileKey, index), options: .atomic) }
        if isHead {
            let head = incoming.map(\.0)
            meta.head = head
            meta.resume = Array(meta.resume.filter { !head.contains($0) }
                .prefix(max(0, maxChunks - head.count)))
        } else {
            meta.resume = incoming.map(\.0)
        }
        meta.lastOpened = Date()
        writeMeta(meta)
        removeUnreferencedChunks(meta)
        enforceTotal(keeping: fileKey)
    }

    private func removeUnreferencedChunks(_ meta: Meta) {
        let folder = folder(meta.fileKey)
        let keep = meta.all
        for name in (try? files.contentsOfDirectory(atPath: folder.path)) ?? []
        where name.hasSuffix(".chunk") {
            if let index = Int(name.dropLast(".chunk".count)), !keep.contains(index) {
                try? files.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }

    private func enforceTotal(keeping current: String) {
        var metas = ((try? files.contentsOfDirectory(atPath: directory.path)) ?? [])
            .compactMap { name -> Meta? in
                let url = directory.appendingPathComponent(name).appendingPathComponent("meta.json")
                return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Meta.self, from: $0) }
            }
            .sorted { $0.lastOpened < $1.lastOpened }
        var total = metas.reduce(0) { $0 + $1.all.count * chunkSize }
        while total > totalLimit, let oldest = metas.first(where: { $0.fileKey != current }) {
            discard(fileKey: oldest.fileKey)
            total -= oldest.all.count * chunkSize
            metas.removeAll { $0.fileKey == oldest.fileKey }
        }
    }

    private func readMeta(_ fileKey: String) -> Meta? {
        let url = folder(fileKey).appendingPathComponent("meta.json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Meta.self, from: $0) }
    }

    private func writeMeta(_ meta: Meta) {
        try? files.createDirectory(at: folder(meta.fileKey), withIntermediateDirectories: true)
        let url = folder(meta.fileKey).appendingPathComponent("meta.json")
        try? JSONEncoder().encode(meta).write(to: url, options: .atomic)
    }

    private func folder(_ fileKey: String) -> URL {
        directory.appendingPathComponent(Self.folderName(fileKey), isDirectory: true)
    }

    private func chunkURL(_ fileKey: String, _ index: Int) -> URL {
        folder(fileKey).appendingPathComponent("\(index).chunk")
    }

    /// FNV-1a 64: stable across launches and platforms, filesystem-safe, no CryptoKit (Linux).
    static func folderName(_ key: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
