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
}
