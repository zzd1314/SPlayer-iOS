import Foundation

// MARK: - 歌单 / 搜索接口

/// 新建歌单（/playlist/create）
struct CreatePlaylistResponse: Decodable {
    let code: Int
    let id: Int?
    let playlist: Playlist?
}

/// MV 搜索（cloudsearch type=1004）
struct MVSearchResponse: Decodable {
    struct Result: Decodable {
        let mvs: [MVSummary]?
    }

    let code: Int
    let result: Result?
}

/// MV 地址（/mv/url）
struct MVURLResponse: Decodable {
    struct Payload: Decodable {
        let url: String?
    }

    let code: Int
    let data: Payload?
}

/// 云盘歌曲（/user/cloud）
struct CloudMusicResponse: Decodable {
    struct Item: Decodable {
        let songId: Int?
        let songName: String?
        let artist: String?
        let album: String?
        let simpleSong: Song?
    }

    let code: Int
    let data: [Item]?
    let count: Int?
}

/// 云盘上传（/cloud）
struct CloudUploadResponse: Decodable {
    let code: Int
    let message: String?
    let msg: String?
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

    /// MV 搜索
    func searchMVs(
        keywords: String,
        limit: Int = 30,
        offset: Int = 0,
        cookie: String? = nil
    ) async throws -> [MVSummary] {
        let response: MVSearchResponse = try await get(
            "/cloudsearch",
            query: [
                "keywords": keywords,
                "type": "1004",
                "limit": String(limit),
                "offset": String(offset)
            ],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "搜索 MV 失败")
        }
        return response.result?.mvs ?? []
    }

    /// MV 播放地址
    func mvURL(id: Int, cookie: String? = nil) async throws -> URL? {
        let response: MVURLResponse = try await get(
            "/mv/url",
            query: ["id": String(id), "r": "1080"],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取 MV 地址失败")
        }
        guard let raw = response.data?.url, let url = URL(string: raw) else {
            return nil
        }
        return url
    }

    /// 云盘歌曲（仅返回带 simpleSong 的可播放项）
    func cloudSongs(cookie: String) async throws -> [Song] {
        let response: CloudMusicResponse = try await get(
            "/user/cloud",
            query: ["limit": "200", "offset": "0"],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取云盘失败")
        }
        return (response.data ?? []).compactMap(\.simpleSong)
    }

    /// 上传本地音频到云盘（/cloud）
    func uploadCloudSong(fileURL: URL, cookie: String) async throws {
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: fileURL)
        let mimeType: String
        switch fileURL.pathExtension.lowercased() {
        case "flac":
            mimeType = "audio/flac"
        case "m4a":
            mimeType = "audio/mp4"
        case "wav":
            mimeType = "audio/wav"
        case "aac":
            mimeType = "audio/aac"
        default:
            mimeType = "audio/mpeg"
        }

        let response: CloudUploadResponse = try await postMultipart(
            "/cloud",
            fileField: "songFile",
            fileName: fileURL.lastPathComponent,
            mimeType: mimeType,
            fileData: data,
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: response.message ?? response.msg ?? "上传失败"
            )
        }
    }

    /// 删除云盘歌曲（/user/cloud/del）
    func deleteCloudSong(id: Int, cookie: String) async throws {
        let response: OperationResponse = try await get(
            "/user/cloud/del",
            query: ["id": String(id)],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: response.message ?? response.msg ?? "删除云盘歌曲失败"
            )
        }
    }
}
