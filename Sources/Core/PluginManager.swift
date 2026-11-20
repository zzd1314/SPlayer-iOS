import Combine
import Foundation

/// 插件管理：安装 / 卸载 / 启用 / 配置 / 市场与更新，并持有 JS 运行时
@MainActor
final class PluginManager: ObservableObject {
    static let shared = PluginManager()
    static let maxScriptSize = 2 * 1024 * 1024
    static let marketURLString = "https://raw.githubusercontent.com/SPlayer-Dev/plugins/registry/registry.json"

    @Published private(set) var plugins: [InstalledPlugin] = []
    @Published private(set) var marketPlugins: [MarketPlugin] = []
    @Published private(set) var isLoadingMarket = false
    @Published private(set) var marketError: String?
    @Published private(set) var installingIDs: Set<String> = []
    @Published private(set) var registrations: [String: PluginRegistration] = [:]
    @Published private(set) var runtimeErrors: [String: String] = [:]

    private let fileManager = FileManager.default
    private let rootDirectory: URL
    private let scriptsDirectory: URL
    private let dataDirectory: URL
    private let manifestURL: URL
    private let runtime = PluginRuntime()
    private var storageCache: [String: [String: String]] = [:]
    private var isStarted = false

    private init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootDirectory = base.appendingPathComponent("SPlayerPlugins", isDirectory: true)
        scriptsDirectory = rootDirectory.appendingPathComponent("scripts", isDirectory: true)
        dataDirectory = rootDirectory.appendingPathComponent("data", isDirectory: true)
        manifestURL = rootDirectory.appendingPathComponent("manifest.json")

        try? fileManager.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

        runtime.manager = self
        loadRecords()
    }

    // MARK: - 生命周期

    /// 启动时加载所有已启用插件（重复调用无副作用）
    func start() {
        guard !isStarted else { return }
        isStarted = true
        for plugin in plugins where plugin.enabled {
            loadRuntime(plugin)
        }
    }

    private func loadRuntime(_ plugin: InstalledPlugin) {
        guard plugin.enabled else {
            runtime.unload(pluginID: plugin.id)
            return
        }

        let url = scriptsDirectory.appendingPathComponent(plugin.scriptFile)
        guard let script = try? String(contentsOf: url, encoding: .utf8) else {
            runtime.unload(pluginID: plugin.id)
            setRuntimeError(pluginID: plugin.id, message: "插件脚本缺失，请重新安装")
            return
        }
        runtime.load(pluginID: plugin.id, script: script)
    }

    // MARK: - 安装与卸载

    @discardableResult
    func install(script: String, origin: String) throws -> PluginInstallResult {
        guard script.utf8.count <= Self.maxScriptSize else { throw PluginError.scriptTooLarge }

        let manifest = try PluginManifest(script: script)
        let existingIndex = plugins.firstIndex { $0.id == manifest.id }
        let existing = existingIndex.map { plugins[$0] }

        var record = InstalledPlugin(manifest: manifest)
        record.enabled = existing?.enabled ?? true
        record.settingValues = existing?.settingValues ?? [:]
        record.settingsSchema = existing?.settingsSchema
        record.installedAt = existing?.installedAt ?? Date()
        record.scriptFile = "\(manifest.id).js"

        try script.write(
            to: scriptsDirectory.appendingPathComponent(record.scriptFile),
            atomically: true,
            encoding: .utf8
        )

        if let existingIndex {
            plugins[existingIndex] = record
        } else {
            plugins.append(record)
        }
        sortPlugins()
        persist()

        if record.enabled {
            loadRuntime(record)
        } else {
            runtime.unload(pluginID: record.id)
        }

        NSLog("[Plugin] 已安装 %@ v%@（来源：%@）", record.name, record.version, origin)

        return PluginInstallResult(
            plugin: record,
            isUpdate: existing != nil,
            previousVersion: existing?.version
        )
    }

    func installFromURL(_ urlString: String) async throws -> PluginInstallResult {
        let script = try await downloadScript(from: urlString)
        return try install(script: script, origin: urlString)
    }

    func installFromMarket(_ item: MarketPlugin) async throws -> PluginInstallResult {
        guard let urlString = item.updateUrl, !urlString.isEmpty else { throw PluginError.noDownloadURL }
        installingIDs.insert(item.id)
        defer { installingIDs.remove(item.id) }
        return try await installFromURL(urlString)
    }

    func uninstall(pluginID: String) {
        guard let plugin = plugins.first(where: { $0.id == pluginID }) else { return }

        runtime.unload(pluginID: pluginID)
        plugins.removeAll { $0.id == pluginID }
        registrations[pluginID] = nil
        runtimeErrors[pluginID] = nil
        storageCache[pluginID] = nil

        try? fileManager.removeItem(at: scriptsDirectory.appendingPathComponent(plugin.scriptFile))
        try? fileManager.removeItem(at: dataDirectory.appendingPathComponent("\(pluginID).json"))

        persist()
    }

    func setEnabled(_ enabled: Bool, pluginID: String) {
        guard let index = plugins.firstIndex(where: { $0.id == pluginID }) else { return }
        plugins[index].enabled = enabled
        let plugin = plugins[index]
        persist()

        if enabled {
            loadRuntime(plugin)
        } else {
            runtime.unload(pluginID: pluginID)
            setRuntimeError(pluginID: pluginID, message: nil)
        }
    }

    func isInstalled(marketID: String) -> Bool {
        let normalized = PluginManifest.normalizedID(marketID)
        return plugins.contains { $0.id == normalized || $0.id == marketID.lowercased() }
    }

    // MARK: - 更新

    func checkUpdate(pluginID: String) async throws -> PluginUpdateResult {
        guard let plugin = plugins.first(where: { $0.id == pluginID }) else { throw PluginError.pluginNotFound }
        guard let updateURL = plugin.updateURL, !updateURL.isEmpty else { throw PluginError.noUpdateURL }

        installingIDs.insert(pluginID)
        defer { installingIDs.remove(pluginID) }

        let script = try await downloadScript(from: updateURL)
        let manifest = try PluginManifest(script: script)
        guard UpdateChecker.isNewer(manifest.version, than: plugin.version) else {
            return .upToDate(plugin.version)
        }

        let result = try install(script: script, origin: updateURL)
        return .updated(from: plugin.version, to: result.plugin.version)
    }

    // MARK: - 设置

    func settings(for pluginID: String) -> [PluginSetting] {
        if let registration = registrations[pluginID] {
            return registration.settings
        }
        return plugins.first { $0.id == pluginID }?.settingsSchema ?? []
    }

    func settingValue(pluginID: String, key: String) -> PluginValue? {
        guard let plugin = plugins.first(where: { $0.id == pluginID }) else { return nil }
        if let value = plugin.settingValues[key] {
            return value
        }
        return settings(for: pluginID).first { $0.key == key }?.defaultValue
    }

    func settingValueJSON(pluginID: String, key: String) -> String? {
        settingValue(pluginID: pluginID, key: key)?.jsonText
    }

    func updateSetting(pluginID: String, key: String, value: PluginValue) {
        guard let index = plugins.firstIndex(where: { $0.id == pluginID }) else { return }
        plugins[index].settingValues[key] = value
        persist()
        runtime.dispatchSettingChange(pluginID: pluginID, key: key, valueJSON: value.jsonText)
    }

    func applyRegistration(
        pluginID: String,
        settings: [PluginSetting],
        menus: [PluginMenu],
        sources: [String: PluginSource]
    ) {
        registrations[pluginID] = PluginRegistration(settings: settings, menus: menus, sources: sources)

        guard let index = plugins.firstIndex(where: { $0.id == pluginID }) else { return }
        if plugins[index].settingsSchema != settings {
            plugins[index].settingsSchema = settings
            persist()
        }
    }

    // MARK: - 音源兜底

    /// 官方接口失败时，按安装顺序尝试声明了对应能力的插件
    private func sourcePlugins(source: String, action: String) -> [InstalledPlugin] {
        plugins.filter { plugin in
            plugin.enabled &&
                runtime.isLoaded(pluginID: plugin.id) &&
                registrations[plugin.id]?.sources[source]?.actions.contains(action) == true
        }
    }

    /// 官方播放地址不可用（VIP / 无版权 / 上游故障）时，用插件解析直链
    func resolvePlaybackURL(for song: Song) async -> URL? {
        for plugin in sourcePlugins(source: "wy", action: "musicUrl") {
            let payload: [String: Any] = [
                "source": "wy",
                "quality": Self.pluginQuality(for: AppSettings.audioLevel),
                "musicInfo": Self.musicInfoPayload(song)
            ]
            do {
                let result = try await runtime.callSource(
                    pluginID: plugin.id,
                    action: "musicUrl",
                    payload: payload
                )
                guard let dictionary = result as? [String: Any],
                      let raw = dictionary["url"] as? String,
                      let url = URL(string: raw),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else { continue }
                NSLog("[Plugin] %@ 提供播放地址：%@", plugin.name, url.absoluteString)
                return url
            } catch {
                handleLog(pluginID: plugin.id, level: "warn", message: "musicUrl 失败：\(error.localizedDescription)")
            }
        }
        return nil
    }

    /// 官方歌词缺失时，用插件获取歌词（LRC / 逐字文本）
    func resolveLyric(for song: Song) async -> (text: String, wordText: String?)? {
        for plugin in sourcePlugins(source: "wy", action: "musicLyric") {
            let payload: [String: Any] = [
                "source": "wy",
                "quality": Self.pluginQuality(for: AppSettings.audioLevel),
                "musicInfo": Self.musicInfoPayload(song)
            ]
            do {
                let result = try await runtime.callSource(
                    pluginID: plugin.id,
                    action: "musicLyric",
                    payload: payload,
                    timeout: 15
                )
                guard let dictionary = result as? [String: Any] else { continue }
                let text = (dictionary["lyric"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let wordText = (dictionary["awlyric"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                NSLog("[Plugin] %@ 提供歌词（%ld 字符）", plugin.name, text.count)
                return (text, wordText?.isEmpty == false ? wordText : nil)
            } catch {
                handleLog(pluginID: plugin.id, level: "warn", message: "musicLyric 失败：\(error.localizedDescription)")
            }
        }
        return nil
    }

    /// 官方封面缺失时，用插件获取封面地址
    func resolveCoverURL(for song: Song) async -> String? {
        for plugin in sourcePlugins(source: "wy", action: "musicPic") {
            let payload: [String: Any] = [
                "source": "wy",
                "musicInfo": Self.musicInfoPayload(song)
            ]
            do {
                let result = try await runtime.callSource(
                    pluginID: plugin.id,
                    action: "musicPic",
                    payload: payload,
                    timeout: 12
                )
                guard let dictionary = result as? [String: Any],
                      let raw = dictionary["url"] as? String,
                      let url = URL(string: raw),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else { continue }
                return raw
            } catch {
                handleLog(pluginID: plugin.id, level: "warn", message: "musicPic 失败：\(error.localizedDescription)")
            }
        }
        return nil
    }

    /// 官方搜索无结果时，用插件补充网易云曲库的匹配结果
    func searchSongsViaPlugins(keyword: String, limit: Int = 30) async -> [Song] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        for plugin in sourcePlugins(source: "wy", action: "musicSearch") {
            let payload: [String: Any] = [
                "source": "wy",
                "keyword": trimmed,
                "page": 1,
                "limit": limit
            ]
            do {
                let result = try await runtime.callSource(
                    pluginID: plugin.id,
                    action: "musicSearch",
                    payload: payload
                )
                guard let dictionary = result as? [String: Any],
                      let list = dictionary["list"] as? [[String: Any]] else { continue }
                let songs = list.compactMap(Self.song(from:))
                if !songs.isEmpty {
                    NSLog("[Plugin] %@ 搜索兜底返回 %ld 首", plugin.name, songs.count)
                    return songs
                }
            } catch {
                handleLog(pluginID: plugin.id, level: "warn", message: "musicSearch 失败：\(error.localizedDescription)")
            }
        }
        return []
    }

    /// iOS 音质档位 → 桌面版插件约定的 quality 名称
    private static func pluginQuality(for level: String) -> String {
        switch level {
        case "standard": return "lq"
        case "higher": return "sq"
        case "exhigh": return "hq"
        case "lossless": return "lossless"
        case "hires": return "hi-res"
        default: return "hq"
        }
    }

    private static func musicInfoPayload(_ song: Song) -> [String: Any] {
        var info: [String: Any] = [
            "id": String(song.id),
            "songId": String(song.id),
            "name": song.name,
            "singer": song.artistText,
            "artists": song.artists.map(\.name),
            "album": song.albumName ?? "",
            "albumName": song.albumName ?? "",
            "duration": song.duration,
            "durationMs": song.duration,
            "source": "wy"
        ]
        if let cover = song.albumPicUrl, !cover.isEmpty {
            info["cover"] = cover
            info["picUrl"] = cover
        }
        return info
    }

    private static func song(from item: [String: Any]) -> Song? {
        let rawID: Int?
        if let number = item["id"] as? NSNumber {
            rawID = number.intValue
        } else if let text = item["id"] as? String {
            rawID = Int(text)
        } else {
            rawID = nil
        }
        guard let id = rawID, id > 0,
              let name = item["name"] as? String, !name.isEmpty else { return nil }

        let singer = (item["singer"] as? String) ?? (item["artist"] as? String) ?? ""
        let artists = singer
            .split(whereSeparator: { "/,;&、，".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { Song.Artist(id: nil, name: $0) }

        let duration: Int
        if let value = item["durationMs"] as? NSNumber {
            duration = value.intValue
        } else if let value = item["duration"] as? NSNumber {
            duration = value.intValue
        } else if let text = item["durationMs"] as? String, let value = Int(text) {
            duration = value
        } else {
            duration = 0
        }

        let album = (item["album"] as? String)?.trimmingCharacters(in: .whitespaces)
        let cover = (item["cover"] as? String) ?? (item["picUrl"] as? String)

        return Song(
            id: id,
            name: name,
            artists: artists,
            albumName: album?.isEmpty == false ? album : nil,
            albumPicUrl: cover?.isEmpty == false ? cover : nil,
            duration: duration
        )
    }

    // MARK: - 存储

    func storageGet(pluginID: String, key: String) -> String? {
        ensureStorageLoaded(pluginID)
        return storageCache[pluginID]?[key]
    }

    func storageSet(pluginID: String, key: String, value: String) {
        ensureStorageLoaded(pluginID)
        storageCache[pluginID, default: [:]][key] = value
        persistStorage(pluginID)
    }

    func storageRemove(pluginID: String, key: String) {
        ensureStorageLoaded(pluginID)
        storageCache[pluginID]?[key] = nil
        persistStorage(pluginID)
    }

    private func ensureStorageLoaded(_ pluginID: String) {
        guard storageCache[pluginID] == nil else { return }
        storageCache[pluginID] = loadStorage(pluginID)
    }

    private func loadStorage(_ pluginID: String) -> [String: String] {
        let url = dataDirectory.appendingPathComponent("\(pluginID).json")
        guard let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return values
    }

    private func persistStorage(_ pluginID: String) {
        let url = dataDirectory.appendingPathComponent("\(pluginID).json")
        guard let data = try? JSONEncoder().encode(storageCache[pluginID] ?? [:]) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - 日志与运行错误

    func handleLog(pluginID: String, level: String, message: String) {
        NSLog("[Plugin][%@][%@] %@", pluginID, level, message)
    }

    func setRuntimeError(pluginID: String, message: String?) {
        if let message, !message.isEmpty {
            runtimeErrors[pluginID] = message
        } else {
            runtimeErrors[pluginID] = nil
        }
    }

    // MARK: - 播放事件

    func notifyTrackChange(song: Song?, lyrics: [LyricLine]) {
        guard isStarted else { return }
        runtime.dispatchPlayerEvent("trackChange", payload: ["track": Self.trackPayload(song)])
        notifyLyricChange(song: song, lyrics: lyrics)
    }

    func notifyLyricChange(song: Song?, lyrics: [LyricLine]) {
        guard isStarted else { return }

        let lineObjects: [[String: Any]] = lyrics.enumerated().map { index, line in
            let endTime = index + 1 < lyrics.count ? lyrics[index + 1].time : line.time + 5
            return Self.linePayload(line, endTime: endTime)
        }

        runtime.dispatchPlayerEvent("lyricChange", payload: [
            "track": Self.trackPayload(song),
            "lines": lineObjects
        ])
    }

    func notifyLineChange(song: Song?, index: Int?, line: LyricLine?) {
        guard isStarted else { return }

        var payload: [String: Any] = ["track": Self.trackPayload(song)]
        if let index {
            payload["index"] = index
        } else {
            payload["index"] = NSNull()
        }

        if let line {
            let endTime = line.time + 5
            payload["line"] = Self.linePayload(line, endTime: endTime)
        }

        runtime.dispatchPlayerEvent("lineChange", payload: payload)
    }

    private static func trackPayload(_ song: Song?) -> [String: Any] {
        guard let song else { return [:] }
        return [
            "id": song.id,
            "title": song.name,
            "name": song.name,
            "artists": song.artistText,
            "artist": song.artistText,
            "album": song.albumName ?? "",
            "cover": song.albumPicUrl ?? "",
            "duration": song.duration,
            "durationMs": song.duration
        ]
    }

    private static func linePayload(_ line: LyricLine, endTime: TimeInterval) -> [String: Any] {
        let words: [[String: Any]] = line.words?.map { word in
            [
                "word": word.text,
                "startTime": word.time,
                "endTime": word.time + word.duration
            ]
        } ?? [[
            "word": line.text,
            "startTime": line.time,
            "endTime": endTime
        ]]

        var payload: [String: Any] = [
            "startTime": line.time,
            "endTime": endTime,
            "text": line.text,
            "words": words,
            "isBG": false,
            "isDuet": false
        ]
        if let translation = line.translation, !translation.isEmpty {
            payload["translatedLyric"] = translation
        }
        if let romanization = line.romanization, !romanization.isEmpty {
            payload["romanization"] = romanization
        }
        return payload
    }

    // MARK: - 插件市场

    func loadMarket() async {
        guard !isLoadingMarket else { return }
        isLoadingMarket = true
        marketError = nil
        defer { isLoadingMarket = false }

        guard let url = URL(string: Self.marketURLString) else {
            marketError = "插件市场地址无效"
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("SPlayer-iOS", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw PluginError.downloadFailed("插件市场返回异常")
            }

            let decoder = JSONDecoder()
            let items: [MarketPlugin]
            if let registry = try? decoder.decode(PluginRegistry.self, from: data) {
                items = registry.plugins ?? []
            } else {
                items = try decoder.decode([MarketPlugin].self, from: data)
            }

            marketPlugins = items.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            marketError = error.localizedDescription
        }
    }

    // MARK: - 下载

    private func downloadScript(from urlString: String) async throws -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw PluginError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("SPlayer-iOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PluginError.downloadFailed("网络响应异常")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PluginError.httpStatus(http.statusCode)
        }
        guard data.count <= Self.maxScriptSize else {
            throw PluginError.scriptTooLarge
        }
        guard let script = String(data: data, encoding: .utf8) else {
            throw PluginError.downloadFailed("插件文件不是 UTF-8 文本")
        }
        return script
    }

    // MARK: - 持久化

    private func loadRecords() {
        guard let data = try? Data(contentsOf: manifestURL),
              let records = try? JSONDecoder().decode([InstalledPlugin].self, from: data) else {
            plugins = []
            return
        }
        plugins = records
        sortPlugins()
    }

    private func sortPlugins() {
        plugins.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(plugins) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
