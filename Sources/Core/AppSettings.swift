import Foundation

/// 本地配置（UserDefaults）
enum AppSettings {
    /// 默认 API 地址（局域网自建 NeteaseCloudMusicApi Enhanced）
    static let defaultBaseURL = "http://192.168.1.244:3000"

    private static let baseURLKey = "apiBaseURL"

    static var baseURL: String {
        get {
            let value = UserDefaults.standard.string(forKey: baseURLKey) ?? ""
            return value.isEmpty ? defaultBaseURL : value
        }
        set {
            UserDefaults.standard.set(newValue, forKey: baseURLKey)
        }
    }
}
