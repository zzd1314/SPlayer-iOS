import Foundation

/// 显式下载库：文件保存在 Documents/SPlayerDownloads，与播放缓存互不影响
enum DownloadStore {
    struct Item: Codable, Identifiable {
        let song: Song
        let fileName: String
        let size: Int64
        let downloadedAt: Date
        let quality: String
        let qualityLabel: String

        var id: Int { song.id }
    }

    private static let folderName = "SPlayerDownloads"
    private static let indexName = "downloads.json"

    private static var directory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private static var indexURL: URL {
        directory.appendingPathComponent(indexName)
    }

    static func items() -> [Item] {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([Item].self, from: data)
        else { return [] }
        return list.sorted { $0.downloadedAt > $1.downloadedAt }
    }

    static func isDownloaded(_ songId: Int) -> Bool {
        items().contains { $0.song.id == songId }
    }

    static func url(for songId: Int) -> URL? {
        guard let item = items().first(where: { $0.song.id == songId }) else { return nil }
        let fileURL = directory.appendingPathComponent(item.fileName)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    static func totalSize() -> Int64 {
        items().reduce(0) { $0 + $1.size }
    }

    /// 下载歌曲到 Documents，已存在时覆盖
    static func download(_ song: Song, quality: String, cookie: String?) async throws {
        guard song.id > 0 else {
            throw APIError.business(code: -1, message: "本地歌曲无需下载")
        }

        let remoteURL = try await NeteaseAPI().songURL(
            id: song.id,
            level: quality,
            cookie: cookie
        )
        let (tmpURL, response) = try await URLSession.shared.download(from: remoteURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.business(code: http.statusCode, message: "下载失败（HTTP \(http.statusCode)）")
        }

        try ensureDirectory()

        let ext = remoteURL.pathExtension.isEmpty ? "mp3" : remoteURL.pathExtension
        let fileName = "\(song.id).\(ext)"
        let targetURL = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try? FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.moveItem(at: tmpURL, to: targetURL)

        let attributes = try? FileManager.default.attributesOfItem(atPath: targetURL.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let label = AppSettings.audioLevels.first(where: { $0.value == quality })?.label ?? quality

        var list = items()
        list.removeAll { $0.song.id == song.id }
        list.insert(
            Item(
                song: song,
                fileName: fileName,
                size: size,
                downloadedAt: Date(),
                quality: quality,
                qualityLabel: label
            ),
            at: 0
        )
        save(list)
    }

    static func remove(_ songId: Int) {
        var list = items()
        guard let item = list.first(where: { $0.song.id == songId }) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.fileName))
        list.removeAll { $0.song.id == songId }
        save(list)
    }

    static func clear() {
        for item in items() {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.fileName))
        }
        try? FileManager.default.removeItem(at: indexURL)
    }

    private static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func save(_ list: [Item]) {
        try? ensureDirectory()
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
