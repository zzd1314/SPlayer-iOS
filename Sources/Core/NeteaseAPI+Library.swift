import Foundation

// MARK: - 歌单 / 搜索接口

/// 新建歌单（/playlist/create）
struct CreatePlaylistResponse: Decodable {
    let code: Int
    let id: Int?
    let playlist: Playlist?
}

extension NeteaseAPI {
    /// 用户歌单列表
    func userPlaylists(uid: Int, cookie: String?) async throws -> [Playlist] {
        let response: UserPlaylistResponse = try await get(
            "/user/playlist",
            query: ["uid": String(uid), "limit": "1000"],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取歌单失败")
        }
        return response.playlist ?? []
    }

    /// 歌单全部歌曲
    func playlistTracks(id: Int, limit: Int = 1000, offset: Int = 0, cookie: String?) async throws -> [Song] {
        let response: PlaylistTrackAllResponse = try await get(
            "/playlist/track/all",
            query: ["id": String(id), "limit": String(limit), "offset": String(offset)],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取歌曲失败")
        }
        return response.songs ?? []
    }

    /// 歌曲搜索（type=1）
    func searchSongs(keywords: String, limit: Int = 30, offset: Int = 0, cookie: String? = nil) async throws -> [Song] {
        let response: CloudSearchResponse = try await get(
            "/cloudsearch",
            query: [
                "keywords": keywords,
                "type": "1",
                "limit": String(limit),
                "offset": String(offset)
            ],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "搜索失败")
        }
        return response.result?.songs ?? []
    }

    /// 新建歌单
    @discardableResult
    func createPlaylist(name: String, cookie: String) async throws -> Int? {
        let response: CreatePlaylistResponse = try await get(
            "/playlist/create",
            query: ["name": name],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "创建歌单失败")
        }
        return response.id ?? response.playlist?.id
    }

    /// 重命名歌单
    func updatePlaylist(id: Int, name: String, cookie: String) async throws {
        let response: OperationResponse = try await get(
            "/playlist/update",
            query: ["id": String(id), "name": name],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: response.message ?? response.msg ?? "更新歌单失败"
            )
        }
    }

    /// 删除歌单
    func deletePlaylist(id: Int, cookie: String) async throws {
        let response: OperationResponse = try await get(
            "/playlist/delete",
            query: ["id": String(id)],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: response.message ?? response.msg ?? "删除歌单失败"
            )
        }
    }
}
