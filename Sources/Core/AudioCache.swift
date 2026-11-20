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
