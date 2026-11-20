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
            if code == 400 || code == 403 {
                return "请求被服务端拒绝（HTTP \(code)），请检查 API 地址，或稍后改用扫码登录"
            }
            return "网络错误（HTTP \(code)）"
        case .business(let code, let message):
            if APIError.riskControlCodes.contains(code) {
                return "登录触发网易云安全验证，请改用密码登录或扫码登录"
            }
            return message ?? "接口错误（\(code)）"
        case .invalidResponse:
            return "响应解析失败"
        }
    }

    /// 网易云风控类错误码：登录被判定为异常时返回
    static let riskControlCodes: Set<Int> = [-460, -461, -462, -463, -447]
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
            throw Self.serverError(from: data, status: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw APIError.business(code: envelope.code ?? -1, message: envelope.msg ?? envelope.message)
            }
            throw APIError.invalidResponse
        }
    }

    /// POST 表单请求：登录、验证码等含凭据的接口，避免把参数放在 URL 上
    func post<T: Decodable>(
        _ path: String,
        fields: [String: String] = [:],
        cookie: String? = nil
    ) async throws -> T {
        guard var components = URLComponents(string: baseURL) else {
            throw APIError.badURL
        }
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1000)))
        ]
        guard let url = components.url else { throw APIError.badURL }

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)
        if let cookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Self.serverError(from: data, status: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw APIError.business(code: envelope.code ?? -1, message: envelope.msg ?? envelope.message)
            }
            throw APIError.invalidResponse
        }
    }

    /// 非 2xx 时尽量取出服务端 JSON 里的原因，避免只显示「HTTP 400」
    private static func serverError(from data: Data, status: Int) -> APIError {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            let text = envelope.message ?? envelope.msg
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .business(code: envelope.code ?? status, message: text)
            }
        }
        return .http(status)
    }

    /// 登录类错误统一补充可操作提示
    private static func authError(_ error: APIError, action: String) -> APIError {
        switch error {
        case .http(400), .http(403):
            return .business(
                code: 400,
                message: "\(action)请求被服务端拒绝，可能触发了网易云安全验证。请改用密码登录或扫码登录"
            )
        case .business(let code, let message):
            if APIError.riskControlCodes.contains(code) {
                return .business(code: code, message: "\(action)触发网易云安全验证，请改用密码登录或扫码登录")
            }
            return .business(code: code, message: message)
        default:
            return error
        }
    }

    /// POST multipart/form-data（文件上传）
    func postMultipart<T: Decodable>(
        _ path: String,
        fields: [String: String] = [:],
        fileField: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        cookie: String? = nil
    ) async throws -> T {
        guard var components = URLComponents(string: baseURL) else {
            throw APIError.badURL
        }
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1000)))
        ]
        guard let url = components.url else { throw APIError.badURL }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for (key, value) in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body
        if let cookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Self.serverError(from: data, status: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw APIError.business(code: envelope.code ?? -1, message: envelope.msg ?? envelope.message)
            }
            throw APIError.invalidResponse
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

private struct ErrorEnvelope: Decodable {
    let code: Int?
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

struct CaptchaResponse: Decodable {
    let code: Int
    let message: String?
    let msg: String?
}

struct LoginResponse: Decodable {
    let code: Int
    let cookie: String?
    let message: String?
    let msg: String?
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

    /// 发送验证码：手机号或邮箱二选一（POST 表单，避免凭据出现在 URL）
    func sendCaptcha(phone: String? = nil, email: String? = nil, countryCode: String = "86") async throws {
        var fields: [String: String] = [:]
        if let phone, !phone.isEmpty {
            fields["phone"] = phone
            fields["ctcode"] = countryCode
        } else if let email, !email.isEmpty {
            fields["email"] = email
        } else {
            throw APIError.business(code: -1, message: "请输入手机号或邮箱")
        }

        let response: CaptchaResponse
        do {
            response = try await post("/captcha/sent", fields: fields)
        } catch let error as APIError {
            throw Self.authError(error, action: "发送验证码")
        }
        guard response.code == 200 else {
            let text = response.message ?? response.msg ?? "验证码发送失败"
            if text.contains("风险") || text.contains("安全") {
                throw APIError.business(code: response.code, message: "\(text)。请改用密码登录或扫码登录")
            }
            throw APIError.business(code: response.code, message: text)
        }
    }

    /// 手机号 + 验证码登录
    func loginCellphone(phone: String, captcha: String, countryCode: String) async throws -> String {
        try await cellphoneLogin(fields: [
            "phone": phone,
            "captcha": captcha,
            "countrycode": countryCode
        ])
    }

    /// 手机号 + 密码登录（验证码登录被风控拦截时的替代方式）
    func loginCellphone(phone: String, password: String, countryCode: String) async throws -> String {
        try await cellphoneLogin(fields: [
            "phone": phone,
            "password": password,
            "countrycode": countryCode
        ])
    }

    private func cellphoneLogin(fields: [String: String]) async throws -> String {
        let response: LoginResponse
        do {
            response = try await post("/login/cellphone", fields: fields)
        } catch let error as APIError {
            throw Self.authError(error, action: "登录")
        }
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: Self.loginMessage(
                    code: response.code,
                    text: response.message ?? response.msg ?? "登录失败（\(response.code)）"
                )
            )
        }
        guard let cookie = response.cookie, !cookie.isEmpty else {
            throw APIError.business(code: -1, message: "登录返回的 Cookie 为空，请重试")
        }
        return cookie
    }

    /// 邮箱 + 验证码登录
    func loginEmail(email: String, captcha: String) async throws -> String {
        let response: LoginResponse
        do {
            response = try await post("/login", fields: [
                "email": email,
                "captcha": captcha
            ])
        } catch let error as APIError {
            throw Self.authError(error, action: "登录")
        }
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: Self.loginMessage(
                    code: response.code,
                    text: response.message ?? response.msg ?? "登录失败（\(response.code)）"
                )
            )
        }
        guard let cookie = response.cookie, !cookie.isEmpty else {
            throw APIError.business(code: -1, message: "登录返回的 Cookie 为空，请重试")
        }
        return cookie
    }

    /// 登录失败的文案：风控类错误给出替代方案
    private static func loginMessage(code: Int, text: String) -> String {
        if APIError.riskControlCodes.contains(code) || text.contains("安全风险") || text.contains("风险") {
            return "\(text)。请改用密码登录或扫码登录"
        }
        return text
    }
}

extension NeteaseAPI {
    /// 从 `data:image/png;base64,...` 中取出图片数据
    static func imageData(fromDataURL dataURL: String) -> Data? {
        let base64 = dataURL.components(separatedBy: ",").last ?? dataURL
        return Data(base64Encoded: base64)
    }
}
