import Foundation

/// 播放模式
enum RepeatMode: String, CaseIterable, Identifiable {
    case off
    case all
    case one

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "顺序播放"
        case .all: return "列表循环"
        case .one: return "单曲循环"
        }
    }

    var symbol: String {
        switch self {
        case .off: return "arrow.right"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

/// 时间显示格式
enum TimeFormatMode: String, CaseIterable, Identifiable {
    case currentTotal
    case remainingTotal
    case currentRemaining

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentTotal: return "播放时间 / 总时长"
        case .remainingTotal: return "剩余时间 / 总时长"
        case .currentRemaining: return "播放时间 / 剩余时间"
        }
    }
}

/// 本地配置（UserDefaults），键名与原版 SPlayer-Next 设置项保持一致
enum AppSettings {
    /// 默认 API 地址（局域网自建 NeteaseCloudMusicApi Enhanced）
    static let defaultBaseURL = "http://192.168.1.244:3000"

    private static var store: UserDefaults { .standard }

    private static func boolValue(_ key: String, _ fallback: Bool) -> Bool {
        store.object(forKey: key) == nil ? fallback : store.bool(forKey: key)
    }

    private static func doubleValue(_ key: String, _ fallback: Double) -> Double {
        store.object(forKey: key) == nil ? fallback : store.double(forKey: key)
    }

    private static func intValue(_ key: String, _ fallback: Int) -> Int {
        store.object(forKey: key) == nil ? fallback : store.integer(forKey: key)
    }

    private static func stringValue(_ key: String, _ fallback: String) -> String {
        store.string(forKey: key) ?? fallback
    }

    // MARK: - 网络

    static var baseURL: String {
        get {
            let value = stringValue("apiBaseURL", "")
            return value.isEmpty ? defaultBaseURL : value
        }
        set { store.set(newValue, forKey: "apiBaseURL") }
    }

    /// 是否使用内置 API 服务（Rust 本地服务），默认开启
    static var useBuiltinAPI: Bool {
        get { boolValue("useBuiltinAPI", true) }
        set { store.set(newValue, forKey: "useBuiltinAPI") }
    }

    /// 实际请求使用的 API 地址：内置服务优先，启动失败时回退到自建服务器
    static var activeBaseURL: String {
        guard useBuiltinAPI else { return baseURL }
        if BuiltinAPIService.shared.start(), let url = BuiltinAPIService.shared.baseURL {
            return url
        }
        return baseURL
    }

    // MARK: - 常规

    static var autoPlay: Bool {
        get { boolValue("autoPlay", true) }
        set { store.set(newValue, forKey: "autoPlay") }
    }

    static var rememberLastTrack: Bool {
        get { boolValue("rememberLastTrack", true) }
        set { store.set(newValue, forKey: "rememberLastTrack") }
    }

    static var showLyricInBar: Bool {
        get { boolValue("showLyricInBar", true) }
        set { store.set(newValue, forKey: "showLyricInBar") }
    }

    /// all / current
    static var searchPlayBehavior: String {
        get { stringValue("searchPlayBehavior", "all") }
        set { store.set(newValue, forKey: "searchPlayBehavior") }
    }

    /// all / current
    static var songListPlayBehavior: String {
        get { stringValue("songListPlayBehavior", "all") }
        set { store.set(newValue, forKey: "songListPlayBehavior") }
    }

    // MARK: - 搜索

    /// 最近搜索关键词（最多 10 条，最新在前）
    static var searchHistory: [String] {
        get { store.stringArray(forKey: "searchHistory") ?? [] }
        set { store.set(Array(newValue.prefix(10)), forKey: "searchHistory") }
    }

    static func addSearchHistory(_ keyword: String) {
        let value = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        var items = searchHistory
        items.removeAll { $0.caseInsensitiveCompare(value) == .orderedSame }
        items.insert(value, at: 0)
        searchHistory = items
    }

    static func clearSearchHistory() {
        store.removeObject(forKey: "searchHistory")
    }

    // MARK: - 播放

    /// standard / higher / exhigh / lossless / hires
    static var audioLevel: String {
        get { stringValue("audioLevel", "exhigh") }
        set { store.set(newValue, forKey: "audioLevel") }
    }

    static let audioLevels: [(value: String, label: String)] = [
        ("standard", "标准 (LQ)"),
        ("higher", "较高 (SQ)"),
        ("exhigh", "极高 (HQ)"),
        ("lossless", "无损 (Lossless)"),
        ("hires", "高解析度无损 (Hi-Res)")
    ]

    static var audioLevelLabel: String {
        audioLevels.first(where: { $0.value == audioLevel })?.label ?? "极高 (HQ)"
    }

    static var preloadNextTrack: Bool {
        get { boolValue("preloadNextTrack", false) }
        set { store.set(newValue, forKey: "preloadNextTrack") }
    }

    /// 播放速度（0.5x ~ 2.0x）
    static var playbackRate: Double {
        get {
            let value = doubleValue("playbackRate", 1.0)
            return value > 0 ? value : 1.0
        }
        set { store.set(newValue, forKey: "playbackRate") }
    }

    static let playbackRateOptions: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    static func playbackRateLabel(_ value: Double) -> String {
        value == 1.0 ? "1.0x（正常）" : String(format: "%gx", value)
    }

    static var keepScreenAwake: Bool {
        get { boolValue("keepScreenAwake", true) }
        set { store.set(newValue, forKey: "keepScreenAwake") }
    }

    /// currentTotal / remainingTotal / currentRemaining
    static var timeFormat: String {
        get { stringValue("timeFormat", TimeFormatMode.currentTotal.rawValue) }
        set { store.set(newValue, forKey: "timeFormat") }
    }

    // MARK: - 歌词

    static var showTranslation: Bool {
        get { boolValue("showTranslation", true) }
        set { store.set(newValue, forKey: "showTranslation") }
    }

    /// 显示罗马音 / 音译
    static var showRomanization: Bool {
        get { boolValue("showRomanization", false) }
        set { store.set(newValue, forKey: "showRomanization") }
    }

    /// 歌词偏移（秒）：正值让歌词提前显示
    static var lyricOffset: Double {
        get { doubleValue("lyricOffset", 0) }
        set { store.set(newValue, forKey: "lyricOffset") }
    }

    static var lyricFontSize: Double {
        get { doubleValue("lyricFontSize", 22) }
        set { store.set(newValue, forKey: "lyricFontSize") }
    }

    /// auto / left / center / right
    static var lyricAlignment: String {
        get { stringValue("lyricAlignment", "auto") }
        set { store.set(newValue, forKey: "lyricAlignment") }
    }

    static var inactiveAlpha: Double {
        get { doubleValue("inactiveAlpha", 0.45) }
        set { store.set(newValue, forKey: "inactiveAlpha") }
    }

    static var followCoverColor: Bool {
        get { boolValue("followCoverColor", true) }
        set { store.set(newValue, forKey: "followCoverColor") }
    }

    /// 灵动岛 / 锁屏歌词（Live Activity）
    static var liveActivityEnabled: Bool {
        get { boolValue("liveActivityEnabled", true) }
        set { store.set(newValue, forKey: "liveActivityEnabled") }
    }

    // MARK: - 外观

    /// system / light / dark
    static var themeMode: String {
        get { stringValue("themeMode", "system") }
        set { store.set(newValue, forKey: "themeMode") }
    }

    /// default / custom / cover / solid
    static var themeSource: String {
        get { stringValue("themeSource", "default") }
        set { store.set(newValue, forKey: "themeSource") }
    }

    static var customThemeColor: String {
        get { stringValue("customThemeColor", "FE7971") }
        set { store.set(newValue, forKey: "customThemeColor") }
    }

    /// solid / image
    static var appearanceStyle: String {
        get { stringValue("appearanceStyle", "solid") }
        set { store.set(newValue, forKey: "appearanceStyle") }
    }

    static var backgroundBlur: Double {
        get { doubleValue("backgroundBlur", 20) }
        set { store.set(newValue, forKey: "backgroundBlur") }
    }

    static var backgroundDim: Double {
        get { doubleValue("backgroundDim", 0.32) }
        set { store.set(newValue, forKey: "backgroundDim") }
    }

    // MARK: - 缓存

    static var enableSongCache: Bool {
        get { boolValue("enableSongCache", true) }
        set { store.set(newValue, forKey: "enableSongCache") }
    }

    /// 0 表示不限制
    static var cacheLimitMB: Int {
        get { intValue("cacheLimitMB", 1024) }
        set { store.set(newValue, forKey: "cacheLimitMB") }
    }

    static let cacheLimitOptions: [Int] = [256, 512, 1024, 2048, 0]

    static func cacheLimitLabel(_ value: Int) -> String {
        value == 0 ? "不限制" : "\(value) MB"
    }

    static var cacheLimitBytes: Int64 {
        Int64(cacheLimitMB) * 1024 * 1024
    }

    // MARK: - 重置

    private static let allKeys = [
        "apiBaseURL", "useBuiltinAPI", "audioLevel", "autoPlay", "rememberLastTrack", "showLyricInBar",
        "searchPlayBehavior", "songListPlayBehavior", "searchHistory", "preloadNextTrack", "playbackRate", "keepScreenAwake",
        "timeFormat", "showTranslation", "showRomanization", "lyricOffset", "lyricFontSize", "lyricAlignment", "inactiveAlpha",
        "followCoverColor", "liveActivityEnabled", "themeMode", "themeSource", "customThemeColor",
        "appearanceStyle", "backgroundBlur", "backgroundDim", "backgroundRevision",
        "enableSongCache", "cacheLimitMB", "repeatMode", "shuffleEnabled", "playbackSnapshot",
        "updateChannel", "autoCheckUpdate", "fullPlayerCoverStyle"
    ]

    /// 恢复默认设置（不影响登录态与缓存文件）
    static func resetAll() {
        for key in allKeys {
            store.removeObject(forKey: key)
        }
    }
}
