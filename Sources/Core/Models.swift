import Foundation

// MARK: - 歌单

struct Playlist: Decodable, Identifiable, Hashable {
    struct Creator: Decodable, Hashable {
        let nickname: String
        let avatarUrl: String?
    }

    let id: Int
    let name: String
    let coverImgUrl: String?
    let trackCount: Int?
    let playCount: Int?
    let creator: Creator?
}

struct UserPlaylistResponse: Decodable {
    let code: Int
    let playlist: [Playlist]?
}

struct PlaylistTrackAllResponse: Decodable {
    let code: Int
    let songs: [Song]?
}

// MARK: - 歌曲

struct Song: Codable, Identifiable, Hashable {
    struct Artist: Codable, Hashable {
        let id: Int?
        let name: String
    }

    struct Album: Codable, Hashable {
        let id: Int?
        let name: String?
        let picUrl: String?
    }

    let id: Int
    let name: String
    let artists: [Artist]
    let albumName: String?
    let albumPicUrl: String?
    /// 时长（毫秒）
    let duration: Int

    enum CodingKeys: String, CodingKey {
        case id, name, ar, artists, al, album, dt, duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        // 新版接口为 ar / al / dt，旧版为 artists / album / duration
        let ar = try? container.decode([Artist].self, forKey: .ar)
        let legacyArtists = try? container.decode([Artist].self, forKey: .artists)
        artists = ar ?? legacyArtists ?? []

        let al = try? container.decode(Album.self, forKey: .al)
        let legacyAlbum = try? container.decode(Album.self, forKey: .album)
        albumName = (al ?? legacyAlbum)?.name
        albumPicUrl = (al ?? legacyAlbum)?.picUrl

        duration = (try? container.decode(Int.self, forKey: .dt))
            ?? (try? container.decode(Int.self, forKey: .duration))
            ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(artists, forKey: .ar)
        try container.encode(Album(id: nil, name: albumName, picUrl: albumPicUrl), forKey: .al)
        try container.encode(duration, forKey: .dt)
    }

    var artistText: String {
        artists.map(\.name).joined(separator: " / ")
    }
}

struct CloudSearchResponse: Decodable {
    struct Result: Decodable {
        let songs: [Song]?
        let songCount: Int?
    }

    let code: Int
    let result: Result?
}

// MARK: - 歌手 / 专辑

/// 歌手摘要（搜索结果 / 歌手详情）
struct ArtistSummary: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let picUrl: String?
    let albumSize: Int?
    let musicSize: Int?
    let alias: [String]?
}

/// 专辑摘要（搜索结果 / 歌手专辑 / 专辑详情）
struct AlbumSummary: Decodable, Identifiable, Hashable {
    struct Artist: Decodable, Hashable {
        let id: Int?
        let name: String?
    }

    let id: Int
    let name: String
    let picUrl: String?
    let artist: Artist?
    let size: Int?
    let publishTime: Int?
}

extension AlbumSummary {
    var artistText: String {
        artist?.name ?? "未知歌手"
    }

    /// 毫秒时间戳 → yyyy-MM-dd
    var publishDateText: String? {
        guard let publishTime, publishTime > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: Double(publishTime) / 1000))
    }

    var publishYearText: String? {
        publishDateText.map { String($0.prefix(4)) }
    }
}

// MARK: - 播放进度快照

/// 用于「记忆播放进度」：应用退出后恢复队列与进度
struct PlaybackSnapshot: Codable {
    let queue: [Song]
    let index: Int
    let time: Double
    let savedAt: Date
}
