import ActivityKit
import Foundation

/// 与桌面小组件共享的当前播放信息
struct SharedNowPlaying: Codable, Hashable {
    var songId: Int = 0
    var title: String = ""
    var artist: String = ""
    var album: String?
    var coverURL: String?
    var lyricLine: String = ""
    var lyricTranslation: String?
    var nextLine: String?
    var isPlaying: Bool = false
    var progress: Double = 0
    var duration: Double = 0
    var updatedAt: Date = .distantPast
}

enum SharedStore {
    static let appGroupID = "group.com.splayer.ios"
    static let nowPlayingKey = "splayer.nowPlaying"
    static let widgetKind = "SPlayerLyricWidget"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(_ item: SharedNowPlaying?) {
        guard let defaults else { return }
        if let item, let data = try? JSONEncoder().encode(item) {
            defaults.set(data, forKey: nowPlayingKey)
        } else {
            defaults.removeObject(forKey: nowPlayingKey)
        }
    }

    static func load() -> SharedNowPlaying? {
        guard let defaults, let data = defaults.data(forKey: nowPlayingKey) else { return nil }
        return try? JSONDecoder().decode(SharedNowPlaying.self, from: data)
    }
}

/// 灵动岛 / 锁屏歌词的 Activity 属性
struct LyricActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var line: String
        public var translation: String?
        public var isPlaying: Bool
        public var progress: Double

        public init(line: String, translation: String?, isPlaying: Bool, progress: Double) {
            self.line = line
            self.translation = translation
            self.isPlaying = isPlaying
            self.progress = progress
        }
    }

    public var songTitle: String
    public var artist: String

    public init(songTitle: String, artist: String) {
        self.songTitle = songTitle
        self.artist = artist
    }
}
