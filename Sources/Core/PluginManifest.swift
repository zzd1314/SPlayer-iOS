import CoreFoundation
import Foundation

// MARK: - 插件元数据

/// 解析插件文件头部注释中的 `@key value` 元数据（与桌面版一致）
struct PluginManifest {
    /// 当前宿主支持的插件 API 级别
    static let supportedAPILevel = 5

    let id: String
    let name: String
    let version: String
    let author: String?
    let summary: String?
    let homepage: String?
    let updateURL: String?
    let changelog: String?
    let apiLevel: Int
    let grants: [String]

    init(script: String) throws {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PluginError.emptyScript
        }

        let metadata = Self.parseMetadata(script)

        var identifier = Self.normalizedID(metadata["id"] ?? "")
        if identifier.isEmpty {
            identifier = Self.normalizedID(metadata["name"] ?? "")
        }
        if identifier.isEmpty {
            identifier = "plugin-" + Self.stableHash(script)
        }
        id = identifier

        let rawName = metadata["name"]?.trimmingCharacters(in: .whitespaces) ?? ""
        name = rawName.isEmpty ? identifier : rawName

        let rawVersion = metadata["version"]?.trimmingCharacters(in: .whitespaces) ?? ""
        version = rawVersion.isEmpty
            ? "0.0.0"
            : (rawVersion.hasPrefix("v") || rawVersion.hasPrefix("V") ? String(rawVersion.dropFirst()) : rawVersion)

        author = Self.optional(metadata["author"])
        summary = Self.optional(metadata["description"])
        homepage = Self.optional(metadata["homepage"])
        updateURL = Self.optional(metadata["updateUrl"])
        changelog = Self.optional(metadata["changelog"])

        let level = Int(metadata["apiLevel"]?.trimmingCharacters(in: .whitespaces) ?? "") ?? 1
        apiLevel = max(1, level)
        guard apiLevel <= Self.supportedAPILevel else {
            throw PluginError.unsupportedAPILevel(apiLevel)
        }

        let rawGrants = metadata["grant"] ?? ""
        let grants = rawGrants
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "|" })
            .map(String.init)
            .filter { !$0.isEmpty }
        self.grants = grants.isEmpty ? ["network"] : grants
    }

    // MARK: 解析

    private static func parseMetadata(_ script: String) -> [String: String] {
        var metadata: [String: String] = [:]
        let lines = script.components(separatedBy: .newlines).prefix(160)

        for rawLine in lines {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // 逐层剥离注释前缀：/**、*/、//、*
            var didStrip = true
            while didStrip {
                didStrip = false
                for prefix in ["/*", "*/", "//", "*"] where line.hasPrefix(prefix) {
                    line.removeFirst(prefix.count)
                    line = line.trimmingCharacters(in: .whitespaces)
                    didStrip = true
                    break
                }
            }

            guard line.hasPrefix("@") else { continue }
            let body = line.dropFirst()
            let parts = body.split(
                maxSplits: 1,
                omittingEmptySubsequences: true,
                whereSeparator: { $0 == " " || $0 == "\t" }
            )
            guard let keyPart = parts.first else { continue }

            let key = String(keyPart)
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                .lowercased()
            guard !key.isEmpty else { continue }

            var value = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: CharacterSet.whitespaces) : ""
            if value.hasSuffix("*/") {
                value.removeLast(2)
                value = value.trimmingCharacters(in: CharacterSet.whitespaces)
            }
            if metadata[key] == nil {
                metadata[key] = value
            }
        }
        return metadata
    }

    /// 规范化插件 ID：小写，仅保留 a-z0-9._-
    static func normalizedID(_ raw: String) -> String {
        var output = ""
        for scalar in raw.lowercased().unicodeScalars {
            if scalar.isASCII,
               CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "_" || scalar == "-" {
                output.unicodeScalars.append(scalar)
            } else if scalar == " " || scalar == "/" || scalar == "\\" {
                output.append("-")
            }
        }
        while output.contains("--") {
            output = output.replacingOccurrences(of: "--", with: "-")
        }
        return output.trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
    }

    private static func stableHash(_ text: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(hash, radix: 16)
    }

    private static func optional(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }
}

// MARK: - 已安装插件

/// 本地已安装的插件记录（持久化到 manifest.json）
struct InstalledPlugin: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var version: String
    var author: String?
    var summary: String?
    var homepage: String?
    var updateURL: String?
    var changelog: String?
    var apiLevel: Int
    var grants: [String]
    var scriptFile: String
    var enabled: Bool
    var installedAt: Date
    /// 用户修改过的设置项（未修改时回退到插件声明的默认值）
    var settingValues: [String: PluginValue]
    /// 上次运行注册的设置结构，插件禁用时也能展示配置项
    var settingsSchema: [PluginSetting]?

    init(manifest: PluginManifest) {
        id = manifest.id
        name = manifest.name
        version = manifest.version
        author = manifest.author
        summary = manifest.summary
        homepage = manifest.homepage
        updateURL = manifest.updateURL
        changelog = manifest.changelog
        apiLevel = manifest.apiLevel
        grants = manifest.grants
        scriptFile = "\(manifest.id).js"
        enabled = true
        installedAt = Date()
        settingValues = [:]
        settingsSchema = nil
    }
}

// MARK: - 设置值

/// 插件设置值（文本 / 数字 / 开关）
enum PluginValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "不支持的设置值类型")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }

    init?(any value: Any?) {
        guard let value else { return nil }
        if let string = value as? String {
            self = .string(string)
            return
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
            return
        }
        return nil
    }

    var stringValue: String {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value == value.rounded() ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        }
    }

    var doubleValue: Double {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value) ?? 0
        case .bool(let value): return value ? 1 : 0
        }
    }

    var boolValue: Bool {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        case .string(let value):
            return ["true", "1", "yes", "on"].contains(value.lowercased())
        }
    }

    var displayText: String {
        switch self {
        case .bool(let value): return value ? "开" : "关"
        default: return stringValue
        }
    }

    /// 供 JS 读取的 JSON 文本
    var jsonText: String {
        guard let data = try? JSONEncoder().encode(self),
              let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }
}

// MARK: - 插件市场

struct MarketPlugin: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let author: String?
    let version: String?
    let description: String?
    let homepage: String?
    let updateUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, author, version, description, homepage
        case updateUrl, updateURL, downloadUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        author = try container.decodeIfPresent(String.self, forKey: .author)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        homepage = try container.decodeIfPresent(String.self, forKey: .homepage)
        let primary = try container.decodeIfPresent(String.self, forKey: .updateUrl)
        let alternate = try container.decodeIfPresent(String.self, forKey: .updateURL)
        let fallback = try container.decodeIfPresent(String.self, forKey: .downloadUrl)
        updateUrl = primary ?? alternate ?? fallback
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(homepage, forKey: .homepage)
        try container.encodeIfPresent(updateUrl, forKey: .updateUrl)
    }
}

struct PluginRegistry: Decodable {
    let plugins: [MarketPlugin]?
}

// MARK: - 错误与结果

enum PluginError: LocalizedError {
    case emptyScript
    case unsupportedAPILevel(Int)
    case scriptTooLarge
    case invalidURL
    case downloadFailed(String)
    case httpStatus(Int)
    case noDownloadURL
    case noUpdateURL
    case pluginNotFound
    case runtimeUnavailable
    case runtimeTimeout(String)
    case runtimeCallFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyScript:
            return "插件文件内容为空"
        case .unsupportedAPILevel(let level):
            return "插件需要 API 级别 \(level)，当前仅支持到 \(PluginManifest.supportedAPILevel)"
        case .scriptTooLarge:
            return "插件文件超过 2 MB，无法导入"
        case .invalidURL:
            return "请输入有效的 http(s) 地址"
        case .downloadFailed(let message):
            return "插件下载失败：\(message)"
        case .httpStatus(let code):
            return "插件下载失败（HTTP \(code)）"
        case .noDownloadURL:
            return "该插件未提供下载地址"
        case .noUpdateURL:
            return "该插件未声明 @updateUrl，无法检查更新"
        case .pluginNotFound:
            return "插件不存在或已被卸载"
        case .runtimeUnavailable:
            return "插件运行时尚未就绪"
        case .runtimeTimeout(let action):
            return "插件处理 \(action) 超时"
        case .runtimeCallFailed(let message):
            return "插件调用失败：\(message)"
        }
    }
}

struct PluginInstallResult {
    let plugin: InstalledPlugin
    let isUpdate: Bool
    let previousVersion: String?
}

enum PluginUpdateResult {
    case upToDate(String)
    case updated(from: String, to: String)
}
