import Combine
import CryptoKit
import Foundation

// MARK: - 服务器模型

enum MediaServerKind: String, Codable, CaseIterable, Identifiable {
    case subsonic
    case jellyfin
    case emby

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subsonic: return "Subsonic / Navidrome"
        case .jellyfin: return "Jellyfin"
        case .emby: return "Emby"
        }
    }

    var shortTitle: String {
        switch self {
        case .subsonic: return "Subsonic"
        case .jellyfin: return "Jellyfin"
        case .emby: return "Emby"
        }
    }

    var icon: String {
        switch self {
        case .subsonic: return "waveform.circle.fill"
        case .jellyfin: return "play.tv.fill"
        case .emby: return "play.rectangle.fill"
        }
    }
}

/// 一台媒体服务器（密钥保存在 Keychain）
struct MediaServer: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: MediaServerKind
    var name: String
    var baseURL: String
    var username: String
    /// Jellyfin / Emby 登录后的 AccessToken
    var token: String?
    /// Jellyfin / Emby 用户 id
    var userID: String?

    var secretKey: String { "mediaServer.\(id.uuidString)" }
    var secret: String { Keychain.read(secretKey) ?? "" }

    var normalizedBaseURL: URL? {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            text = "http://" + text
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        return URL(string: text)
    }
}

/// 媒体服务器配置存储
final class MediaServerStore: ObservableObject {
    static let shared = MediaServerStore()

    @Published private(set) var servers: [MediaServer] = []

    private let defaultsKey = "mediaServers"

    private init() {
        load()
    }

    func save(_ server: MediaServer, secret: String) {
        var updated = server
        updated.baseURL = server.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = server.name.trimmingCharacters(in: .whitespacesAndNewlines)

        if updated.name.isEmpty {
            updated.name = URL(string: updated.baseURL)?.host ?? updated.kind.shortTitle
        }

        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            let old = servers[index]
            let oldSecret = Keychain.read(old.secretKey) ?? ""
            if old.baseURL != updated.baseURL
                || old.username != updated.username
                || oldSecret != secret {
                updated.token = nil
                updated.userID = nil
            }
            Keychain.save(secret, for: updated.secretKey)
            servers[index] = updated
        } else {
            Keychain.save(secret, for: updated.secretKey)
            servers.append(updated)
        }
        persist()
    }

    func update(_ server: MediaServer) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[index] = server
        persist()
    }

    func remove(_ server: MediaServer) {
        Keychain.delete(server.secretKey)
        MediaServerRegistry.remove(serverID: server.id)
        servers.removeAll { $0.id == server.id }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([MediaServer].self, from: data)
        else { return }
        servers = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

// MARK: - 列表模型

struct MediaServerAlbum: Identifiable, Hashable {
    let serverID: UUID
    let id: String
    let name: String
    let artist: String?
    let coverURL: URL?
    let songCount: Int?
    let year: Int?
}

struct MediaServerTrack {
    let id: String
    let title: String
    let artist: String?
    let album: String?
    let duration: Int
    let coverURL: URL?
    let trackNumber: Int?

    /// 转换为播放器可用的 Song（负数 id 通过注册表映射）
    func song(server: MediaServer, album albumInfo: MediaServerAlbum) -> Song {
        let songID = MediaServerRegistry.songID(serverID: server.id, remoteID: id)
        let albumTitle = (album?.isEmpty == false) ? album! : albumInfo.name
        return Song(
            id: songID,
            name: title,
            artists: artist.map { [Song.Artist(id: nil, name: $0)] } ?? [],
            albumName: albumTitle,
            albumPicUrl: (coverURL ?? albumInfo.coverURL)?.absoluteString,
            duration: duration * 1000
        )
    }
}

// MARK: - 歌曲 id 注册表

/// 把服务器歌曲的字符串 id 映射为稳定的负数 Int id，便于复用现有播放器
enum MediaServerRegistry {
    private struct Ref: Codable {
        let serverID: UUID
        let remoteID: String
    }

    private static let defaultsKey = "mediaServerSongMap"
    private static let startID = -9_000_000

    private static var refs: [String: Ref] = loadRefs()
    private static var reverse: [String: Int] = {
        var result: [String: Int] = [:]
        for (key, ref) in refs {
            guard let id = Int(key) else { continue }
            result[requestKey(serverID: ref.serverID, remoteID: ref.remoteID)] = id
        }
        return result
    }()

    static func songID(serverID: UUID, remoteID: String) -> Int {
        let key = requestKey(serverID: serverID, remoteID: remoteID)
        if let existing = reverse[key] { return existing }

        var candidate = startID
        while refs[String(candidate)] != nil {
            candidate -= 1
        }
        refs[String(candidate)] = Ref(serverID: serverID, remoteID: remoteID)
        reverse[key] = candidate
        persist()
        return candidate
    }

    static func resolve(_ songID: Int) -> (server: MediaServer, remoteID: String)? {
        guard songID < 0,
              let ref = refs[String(songID)],
              let server = MediaServerStore.shared.servers.first(where: { $0.id == ref.serverID })
        else { return nil }
        return (server, ref.remoteID)
    }

    static func streamURL(for songID: Int) -> URL? {
        guard let (server, remoteID) = resolve(songID) else { return nil }
        return MediaServerClient.streamURL(server: server, trackID: remoteID)
    }

    static func remove(serverID: UUID) {
        refs = refs.filter { $0.value.serverID != serverID }
        reverse = [:]
        for (key, ref) in refs {
            guard let id = Int(key) else { continue }
            reverse[requestKey(serverID: ref.serverID, remoteID: ref.remoteID)] = id
        }
        persist()
    }

    private static func requestKey(serverID: UUID, remoteID: String) -> String {
        "\(serverID.uuidString)|\(remoteID)"
    }

    private static func loadRefs() -> [String: Ref] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: Ref].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func persist() {
        guard let data = try? JSONEncoder().encode(refs) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

// MARK: - 错误

enum MediaServerError: LocalizedError {
    case invalidURL
    case missingCredentials
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "服务器地址无效"
        case .missingCredentials: return "请填写用户名与密码"
        case .requestFailed(let message): return message
        }
    }
}

// MARK: - 客户端

enum MediaServerClient {
    // MARK: 对外接口

    static func test(server: MediaServer, secret: String) async throws {
        switch server.kind {
        case .subsonic:
            guard !server.username.isEmpty, !secret.isEmpty else {
                throw MediaServerError.missingCredentials
            }
            let url = try subsonicURL(server, method: "ping", secret: secret)
            let envelope = try await getJSON(url, as: SubsonicEnvelope.self)
            try check(envelope)
        case .jellyfin, .emby:
            guard !server.username.isEmpty, !secret.isEmpty else {
                throw MediaServerError.missingCredentials
            }
            _ = try await login(server, secret: secret, persist: false)
        }
    }

    static func albums(server: MediaServer, limit: Int = 100, offset: Int = 0) async throws -> [MediaServerAlbum] {
        switch server.kind {
        case .subsonic:
            let url = try subsonicURL(server, method: "getAlbumList2", extra: [
                URLQueryItem(name: "type", value: "alphabeticalByName"),
                URLQueryItem(name: "size", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ])
            let envelope = try await getJSON(url, as: SubsonicEnvelope.self)
            try check(envelope)
            let albums = envelope.subsonicResponse.albumList2?.album ?? []
            return albums.map { album in
                MediaServerAlbum(
                    serverID: server.id,
                    id: album.id,
                    name: album.name ?? "未知专辑",
                    artist: album.artist,
                    coverURL: album.coverArt.flatMap { coverURL(server, coverID: $0) },
                    songCount: album.songCount,
                    year: album.year
                )
            }

        case .jellyfin, .emby:
            let authenticated = try await authenticated(server)
            guard let userID = authenticated.userID, !userID.isEmpty else {
                throw MediaServerError.requestFailed("登录信息已失效，请重新保存服务器配置")
            }
            let url = try jellyfinURL(authenticated, path: "Users/\(userID)/Items", query: [
                URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "StartIndex", value: String(offset)),
                URLQueryItem(name: "Fields", value: "ChildCount,ProductionYear"),
                URLQueryItem(name: "api_key", value: authenticated.token ?? "")
            ])
            let response = try await getJSON(url, as: JellyfinItemsResponse.self)
            return response.Items.map { item in
                MediaServerAlbum(
                    serverID: authenticated.id,
                    id: item.Id,
                    name: item.Name ?? "未知专辑",
                    artist: item.AlbumArtist ?? item.Artists?.first,
                    coverURL: jellyfinImageURL(authenticated, itemID: item.Id),
                    songCount: item.ChildCount,
                    year: item.ProductionYear
                )
            }
        }
    }

    static func tracks(server: MediaServer, album: MediaServerAlbum) async throws -> [MediaServerTrack] {
        switch server.kind {
        case .subsonic:
            let url = try subsonicURL(server, method: "getAlbum", extra: [
                URLQueryItem(name: "id", value: album.id)
            ])
            let envelope = try await getJSON(url, as: SubsonicEnvelope.self)
            try check(envelope)
            let detail = envelope.subsonicResponse.album
            return (detail?.song ?? []).map { song in
                MediaServerTrack(
                    id: song.id,
                    title: song.title ?? "未知歌曲",
                    artist: song.artist,
                    album: song.album ?? detail?.name ?? album.name,
                    duration: song.duration ?? 0,
                    coverURL: song.coverArt.flatMap { coverURL(server, coverID: $0) } ?? album.coverURL,
                    trackNumber: song.track
                )
            }

        case .jellyfin, .emby:
            let authenticated = try await authenticated(server)
            guard let userID = authenticated.userID, !userID.isEmpty else {
                throw MediaServerError.requestFailed("登录信息已失效，请重新保存服务器配置")
            }
            let url = try jellyfinURL(authenticated, path: "Users/\(userID)/Items", query: [
                URLQueryItem(name: "ParentId", value: album.id),
                URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "SortBy", value: "ParentIndexNumber,IndexNumber"),
                URLQueryItem(name: "Limit", value: "500"),
                URLQueryItem(name: "Fields", value: "RunTimeTicks,AlbumId"),
                URLQueryItem(name: "api_key", value: authenticated.token ?? "")
            ])
            let response = try await getJSON(url, as: JellyfinItemsResponse.self)
            return response.Items.map { item in
                MediaServerTrack(
                    id: item.Id,
                    title: item.Name ?? "未知歌曲",
                    artist: item.Artists?.isEmpty == false
                        ? item.Artists?.joined(separator: " / ")
                        : item.AlbumArtist,
                    album: item.Album ?? album.name,
                    duration: Int((Double(item.RunTimeTicks ?? 0) / 10_000_000).rounded()),
                    coverURL: jellyfinImageURL(authenticated, itemID: item.AlbumId ?? album.id),
                    trackNumber: item.IndexNumber
                )
            }
        }
    }

    /// 播放地址（Subsonic 每次生成新的盐；Jellyfin 使用已保存 token）
    static func streamURL(server: MediaServer, trackID: String) -> URL? {
        switch server.kind {
        case .subsonic:
            return try? subsonicURL(server, method: "stream", extra: [
                URLQueryItem(name: "id", value: trackID)
            ])

        case .jellyfin, .emby:
            guard let token = server.token, !token.isEmpty else { return nil }
            return try? jellyfinURL(server, path: "Audio/\(trackID)/stream", query: [
                URLQueryItem(name: "static", value: "true"),
                URLQueryItem(name: "api_key", value: token)
            ])
        }
    }

    // MARK: Subsonic

    private static func subsonicURL(
        _ server: MediaServer,
        method: String,
        secret: String? = nil,
        extra: [URLQueryItem] = []
    ) throws -> URL {
        guard let base = server.normalizedBaseURL else {
            throw MediaServerError.invalidURL
        }
        let password = secret ?? server.secret
        guard !server.username.isEmpty, !password.isEmpty else {
            throw MediaServerError.missingCredentials
        }

        let salt = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let token = md5Hex(password + salt)

        var components = URLComponents(
            url: base.appendingPathComponent("rest/\(method)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "u", value: server.username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: "1.16.1"),
            URLQueryItem(name: "c", value: "SPlayer"),
            URLQueryItem(name: "f", value: "json")
        ] + extra

        guard let url = components?.url else {
            throw MediaServerError.invalidURL
        }
        return url
    }

    private static func coverURL(_ server: MediaServer, coverID: String) -> URL? {
        try? subsonicURL(server, method: "getCoverArt", extra: [
            URLQueryItem(name: "id", value: coverID),
            URLQueryItem(name: "size", value: "300")
        ])
    }

    // MARK: Jellyfin / Emby

    private static func authenticated(_ server: MediaServer) async throws -> MediaServer {
        switch server.kind {
        case .subsonic:
            return server
        case .jellyfin, .emby:
            if let token = server.token, !token.isEmpty,
               let userID = server.userID, !userID.isEmpty {
                return server
            }
            return try await login(server, secret: server.secret, persist: true)
        }
    }

    @discardableResult
    private static func login(
        _ server: MediaServer,
        secret: String,
        persist: Bool
    ) async throws -> MediaServer {
        guard let base = server.normalizedBaseURL else {
            throw MediaServerError.invalidURL
        }
        guard !server.username.isEmpty, !secret.isEmpty else {
            throw MediaServerError.missingCredentials
        }

        var request = URLRequest(url: base.appendingPathComponent("Users/AuthenticateByName"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let header = "MediaBrowser Client=\"SPlayer\", Device=\"iOS\", DeviceId=\"\(deviceID)\", Version=\"1.0.0\""
        request.setValue(header, forHTTPHeaderField: "Authorization")
        request.setValue(header, forHTTPHeaderField: "X-Emby-Authorization")
        request.httpBody = try JSONEncoder().encode([
            "Username": server.username,
            "Pw": secret
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)

        let auth: JellyfinAuthResponse
        do {
            auth = try JSONDecoder().decode(JellyfinAuthResponse.self, from: data)
        } catch {
            throw MediaServerError.requestFailed("登录响应解析失败")
        }

        var updated = server
        updated.token = auth.AccessToken
        updated.userID = auth.User.Id

        if persist {
            MediaServerStore.shared.update(updated)
        }
        return updated
    }

    private static func jellyfinURL(
        _ server: MediaServer,
        path: String,
        query: [URLQueryItem] = []
    ) throws -> URL {
        guard let base = server.normalizedBaseURL else {
            throw MediaServerError.invalidURL
        }
        var components = URLComponents(
            url: base.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query
        }
        guard let url = components?.url else {
            throw MediaServerError.invalidURL
        }
        return url
    }

    private static func jellyfinImageURL(_ server: MediaServer, itemID: String) -> URL? {
        guard let token = server.token, !token.isEmpty else { return nil }
        return try? jellyfinURL(server, path: "Items/\(itemID)/Images/Primary", query: [
            URLQueryItem(name: "maxHeight", value: "300"),
            URLQueryItem(name: "api_key", value: token)
        ])
    }

    private static var deviceID: String {
        let key = "mediaServerDeviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    // MARK: 通用

    private static func getJSON<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response, data: data)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MediaServerError.requestFailed("服务器返回数据无法解析")
        }
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let snippet = body.prefix(120)
            throw MediaServerError.requestFailed("请求失败（HTTP \(http.statusCode)）\(snippet)")
        }
    }

    private static func check(_ envelope: SubsonicEnvelope) throws {
        guard envelope.subsonicResponse.status != "failed" else {
            let message = envelope.subsonicResponse.error?.message ?? "Subsonic 请求失败"
            throw MediaServerError.requestFailed(message)
        }
    }

    private static func md5Hex(_ string: String) -> String {
        Insecure.MD5.hash(data: Data(string.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: - DTO

private struct SubsonicEnvelope: Decodable {
    let subsonicResponse: Body

    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }

    struct Body: Decodable {
        struct APIError: Decodable {
            let code: Int?
            let message: String?
        }

        struct AlbumList: Decodable {
            let album: [Album]?
        }

        struct Album: Decodable {
            let id: String
            let name: String?
            let artist: String?
            let coverArt: String?
            let songCount: Int?
            let year: Int?
        }

        struct AlbumDetail: Decodable {
            let id: String
            let name: String?
            let artist: String?
            let coverArt: String?
            let song: [Song]?
        }

        struct Song: Decodable {
            let id: String
            let title: String?
            let artist: String?
            let album: String?
            let duration: Int?
            let coverArt: String?
            let track: Int?
        }

        let status: String?
        let error: APIError?
        let albumList2: AlbumList?
        let album: AlbumDetail?
    }
}

private struct JellyfinAuthResponse: Decodable {
    let AccessToken: String
    let User: User

    struct User: Decodable {
        let Id: String
    }
}

private struct JellyfinItemsResponse: Decodable {
    let Items: [Item]

    struct Item: Decodable {
        let Id: String
        let Name: String?
        let Album: String?
        let AlbumArtist: String?
        let Artists: [String]?
        let RunTimeTicks: Int64?
        let IndexNumber: Int?
        let ChildCount: Int?
        let ProductionYear: Int?
        let AlbumId: String?
    }
}
