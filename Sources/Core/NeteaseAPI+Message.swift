import Foundation

// MARK: - 私信 / 消息

/// 最近联系人（/msg/recentcontact）
struct RecentContact: Decodable, Identifiable {
    struct User: Decodable {
        let userId: Int?
        let nickname: String?
        let avatarUrl: String?
    }

    let conversationId: Int?
    let userId: Int?
    let user: User?
    let lastMsg: String?
    let lastMsgTime: Int?
    let newMsgCount: Int?

    enum CodingKeys: String, CodingKey {
        case conversationId = "id"
        case userId, user, lastMsg, lastMsgTime, newMsgCount
    }

    var id: String {
        "\(conversationId ?? 0)-\(contactUserId ?? 0)"
    }

    var contactUserId: Int? {
        user?.userId ?? userId
    }

    var nickname: String {
        user?.nickname ?? "用户 \(contactUserId ?? 0)"
    }

    var avatarURL: String? {
        user?.avatarUrl
    }
}

struct RecentContactsResponse: Decodable {
    let code: Int
    let data: [RecentContact]?
}

/// 私信消息（/msg/private/history）
struct PrivateMessage: Decodable, Identifiable {
    let remoteId: Int?
    let fromUserId: Int?
    let toUserId: Int?
    let content: String?
    let time: Int?

    enum CodingKeys: String, CodingKey {
        case remoteId = "id"
        case fromUserId, toUserId, content, time
    }

    var id: String {
        "\(remoteId ?? 0)-\(fromUserId ?? 0)-\(time ?? 0)"
    }

    var date: Date? {
        guard let time else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time) / 1000)
    }
}

struct MessageHistoryResponse: Decodable {
    let code: Int
    let more: Bool?
    let msgs: [PrivateMessage]?
}

extension NeteaseAPI {
    /// 最近联系人
    func recentContacts(cookie: String) async throws -> [RecentContact] {
        let response: RecentContactsResponse = try await get(
            "/msg/recentcontact",
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取消息列表失败")
        }
        return response.data ?? []
    }

    /// 私信历史（返回最新在前）
    func privateMessages(
        uid: Int,
        limit: Int = 30,
        offset: Int = 0,
        cookie: String
    ) async throws -> (messages: [PrivateMessage], more: Bool) {
        let response: MessageHistoryResponse = try await get(
            "/msg/private/history",
            query: ["uid": String(uid), "limit": String(limit), "offset": String(offset)],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取私信失败")
        }
        return (response.msgs ?? [], response.more ?? false)
    }

    /// 发送私信
    func sendPrivateMessage(uid: Int, text: String, cookie: String) async throws {
        let response: OperationResponse = try await get(
            "/msg/private/send",
            query: ["uid": String(uid), "msg": text],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: response.message ?? response.msg ?? "发送失败"
            )
        }
    }
}
