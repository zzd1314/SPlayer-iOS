import Foundation

/// 内置网易云 API 服务（Rust `ncm-api-rs`）
///
/// App 启动后在 `127.0.0.1` 上运行本地 HTTP 服务，`NeteaseAPI` 直接访问该地址，
/// 不再依赖外部自建服务器。服务随 App 进程结束，仅监听本机，不对外网开放。
final class BuiltinAPIService {
    static let shared = BuiltinAPIService()

    /// 本地服务根地址，例如 `http://127.0.0.1:3000`
    private(set) var baseURL: String?
    /// 实际监听端口
    private(set) var port: UInt16 = 0
    /// 最近一次启动失败的原因
    private(set) var lastError: String?

    var isRunning: Bool { baseURL != nil }

    private let lock = NSLock()

    private init() {}

    /// 启动内置服务；已运行时直接返回成功，失败后再次调用会重试。
    @discardableResult
    func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if isRunning { return true }

        let result = ncm_start_server(3000)
        guard result > 0 else {
            lastError = "内置 API 服务启动失败（错误码 \(result)）"
            return false
        }

        port = UInt16(result)
        baseURL = "http://127.0.0.1:\(port)"
        lastError = nil
        return true
    }

    /// 探活专用会话：不复用连接，避免把失效的连接池误判成服务可用
    private let probeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// 回到前台、或请求连不上本地服务时调用。
    ///
    /// 设备长时间休眠后本地监听可能已经失效，此时仅重试请求没有用：
    /// 先探活，确认连不上就强制重启服务，并更新为新端口。
    func recoverIfNeeded() async {
        let current = baseURL ?? AppSettings.baseURL
        if await probe(current) { return }

        let result = ncm_restart_server(3000)
        guard result > 0 else {
            lastError = "内置 API 服务重启失败（错误码 \(result)）"
            return
        }

        lock.lock()
        port = UInt16(result)
        baseURL = "http://127.0.0.1:\(result)"
        lastError = nil
        lock.unlock()

        _ = await probe(baseURL ?? current)
    }

    /// 轻量探活：收到任意 HTTP 响应即视为服务可用
    private func probe(_ base: String) async -> Bool {
        guard let url = URL(string: base + "/login/status") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("close", forHTTPHeaderField: "Connection")
        do {
            _ = try await probeSession.data(for: request)
            return true
        } catch {
            return false
        }
    }
}
