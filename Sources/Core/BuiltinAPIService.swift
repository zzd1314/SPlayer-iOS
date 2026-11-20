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
}
