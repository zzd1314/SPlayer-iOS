import Foundation

// MARK: - 播客模型

struct PodcastDJ: Decodable {
    let nickname: String?
    let avatarUrl: String?
}

struct PodcastRadioRef: Decodable {
    let id: Int?
    let name: String?
    let picUrl: String?
}

struct PodcastRadio: Decodable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
    let desc: String?
    let programCount: Int?
    let subCount: Int?
    let dj: PodcastDJ?
}

struct PodcastProgram: Decodable, Identifiable {
    let id: Int
    let name: String
    let coverUrl: String?
    let duration: Int
    let listenerCount: Int?
    let createTime: Int64?
    let description: String?
    let dj: PodcastDJ?
    let radio: PodcastRadioRef?
    let mainSong: Song?
}

// MARK: - 响应

private struct HotRadioResponse: Decodable {
    let code: Int
    let djradios: [PodcastRadio]?
}

private struct RadioRecommendResponse: Decodable {
    let code: Int
    let result: [PodcastProgram]?
}

private struct RadioProgramResponse: Decodable {
    let code: Int
    let programs: [PodcastProgram]?
}

private struct ProgramDetailResponse: Decodable {
    let code: Int
    let program: PodcastProgram?
}

private struct RadioDetailResponse: Decodable {
    let code: Int
    let data: PodcastRadio?
}

private struct ArtistListResponse: Decodable {
    let code: Int
    let artists: [ArtistSummary]?
}

extension NeteaseAPI {
    /// 热门播客电台
    func hotPodcastRadios(limit: Int = 30, offset: Int = 0, cookie: String?) async throws -> [PodcastRadio] {
        do {
            let response: HotRadioResponse = try await get(
                "/dj/hot",
                query: ["limit": "\(limit)", "offset": "\(offset)"],
                cookie: cookie
            )
            if response.code == 200, let list = response.djradios, !list.isEmpty {
                return list
            }
        } catch {
            // 部分服务端只实现 /djradio/hot，继续尝试
        }

        let fallback: HotRadioResponse = try await get(
            "/djradio/hot",
            query: ["limit": "\(limit)", "offset": "\(offset)"],
            cookie: cookie
        )
        guard fallback.code == 200 else {
            throw APIError.business(code: fallback.code, message: "获取热门播客失败")
        }
        return fallback.djradios ?? []
    }

    /// 推荐节目
    func recommendedPodcastPrograms(cookie: String?) async throws -> [PodcastProgram] {
        let response: RadioRecommendResponse = try await get(
            "/personalized/djprogram",
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取推荐节目失败")
        }
        return response.result ?? []
    }

    /// 电台节目列表
    func radioPrograms(
        radioId: Int,
        limit: Int = 30,
        offset: Int = 0,
        cookie: String?
    ) async throws -> [PodcastProgram] {
        let response: RadioProgramResponse = try await get(
            "/dj/program",
            query: [
                "radioId": "\(radioId)",
                "limit": "\(limit)",
                "offset": "\(offset)"
            ],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取节目列表失败")
        }
        return response.programs ?? []
    }

    /// 节目详情
    func podcastProgramDetail(id: Int, cookie: String?) async throws -> PodcastProgram {
        let response: ProgramDetailResponse = try await get(
            "/dj/program/detail",
            query: ["id": "\(id)"],
            cookie: cookie
        )
        guard response.code == 200, let program = response.program else {
            throw APIError.business(code: response.code, message: "获取节目详情失败")
        }
        return program
    }

    /// 电台详情
    func podcastRadioDetail(id: Int, cookie: String?) async throws -> PodcastRadio {
        let response: RadioDetailResponse = try await get(
            "/djradio/detail",
            query: ["id": "\(id)"],
            cookie: cookie
        )
        guard response.code == 200, let radio = response.data else {
            throw APIError.business(code: response.code, message: "获取电台详情失败")
        }
        return radio
    }

    /// 歌手列表（area: -1 全部 / 7 华语 / 96 欧美 / 8 日本 / 16 韩国）
    func artistList(
        area: String,
        limit: Int = 60,
        offset: Int = 0,
        cookie: String?
    ) async throws -> [ArtistSummary] {
        let response: ArtistListResponse = try await get(
            "/artist/list",
            query: [
                "type": "-1",
                "area": area,
                "initial": "-1",
                "limit": "\(limit)",
                "offset": "\(offset)"
            ],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取歌手列表失败")
        }
        return response.artists ?? []
    }
}
