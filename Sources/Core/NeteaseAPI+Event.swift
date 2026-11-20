import Foundation

// MARK: - 云村动态

/// 动态（/event）
struct EventItem: Decodable, Identifiable {
    struct User: Decodable {
        let userId: Int?
        let nickname: String?
        let avatarUrl: String?
    }

    struct Info: Decodable {
        let commentId: Int?
        var likedCount: Int?
        var liked: Bool?
        let commentCount: Int?
        let shareCount: Int?
        let time: Int?
    }

    let eventId: Int?
    let type: Int?
    let user: User?
    let json: String?
    let pics: [String]?
    var info: Info?

    enum CodingKeys: String, CodingKey {
        case eventId = "id"
        case type, user, json, pics, info
    }

    var id: Int { eventId ?? 0 }

    var nickname: String {
        user?.nickname ?? "网易云用户"
    }

    var avatarURL: String? {
        user?.avatarUrl
    }

    var time: Int? {
        info?.time
    }

    /// 动态正文
    var message: String? {
        guard let json, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["msg"] as? String
    }

    /// 动态中分享的歌曲
    var sharedSong: Song? {
        guard let json, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let songObject = object["song"],
              let songData = try? JSONSerialization.data(withJSONObject: songObject)
        else { return nil }
        return try? JSONDecoder().decode(Song.self, from: songData)
    }
}

struct EventListResponse: Decodable {
    let code: Int
    let events: [EventItem]?
    let lasttime: Int?
}

extension NeteaseAPI {
    /// 动态列表（lasttime 用于翻页，首次传 nil）
    func events(
        limit: Int = 20,
        lasttime: Int? = nil,
        cookie: String
    ) async throws -> (events: [EventItem], lasttime: Int?) {
        var query = ["limit": String(limit)]
        if let lasttime {
            query["lasttime"] = String(lasttime)
        }
        let response: EventListResponse = try await get(
            "/event",
            query: query,
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取动态失败")
        }
        return (response.events ?? [], response.lasttime)
    }

    /// 动态点赞 / 取消点赞
    func likeEvent(id: Int, like: Bool, cookie: String) async throws {
        let response: OperationResponse = try await get(
            "/event/like",
            query: ["id": String(id), "t": like ? "1" : "0"],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: response.message ?? response.msg ?? "操作失败"
            )
        }
    }
}
