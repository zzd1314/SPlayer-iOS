import Foundation

// MARK: - 搜索分类 / 歌手 / 专辑接口

/// 歌手搜索（type=100）
struct ArtistSearchResponse: Decodable {
    struct Result: Decodable {
        let artists: [ArtistSummary]?
    }

    let code: Int
    let result: Result?
}

/// 专辑搜索（type=10）
struct AlbumSearchResponse: Decodable {
    struct Result: Decodable {
        let albums: [AlbumSummary]?
    }

    let code: Int
    let result: Result?
}

/// 歌单搜索（type=1000）
struct PlaylistSearchResponse: Decodable {
    struct Result: Decodable {
        let playlists: [Playlist]?
    }

    let code: Int
    let result: Result?
}

/// 歌手详情（/artists）
struct ArtistDetailResponse: Decodable {
    let code: Int
    let artist: ArtistSummary?
    let hotSongs: [Song]?
}

/// 歌手专辑（/artist/album）
struct ArtistAlbumsResponse: Decodable {
    let code: Int
    let hotAlbums: [AlbumSummary]?
}

/// 专辑详情（/album）
struct AlbumDetailResponse: Decodable {
    let code: Int
    let album: AlbumSummary?
    let songs: [Song]?
}

extension NeteaseAPI {
    /// 歌手搜索
    func searchArtists(
        keywords: String,
        limit: Int = 30,
        offset: Int = 0,
        cookie: String? = nil
    ) async throws -> [ArtistSummary] {
        let response: ArtistSearchResponse = try await get(
            "/cloudsearch",
            query: [
                "keywords": keywords,
                "type": "100",
                "limit": String(limit),
                "offset": String(offset)
            ],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "搜索歌手失败")
        }
        return response.result?.artists ?? []
    }

    /// 专辑搜索
    func searchAlbums(
        keywords: String,
        limit: Int = 30,
        offset: Int = 0,
        cookie: String? = nil
    ) async throws -> [AlbumSummary] {
        let response: AlbumSearchResponse = try await get(
            "/cloudsearch",
            query: [
                "keywords": keywords,
                "type": "10",
                "limit": String(limit),
                "offset": String(offset)
            ],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "搜索专辑失败")
        }
        return response.result?.albums ?? []
    }

    /// 歌单搜索
    func searchPlaylists(
        keywords: String,
        limit: Int = 30,
        offset: Int = 0,
        cookie: String? = nil
    ) async throws -> [Playlist] {
        let response: PlaylistSearchResponse = try await get(
            "/cloudsearch",
            query: [
                "keywords": keywords,
                "type": "1000",
                "limit": String(limit),
                "offset": String(offset)
            ],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "搜索歌单失败")
        }
        return response.result?.playlists ?? []
    }

    /// 歌手详情 + 热门歌曲
    func artistDetail(id: Int, cookie: String? = nil) async throws -> (artist: ArtistSummary, hotSongs: [Song]) {
        let response: ArtistDetailResponse = try await get(
            "/artists",
            query: ["id": String(id)],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取歌手信息失败")
        }
        guard let artist = response.artist else {
            throw APIError.business(code: response.code, message: "歌手不存在")
        }
        return (artist, response.hotSongs ?? [])
    }

    /// 歌手全部专辑
    func artistAlbums(id: Int, limit: Int = 50, cookie: String? = nil) async throws -> [AlbumSummary] {
        let response: ArtistAlbumsResponse = try await get(
            "/artist/album",
            query: ["id": String(id), "limit": String(limit)],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取歌手专辑失败")
        }
        return response.hotAlbums ?? []
    }

    /// 专辑详情 + 歌曲列表
    func albumDetail(id: Int, cookie: String? = nil) async throws -> (album: AlbumSummary, songs: [Song]) {
        let response: AlbumDetailResponse = try await get(
            "/album",
            query: ["id": String(id)],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取专辑失败")
        }
        guard let album = response.album else {
            throw APIError.business(code: response.code, message: "专辑不存在")
        }
        return (album, response.songs ?? [])
    }

    /// 收藏 / 取消收藏专辑
    func setAlbumSubscribed(id: Int, subscribe: Bool, cookie: String) async throws {
        let response: OperationResponse = try await get(
            "/album/sub",
            query: ["id": String(id), "t": subscribe ? "1" : "0"],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: response.message ?? response.msg ?? "专辑收藏操作失败"
            )
        }
    }
}
