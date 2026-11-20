import AVFoundation
import Foundation

/// 本地音乐库：导入音频文件、解析元数据、持久化索引
/// 本地歌曲使用负数 id，避免与在线歌曲冲突
enum LocalMusicStore {
    struct Track: Codable, Identifiable {
        let song: Song
        let fileName: String
        let importedAt: Date

        var id: Int { song.id }
    }

    private static let indexFileName = "library.json"

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SPlayerLocal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let covers = dir.appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: covers, withIntermediateDirectories: true)
        return dir
    }()

    private static var cached: [Track]?

    /// 全部本地曲目（最新导入在前）
    static func allTracks() -> [Track] {
        if let cached { return cached }
        let url = directory.appendingPathComponent(indexFileName)
        guard let data = try? Data(contentsOf: url),
              let tracks = try? JSONDecoder().decode([Track].self, from: data)
        else {
            cached = []
            return []
        }
        cached = tracks
        return tracks
    }

    static func songs() -> [Song] {
        allTracks().map(\.song)
    }

    static func isLocal(_ songId: Int) -> Bool {
        songId < 0
    }

    /// 本地曲目文件地址（仅负 id 可命中）
    static func url(for songId: Int) -> URL? {
        guard isLocal(songId),
              let track = allTracks().first(where: { $0.song.id == songId })
        else { return nil }
        let url = directory.appendingPathComponent(track.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 本地封面文件地址
    static func coverURL(for songId: Int) -> URL? {
        let url = directory.appendingPathComponent("covers/\(songId).jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 导入文件（拷贝到 App 沙盒并解析元数据）
    @discardableResult
    static func importFiles(_ urls: [URL]) async -> (added: Int, failed: Int) {
        guard !urls.isEmpty else { return (0, 0) }

        var existing = allTracks()
        var nextId = (existing.map(\.song.id).min() ?? 0) - 1
        var added: [Track] = []
        var failed = 0

        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let track = try await importFile(url, id: nextId)
                nextId -= 1
                added.append(track)
            } catch {
                failed += 1
            }
        }

        if !added.isEmpty {
            existing.insert(contentsOf: added, at: 0)
            save(existing)
        }
        return (added.count, failed)
    }

    static func delete(_ track: Track) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(track.fileName))
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent("covers/\(track.song.id).jpg")
        )
        var tracks = allTracks()
        tracks.removeAll { $0.song.id == track.song.id }
        save(tracks)
    }

    // MARK: - 私有

    private static func importFile(_ url: URL, id: Int) async throws -> Track {
        let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension.lowercased()
        let fileName = "\(id).\(ext)"
        let destination = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: url, to: destination)

        let asset = AVURLAsset(url: destination)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let metadata = (try? await asset.load(.commonMetadata)) ?? []

        var title: String?
        var artist: String?
        var album: String?
        var artwork: Data?

        for item in metadata {
            if item.commonKey == .commonKeyTitle {
                title = try? await item.load(.stringValue)
            } else if item.commonKey == .commonKeyArtist {
                artist = try? await item.load(.stringValue)
            } else if item.commonKey == .commonKeyAlbumName {
                album = try? await item.load(.stringValue)
            } else if item.commonKey == .commonKeyArtwork {
                artwork = try? await item.load(.dataValue)
            }
        }

        var picURL: String?
        if let artwork, !artwork.isEmpty {
            let coverURL = directory.appendingPathComponent("covers/\(id).jpg")
            if (try? artwork.write(to: coverURL)) != nil {
                picURL = "local://\(id)"
            }
        }

        let artists = artist.flatMap { name -> [Song.Artist]? in
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : [Song.Artist(id: nil, name: trimmed)]
        } ?? []

        let song = Song(
            id: id,
            name: title?.trimmingCharacters(in: .whitespaces).isEmpty == false
                ? title!.trimmingCharacters(in: .whitespaces)
                : url.deletingPathExtension().lastPathComponent,
            artists: artists,
            albumName: album,
            albumPicUrl: picURL,
            duration: Int(duration * 1000)
        )
        return Track(song: song, fileName: fileName, importedAt: Date())
    }

    private static func save(_ tracks: [Track]) {
        cached = tracks
        let url = directory.appendingPathComponent(indexFileName)
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: url)
    }
}
