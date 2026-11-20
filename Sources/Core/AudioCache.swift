import Foundation

/// 音频文件缓存：Caches/SPlayerAudio/<songId>.mp3
enum AudioCache {
    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SPlayerAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func cachedURL(songId: Int) -> URL? {
        let url = directory.appendingPathComponent("\(songId).mp3")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func store(tmpURL: URL, songId: Int) {
        let dest = directory.appendingPathComponent("\(songId).mp3")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: tmpURL, to: dest)
    }

    /// 超过缓存上限时按最近使用时间清理旧文件
    static func enforceLimit(maxBytes: Int64) {
        guard maxBytes > 0 else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )) ?? []

        var total = files.reduce(Int64(0)) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
        guard total > maxBytes else { return }

        let sorted = files.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }

        for url in sorted where total > maxBytes {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try? FileManager.default.removeItem(at: url)
            total -= Int64(size)
        }
    }

    static func totalSize() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return files.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }

    /// 缓存条目
    struct Entry: Identifiable {
        let songId: Int
        let size: Int64
        let modifiedAt: Date

        var id: Int { songId }
    }

    /// 列出全部缓存文件（按修改时间倒序）
    static func entries() -> [Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )) ?? []

        return files.compactMap { url -> Entry? in
            guard let songId = Int(url.deletingPathExtension().lastPathComponent) else { return nil }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return Entry(
                songId: songId,
                size: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate ?? .distantPast
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// 删除单首缓存
    static func remove(songId: Int) {
        let url = directory.appendingPathComponent("\(songId).mp3")
        try? FileManager.default.removeItem(at: url)
    }

    static func clear() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in files {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
