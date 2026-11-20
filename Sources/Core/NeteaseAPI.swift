import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int)
    case business(code: Int, message: String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "API 地址无效，请在设置中检查"
        case .http(let code):
            return "网络错误（HTTP \(code)）"
        case .business(let code, let message):
            return message ?? "接口错误（\(code)）"
        case .invalidResponse:
            return "响应解析失败"
        }
    }
}

/// 网易云音乐接口客户端
struct NeteaseAPI {
    var baseURL: String

    init(baseURL: String = AppSettings.baseURL) {
        self.baseURL = baseURL
    }

    /// GET 请求；`cookie` 非空时写入 Cookie 头（形如 `MUSIC_U=xxx`）
    func get<T: Decodable>(
        _ path: String,
        query: [String: String] = [:],
        cookie: String? = nil
    ) async throws -> T {
        guard var components = URLComponents(string: baseURL) else {
            throw APIError.badURL
        }
        components.path = path
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        // 避免 CDN / 代理缓存登录态接口
        items.append(URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1000))))
        components.queryItems = items

        guard let url = components.url else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if let cookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw APIError.business(code: envelope.code, message: envelope.msg ?? envelope.message)
            }
            throw APIError.invalidResponse
        }
    }
}

private struct ErrorEnvelope: Decodable {
    let code: Int
    let msg: String?
    let message: String?
}

// MARK: - 登录 / 账号

struct QRKeyResponse: Decodable {
    struct Payload: Decodable { let unikey: String }
    let code: Int
    let data: Payload?
}

struct QRCreateResponse: Decodable {
    struct Payload: Decodable {
        let qrurl: String
        let qrimg: String?
    }
    let code: Int
    let data: Payload?
}

struct QRCheckResponse: Decodable {
    let code: Int
    let cookie: String?
    let message: String?
}

struct AccountProfile: Decodable, Equatable {
    let userId: Int
    let nickname: String
    let avatarUrl: String?
}

struct AccountResponse: Decodable {
    let code: Int
    let profile: AccountProfile?
}

extension NeteaseAPI {
    /// 获取二维码 key
    func qrKey() async throws -> String {
        let response: QRKeyResponse = try await get("/login/qr/key")
        guard let key = response.data?.unikey else {
            throw APIError.business(code: response.code, message: "无法获取二维码，请检查 API 服务")
        }
        return key
    }

    /// 生成二维码（qrimg 为 data URL 形式的 base64 图片）
    func qrCreate(key: String) async throws -> (url: String, image: String?) {
        let response: QRCreateResponse = try await get("/login/qr/create", query: [
            "key": key,
            "qrimg": "true"
        ])
        guard let payload = response.data else {
            throw APIError.business(code: response.code, message: "二维码生成失败")
        }
        return (payload.qrurl, payload.qrimg)
    }

    /// 轮询扫码状态：800 过期 / 801 未扫码 / 802 待确认 / 803 成功
    func qrCheck(key: String) async throws -> QRCheckResponse {
        try await get("/login/qr/check", query: ["key": key])
    }

    /// 当前登录账号
    func account(cookie: String) async throws -> AccountProfile? {
        let response: AccountResponse = try await get("/user/account", cookie: cookie)
        return response.profile
    }
}

extension NeteaseAPI {
    /// 从 `data:image/png;base64,...` 中取出图片数据
    static func imageData(fromDataURL dataURL: String) -> Data? {
        let base64 = dataURL.components(separatedBy: ",").last ?? dataURL
        return Data(base64Encoded: base64)
    }
}
