import Foundation

/// 播放地址接口（/song/url/v1）
struct SongURLResponse: Decodable {
    struct Item: Decodable {
        let id: Int
        let url: String?
        let level: String?
    }

    let code: Int
    let data: [Item]?
}

extension NeteaseAPI {
    /// 解析歌曲播放地址（默认 exhigh 极高音质）
    func songURL(id: Int, level: String = "exhigh", cookie: String?) async throws -> URL {
        let response: SongURLResponse = try await get(
            "/song/url/v1",
            query: ["id": String(id), "level": level],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取播放地址失败")
        }
        guard let raw = response.data?.first?.url, let url = URL(string: raw) else {
            throw APIError.business(code: response.code, message: "该歌曲暂无可用播放地址（可能为 VIP 专享）")
        }
        return url
    }
}
