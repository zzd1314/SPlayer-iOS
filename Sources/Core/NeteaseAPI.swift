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

    init(baseURL: String = AppSettings.activeBaseURL) {
        self.baseURL = baseURL
    }

    /// 共享会话：不使用磁盘缓存，避免长连接在设备休眠后滞留
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// 发送请求；设备休眠唤醒后首个请求容易命中已失效的连接或遇到服务端 5xx，自动重试
    private static func send(_ request: URLRequest, retries: Int = 2) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse,
                   [500, 502, 503, 504].contains(http.statusCode),
                   attempt < retries {
                    attempt += 1
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 600_000_000)
                    continue
                }
                return (data, response)
            } catch {
                if isTransient(error), attempt < retries {
                    attempt += 1
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 600_000_000)
                    continue
                }
                // 本地服务连不上：可能是长时间休眠后监听失效，重启服务后用新端口再试一次
                if let url = request.url,
                   url.host == "127.0.0.1",
                   shouldRecover(error),
                   let retried = await retryAfterRecovery(request) {
                    return retried
                }
                throw error
            }
        }
    }

    /// 只有"服务无响应/拒绝连接"这类错误才值得重启本地服务
    private static func shouldRecover(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        switch ns.code {
        case NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost,
             NSURLErrorNetworkConnectionLost:
            return true
        default:
            return false
        }
    }

    /// 重启本地服务，并把请求切到新端口用全新会话重试
    private static func retryAfterRecovery(_ request: URLRequest) async -> (Data, URLResponse)? {
        await BuiltinAPIService.shared.recoverIfNeeded()
        guard let base = BuiltinAPIService.shared.baseURL,
              var components = URLComponents(string: base),
              let old = request.url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        else { return nil }
        components.path = old.path
        components.percentEncodedQuery = old.percentEncodedQuery
        guard let url = components.url else { return nil }

        var newRequest = request
        newRequest.url = url
        let fresh = URLSession(configuration: session.configuration)
        defer { fresh.finishTasksAndInvalidate() }
        return try? await fresh.data(for: newRequest)
    }

    /// 休眠唤醒、切换网络时常见的瞬时错误，值得立即重试
    private static func isTransient(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        switch ns.code {
        case NSURLErrorNetworkConnectionLost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorTimedOut,
             NSURLErrorNotConnectedToInternet:
            return true
        default:
            return false
        }
    }

    /// GET 请求；`cookie` 非空时写入 Cookie 头（形如 `MUSIC_U=xxx`）
    func get<T: Decodable>(
        _ path: String,
        query: [String: String] = [:],
        cookie: String? = nil
    ) async throws -> T {
        let data = try await getData(path, query: query, cookie: cookie)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw APIError.business(code: envelope.code ?? -1, message: envelope.msg ?? envelope.message)
            }
            throw APIError.invalidResponse
        }
    }

    /// GET 原始响应体，供需要宽松解析的接口使用（个别异常条目不至于拖垮整段解码）
    func getData(
        _ path: String,
        query: [String: String] = [:],
        cookie: String? = nil
    ) async throws -> Data {
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

        let (data, response) = try await Self.send(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Self.serverError(from: data, status: http.statusCode)
        }
        return data
    }

    /// GET 并同时返回响应头里的会话 Cookie（扫码登录成功时内置服务只写 Set-Cookie）
    func getWithCookies<T: Decodable>(
        _ path: String,
        query: [String: String] = [:],
        cookie: String? = nil
    ) async throws -> (value: T, cookies: String) {
        guard var components = URLComponents(string: baseURL) else {
            throw APIError.badURL
        }
        components.path = path
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1000))))
        components.queryItems = items

        guard let url = components.url else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if let cookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await Self.send(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Self.serverError(from: data, status: http.statusCode)
        }

        do {
            let value = try JSONDecoder().decode(T.self, from: data)
            return (value, Self.cookieString(from: response as? HTTPURLResponse))
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
        try await postResponse(path, fields: fields, cookie: cookie).value
    }

    /// POST 表单，并返回响应头里的会话 Cookie（内置服务的登录响应不带 cookie 字段）
    func postResponse<T: Decodable>(
        _ path: String,
        fields: [String: String] = [:],
        cookie: String? = nil
    ) async throws -> (value: T, cookies: String) {
        guard var components = URLComponents(string: baseURL) else {
            throw APIError.badURL
        }
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1000)))
        ]
        guard let url = components.url else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Self.formEncode(fields).data(using: .utf8)
        if let cookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await Self.send(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Self.serverError(from: data, status: http.statusCode)
        }

        do {
            let value = try JSONDecoder().decode(T.self, from: data)
            return (value, Self.cookieString(from: response as? HTTPURLResponse))
        } catch {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw APIError.business(code: envelope.code ?? -1, message: envelope.msg ?? envelope.message)
            }
            throw APIError.invalidResponse
        }
    }

    /// 严格表单编码：`+ & = %` 等字符全部转义，避免密码被服务端按表单规则改写
    private static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }

    /// 从响应头 Set-Cookie 提取会话 Cookie（多个头会被系统合并，按已知字段名匹配取值）
    static func cookieString(from http: HTTPURLResponse?) -> String {
        guard let http else { return "" }
        let raw = http.allHeaderFields
            .filter { ($0.key as? String)?.lowercased() == "set-cookie" }
            .map { String(describing: $0.value) }
            .joined(separator: "; ")
        guard !raw.isEmpty else { return "" }

        let names = ["MUSIC_U", "MUSIC_A", "__csrf", "NMTID", "_ntes_nuid", "__remember_me"]
        var parts: [String] = []
        for name in names {
            guard let range = raw.range(of: "\(name)=") else { continue }
            let value = raw[range.upperBound...].prefix { $0 != ";" && $0 != "," && !$0.isWhitespace }
            if !value.isEmpty { parts.append("\(name)=\(value)") }
        }
        return parts.joined(separator: "; ")
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

        let (data, response) = try await Self.send(request)
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
        let result: (value: QRCheckResponse, cookies: String) = try await getWithCookies(
            "/login/qr/check",
            query: ["key": key]
        )
        var response = result.value
        // 扫码成功时部分服务端只在 Set-Cookie 中下发会话，body 里没有 cookie 字段
        if (response.cookie ?? "").isEmpty, !result.cookies.isEmpty {
            response = QRCheckResponse(code: response.code, cookie: result.cookies, message: response.message)
        }
        return response
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
        let result: (value: LoginResponse, cookies: String)
        do {
            result = try await postResponse("/login/cellphone", fields: fields)
        } catch let error as APIError {
            throw Self.authError(error, action: "登录")
        }
        let response = result.value
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: Self.loginMessage(
                    code: response.code,
                    text: response.message ?? response.msg ?? "登录失败（\(response.code)）"
                )
            )
        }
        // 内置服务只在响应头写 Set-Cookie，标准服务则在 body 返回 cookie，两者都兼容
        let bodyCookie = response.cookie ?? ""
        let cookie = bodyCookie.isEmpty ? result.cookies : bodyCookie
        guard !cookie.isEmpty else {
            throw APIError.business(code: -1, message: "登录返回的 Cookie 为空，请重试")
        }
        return cookie
    }

    /// 邮箱 + 验证码登录
    func loginEmail(email: String, captcha: String) async throws -> String {
        let result: (value: LoginResponse, cookies: String)
        do {
            result = try await postResponse("/login", fields: [
                "email": email,
                "captcha": captcha
            ])
        } catch let error as APIError {
            throw Self.authError(error, action: "登录")
        }
        let response = result.value
        guard response.code == 200 else {
            throw APIError.business(
                code: response.code,
                message: Self.loginMessage(
                    code: response.code,
                    text: response.message ?? response.msg ?? "登录失败（\(response.code)）"
                )
            )
        }
        let bodyCookie = response.cookie ?? ""
        let cookie = bodyCookie.isEmpty ? result.cookies : bodyCookie
        guard !cookie.isEmpty else {
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
