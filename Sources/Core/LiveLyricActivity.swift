import ActivityKit
import Foundation

/// 灵动岛 / 锁屏歌词控制器（Live Activity）
@MainActor
final class LiveLyricActivity {
    static let shared = LiveLyricActivity()

    private var activity: Activity<LyricActivityAttributes>?
    private var currentSongId: Int?
    private var lastKey = ""

    private init() {}

    func sync(payload: SharedNowPlaying, enabled: Bool) {
        guard enabled, payload.songId != 0, !payload.title.isEmpty else {
            stop()
            return
        }

        let progress = payload.duration > 0
            ? min(max(payload.progress / payload.duration, 0), 1)
            : 0
        let state = LyricActivityAttributes.ContentState(
            line: payload.lyricLine,
            translation: payload.lyricTranslation,
            isPlaying: payload.isPlaying,
            progress: progress
        )

        let key = "\(payload.songId)|\(state.line)|\(state.isPlaying)|\(Int(progress * 100))"
        guard key != lastKey else { return }
        lastKey = key

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if currentSongId != payload.songId {
            currentSongId = payload.songId
            let old = activity
            activity = nil
            Task {
                await old?.end(nil, dismissalPolicy: .immediate)
                self.start(payload: payload, state: state)
            }
        } else if let activity {
            let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(120))
            Task { await activity.update(content) }
        } else {
            start(payload: payload, state: state)
        }
    }

    func stop() {
        currentSongId = nil
        lastKey = ""
        guard let old = activity else { return }
        activity = nil
        Task { await old.end(nil, dismissalPolicy: .immediate) }
    }

    private func start(payload: SharedNowPlaying, state: LyricActivityAttributes.ContentState) {
        let attributes = LyricActivityAttributes(songTitle: payload.title, artist: payload.artist)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(120))
        activity = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }
}
