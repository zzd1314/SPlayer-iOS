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
    /// 解析歌曲播放地址
    ///
    /// 使用旧版 `/song/url`（eapi 加密）：新版 `/song/url/v1` 需要网易云最新的 xeapi
    /// 签名协议，内置的 Rust 服务暂不支持；`/song/url` 在内置服务与自建 api-enhanced 上均可用。
    func songURL(id: Int, level: String = "exhigh", cookie: String?) async throws -> URL {
        let response: SongURLResponse = try await get(
            "/song/url",
            query: ["id": String(id), "br": String(Self.bitrate(for: level))],
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

    /// 音质档位 → 旧版接口使用的目标码率
    private static func bitrate(for level: String) -> Int {
        switch level {
        case "standard": return 128000
        case "higher": return 192000
        case "exhigh": return 320000
        case "lossless", "hires": return 999000
        default: return 320000
        }
    }
}
