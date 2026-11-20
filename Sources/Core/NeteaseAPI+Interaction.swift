import Foundation

// MARK: - 关注 / 收藏 / 评论接口

/// 歌单详情中的收藏状态（/playlist/detail）
struct PlaylistSubscriptionResponse: Decodable {
    struct Info: Decodable {
        let subscribed: Bool?
    }

    let code: Int
    let playlist: Info?
}

/// 已关注歌手列表（/artist/sublist），兼容 artists / data 两种返回
struct ArtistSublistResponse: Decodable {
    let code: Int
    let artists: [ArtistSummary]?
    let data: [ArtistSummary]?
}

/// 通用操作结果
struct OperationResponse: Decodable {
    let code: Int
    let message: String?
    let msg: String?
}

/// 歌曲评论（/comment/music）
struct CommentsResponse: Decodable {
    let code: Int
    let total: Int?
    let hotComments: [CommentItem]?
    let comments: [CommentItem]?
}

/// 单条评论
struct CommentItem: Decodable, Identifiable {
    struct User: Decodable {
        let nickname: String
        let avatarUrl: String?
    }

    let commentId: Int
    let content: String
    let time: Int?
    var likedCount: Int?
    var liked: Bool?
    let user: User?

    var id: Int { commentId }

    /// 毫秒时间戳 → yyyy-MM-dd
    var dateText: String? {
        guard let time, time > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: Double(time) / 1000))
    }
}

extension NeteaseAPI {
    /// 歌单是否已收藏
    func playlistSubscribed(id: Int, cookie: String?) async throws -> Bool {
        let response: PlaylistSubscriptionResponse = try await get(
            "/playlist/detail",
            query: ["id": String(id)],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取歌单信息失败")
        }
        return response.playlist?.subscribed ?? false
    }

    /// 收藏 / 取消收藏歌单
    func setPlaylistSubscribed(id: Int, subscribe: Bool, cookie: String) async throws {
        let response: OperationResponse = try await get(
            "/playlist/subscribe",
            query: ["id": String(id), "t": subscribe ? "1" : "0"],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: response.message ?? response.msg ?? "歌单收藏操作失败"
            )
        }
    }

    /// 已关注歌手列表
    func subscribedArtists(cookie: String) async throws -> [ArtistSummary] {
        let response: ArtistSublistResponse = try await get(
            "/artist/sublist",
            query: ["limit": "1000", "offset": "0"],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取关注歌手失败")
        }
        return response.artists ?? response.data ?? []
    }

    /// 已关注歌手 id 集合
    func subscribedArtistIDs(cookie: String) async throws -> Set<Int> {
        Set(try await subscribedArtists(cookie: cookie).map(\.id))
    }

    /// 关注 / 取消关注歌手
    func setArtistSubscribed(id: Int, subscribe: Bool, cookie: String) async throws {
        let response: OperationResponse = try await get(
            "/artist/sub",
            query: ["id": String(id), "t": subscribe ? "1" : "0"],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: response.message ?? response.msg ?? "歌手关注操作失败"
            )
        }
    }

    /// 歌曲评论：热门 + 最新
    func songComments(
        id: Int,
        limit: Int = 50,
        offset: Int = 0,
        cookie: String? = nil
    ) async throws -> (hot: [CommentItem], latest: [CommentItem], total: Int) {
        let response: CommentsResponse = try await get(
            "/comment/music",
            query: ["id": String(id), "limit": String(limit), "offset": String(offset)],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取评论失败")
        }
        return (response.hotComments ?? [], response.comments ?? [], response.total ?? 0)
    }

    /// 评论点赞 / 取消点赞
    func setCommentLiked(songId: Int, commentId: Int, like: Bool, cookie: String) async throws {
        let response: OperationResponse = try await get(
            "/comment/like",
            query: [
                "id": String(songId),
                "cid": String(commentId),
                "t": like ? "1" : "0",
                "type": "0"
            ],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: response.message ?? response.msg ?? "评论点赞失败"
            )
        }
    }

    /// 发表歌曲评论
    func sendComment(songId: Int, content: String, cookie: String) async throws {
        let response: OperationResponse = try await get(
            "/comment",
            query: [
                "t": "1",
                "type": "0",
                "id": String(songId),
                "content": content
            ],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: response.message ?? response.msg ?? "评论发送失败"
            )
        }
    }
}
