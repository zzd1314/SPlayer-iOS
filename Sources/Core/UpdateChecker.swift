import Foundation

// MARK: - 发布信息

/// GitHub Release 数据模型
struct AppRelease: Identifiable, Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let id: Int
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let prerelease: Bool
    let publishedAt: Date?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case body
        case prerelease
        case assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }

    /// 去掉前缀 v 的版本号
    var version: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return "SPlayer-iOS \(tagName)"
    }

    var ipaURL: URL? {
        assets.first { $0.name.lowercased().hasSuffix(".ipa") }?.browserDownloadURL
    }
}

// MARK: - 更新检查

/// 通过 GitHub Releases 检查新版本。
/// iOS 未签名 IPA 无法静默安装，因此这里只负责版本提示与下载入口。
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case failed(String)
    }

    static let shared = UpdateChecker()

    @Published private(set) var state: State = .idle
    @Published private(set) var latestRelease: AppRelease?
    /// 手动检查发现新版本时用于弹出更新说明
    @Published var presentedRelease: AppRelease?
    /// 手动检查的结果提示
    @Published var alertMessage: String?

    private let owner = "zzd1314"
    private let repo = "SPlayer-iOS"
    private let lastCheckKey = "lastUpdateCheckDate"

    var hasUpdate: Bool {
        if case .updateAvailable = state {
            return latestRelease != nil
        }
        return false
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: 对外入口

    /// 启动后按开关与频率自动检查
    func autoCheckIfNeeded() async {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "autoCheckUpdate") as? Bool ?? true
        guard enabled else { return }

        if let last = defaults.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }

        await check(manual: false)
    }

    /// 检查更新；manual 为 true 时会展示结果提示或更新说明
    func check(manual: Bool) async {
        guard state != .checking else { return }
        state = .checking
        latestRelease = nil

        do {
            let release = try await fetchLatestRelease()
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)

            guard let release, Self.isNewer(release.version, than: currentVersion) else {
                state = .upToDate
                if manual {
                    alertMessage = "当前已是最新版本 v\(currentVersion)"
                }
                return
            }

            latestRelease = release
            state = .updateAvailable
            if manual {
                presentedRelease = release
            }
        } catch {
            state = .failed(error.localizedDescription)
            if manual {
                alertMessage = "检查更新失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: 网络

    private var channel: String {
        UserDefaults.standard.string(forKey: "updateChannel") ?? "stable"
    }

    private func fetchLatestRelease() async throws -> AppRelease? {
        let base = "https://api.github.com/repos/\(owner)/\(repo)/releases"

        if channel == "stable" {
            do {
                return try await request(AppRelease.self, from: base + "/latest")
            } catch UpdateError.noRelease {
                return nil
            }
        }

        let releases: [AppRelease] = try await request([AppRelease].self, from: base + "?per_page=20")
        return releases.first
    }

    private func request<T: Decodable>(_ type: T.Type, from urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw UpdateError.invalidURL }

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 20
        urlRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("SPlayer-iOS", forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
        if http.statusCode == 404 { throw UpdateError.noRelease }
        guard (200..<300).contains(http.statusCode) else { throw UpdateError.http(http.statusCode) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    // MARK: 版本比较

    /// 仅比较数字段，例如 v1.2.0-beta.1 视为 1.2.0
    static func isNewer(_ remote: String, than current: String) -> Bool {
        let remoteParts = numericParts(remote)
        let currentParts = numericParts(current)
        let count = max(remoteParts.count, currentParts.count)

        for index in 0..<count {
            let remoteValue = index < remoteParts.count ? remoteParts[index] : 0
            let currentValue = index < currentParts.count ? currentParts[index] : 0
            if remoteValue != currentValue {
                return remoteValue > currentValue
            }
        }
        return false
    }

    private static func numericParts(_ version: String) -> [Int] {
        let trimmed = version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let core = trimmed.split(separator: "-", maxSplits: 1).first.map(String.init) ?? trimmed
        return core.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
    }
}

enum UpdateError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noRelease
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "更新地址无效"
        case .invalidResponse: return "网络响应异常"
        case .noRelease: return "暂无可用版本"
        case .http(let code): return "服务返回错误（\(code)）"
        }
    }
}
