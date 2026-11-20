import Foundation

// MARK: - 发现 / 收藏接口

/// 推荐歌单（/personalized）
struct PersonalizedResponse: Decodable {
    struct Item: Decodable {
        let id: Int
        let name: String
        let picUrl: String?
        let playCount: Int?
        let trackCount: Int?
    }

    let code: Int
    let result: [Item]?
}

/// 每日推荐（/recommend/songs）
struct DailySongsResponse: Decodable {
    struct Payload: Decodable {
        let dailySongs: [Song]?
    }

    let code: Int
    let data: Payload?
}

/// 排行榜（/toplist）
struct ToplistResponse: Decodable {
    struct Item: Decodable {
        let id: Int
        let name: String
        let coverImgUrl: String?
        let updateFrequency: String?
        let trackCount: Int?
        let playCount: Int?
    }

    let code: Int
    let list: [Item]?
}

struct LikeListResponse: Decodable {
    let code: Int
    let ids: [Int]?
}

struct SongDetailResponse: Decodable {
    let code: Int
    let songs: [Song]?
}

struct LikeResponse: Decodable {
    let code: Int
    let message: String?
    let msg: String?
}

/// 私人 FM（/personal_fm）
struct PersonalFMResponse: Decodable {
    let code: Int
    let data: [Song]?
}

/// 歌单分类（/playlist/catlist）
struct PlaylistCatlistResponse: Decodable {
    struct SubCategory: Decodable {
        let name: String
    }

    struct Category: Decodable {
        let name: String
        let subs: [SubCategory]?
    }

    let code: Int
    let sub: [SubCategory]?
    let categories: [Category]?
}

/// 歌单广场（/top/playlist）
struct TopPlaylistsResponse: Decodable {
    let code: Int
    let playlists: [Playlist]?
}

/// 新歌速递（/personalized/newsong）
struct NewSongsResponse: Decodable {
    struct Item: Decodable {
        let id: Int
        let name: String
        let picUrl: String?
        let song: Song?
    }

    let code: Int
    let result: [Item]?
}

/// 新碟上架（/album/newest）
struct NewAlbumsResponse: Decodable {
    let code: Int
    let albums: [AlbumSummary]?
}

extension NeteaseAPI {
    /// 推荐歌单
    func personalizedPlaylists(limit: Int = 12, cookie: String?) async throws -> [Playlist] {
        let response: PersonalizedResponse = try await get(
            "/personalized",
            query: ["limit": String(limit)],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取推荐歌单失败")
        }
        return (response.result ?? []).map { item in
            Playlist(
                id: item.id,
                name: item.name,
                coverImgUrl: item.picUrl,
                trackCount: item.trackCount,
                playCount: item.playCount,
                creator: nil
            )
        }
    }

    /// 每日推荐歌曲（需登录）
    func dailyRecommendations(cookie: String?) async throws -> [Song] {
        let response: DailySongsResponse = try await get("/recommend/songs", cookie: cookie)
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取每日推荐失败")
        }
        return response.data?.dailySongs ?? []
    }

    /// 排行榜列表
    func toplists(cookie: String?) async throws -> [Playlist] {
        let response: ToplistResponse = try await get("/toplist", cookie: cookie)
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取排行榜失败")
        }
        return (response.list ?? []).map { item in
            Playlist(
                id: item.id,
                name: item.name,
                coverImgUrl: item.coverImgUrl,
                trackCount: item.trackCount,
                playCount: item.playCount,
                creator: nil
            )
        }
    }

    /// 我喜欢的音乐（仅返回歌曲 id，需登录）
    func likeList(uid: Int, cookie: String) async throws -> [Int] {
        let response: LikeListResponse = try await get(
            "/likelist",
            query: ["uid": String(uid)],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取收藏列表失败")
        }
        return response.ids ?? []
    }

    /// 批量获取歌曲详情（每批最多 200 个 id）
    func songDetails(ids: [Int], cookie: String?) async throws -> [Song] {
        guard !ids.isEmpty else { return [] }
        var songs: [Song] = []
        var start = 0
        while start < ids.count {
            let end = min(start + 200, ids.count)
            let chunk = ids[start..<end]
            let response: SongDetailResponse = try await get(
                "/song/detail",
                query: ["ids": chunk.map(String.init).joined(separator: ",")],
                cookie: cookie
            )
            guard response.code == 200 else {
                throw APIError.business(code: response.code, message: "获取歌曲详情失败")
            }
            songs.append(contentsOf: response.songs ?? [])
            start = end
        }
        return songs
    }

    /// 私人 FM 推荐歌曲（每次约 3 首，需登录）
    func personalFM(cookie: String) async throws -> [Song] {
        let response: PersonalFMResponse = try await get("/personal_fm", cookie: cookie)
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取私人 FM 失败")
        }
        return response.data ?? []
    }

    /// 歌单广场分类
    func playlistCategories(cookie: String?) async throws -> [String] {
        let response: PlaylistCatlistResponse = try await get("/playlist/catlist", cookie: cookie)
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取歌单分类失败")
        }

        var names: [String] = []
        var seen = Set<String>()
        for item in response.sub ?? [] where !item.name.isEmpty && !seen.contains(item.name) {
            seen.insert(item.name)
            names.append(item.name)
        }
        for category in response.categories ?? [] {
            for item in category.subs ?? [] where !item.name.isEmpty && !seen.contains(item.name) {
                seen.insert(item.name)
                names.append(item.name)
            }
        }
        return names
    }

    /// 歌单广场列表
    func topPlaylists(
        category: String = "全部",
        limit: Int = 30,
        offset: Int = 0,
        cookie: String?
    ) async throws -> [Playlist] {
        let response: TopPlaylistsResponse = try await get(
            "/top/playlist",
            query: [
                "cat": category,
                "limit": String(limit),
                "offset": String(offset),
                "order": "hot"
            ],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取歌单广场失败")
        }
        return response.playlists ?? []
    }

    /// 新歌速递
    func newSongs(limit: Int = 30, cookie: String?) async throws -> [Song] {
        let response: NewSongsResponse = try await get(
            "/personalized/newsong",
            query: ["limit": String(limit)],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取新歌速递失败")
        }
        return (response.result ?? []).compactMap(\.song)
    }

    /// 新碟上架
    func newAlbums(limit: Int = 30, cookie: String?) async throws -> [AlbumSummary] {
        let response: NewAlbumsResponse = try await get(
            "/album/newest",
            query: ["limit": String(limit)],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取新碟上架失败")
        }
        return response.albums ?? []
    }

    /// 收藏 / 取消收藏
    func setLike(songId: Int, like: Bool, cookie: String) async throws {
        let response: LikeResponse = try await get(
            "/like",
            query: ["id": String(songId), "like": like ? "true" : "false"],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: response.message ?? response.msg ?? "收藏操作失败"
            )
        }
    }
}
