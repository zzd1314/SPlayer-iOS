import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit
import WidgetKit

/// 播放核心：AVPlayer 队列 + 后台音频 + 锁屏信息/控制 + 本地缓存 + 小组件歌词
@MainActor
final class PlayerStore: ObservableObject {
    @Published private(set) var queue: [Song] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    /// 当前播放进度（秒），供歌词滚动使用
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    /// 当前歌曲歌词（含翻译）
    @Published private(set) var lyricLines: [LyricLine] = []
    @Published private(set) var isLoadingLyrics = false
    @Published private(set) var lyricError: String?
    /// 封面主色（用于歌词高亮 / 主题跟随封面）
    @Published private(set) var coverAccent: Color?
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var isShuffleEnabled = false

    /// 登录 Cookie（由 RootView 同步）
    var cookie: String?

    private let player = AVPlayer()
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var lyricTask: Task<Void, Never>?
    private var lastWidgetReload = Date.distantPast
    private var isRestored = false
    /// 正在预载/缓存中的歌曲，避免重复下载
    private var preloadingSongs: Set<Int> = []

    init() {
        if let raw = UserDefaults.standard.string(forKey: "repeatMode"),
           let mode = RepeatMode(rawValue: raw) {
            repeatMode = mode
        }
        isShuffleEnabled = UserDefaults.standard.bool(forKey: "shuffleEnabled")

        configureAudioSession()
        registerRemoteCommands()
        observeInterruptions()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                guard seconds.isFinite else { return }

                let previousLine = self.currentLyricIndex
                self.currentTime = max(0, seconds)

                if let itemDuration = self.player.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }

                if self.currentLyricIndex != previousLine {
                    self.syncNowPlaying()
                }
            }
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        lyricTask?.cancel()
    }

    // MARK: - 派生状态

    var currentLyricIndex: Int? {
        guard !lyricLines.isEmpty else { return nil }
        var index: Int?
        for (i, line) in lyricLines.enumerated() where line.time <= currentTime + 0.2 {
            index = i
        }
        return index
    }

    var currentLyricLine: LyricLine? {
        guard let index = currentLyricIndex, lyricLines.indices.contains(index) else { return nil }
        return lyricLines[index]
    }

    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    // MARK: - 外部操作

    func play(song: Song, in songs: [Song]) async {
        guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
        await play(songs, startAt: index)
    }

    func play(_ songs: [Song], startAt index: Int) async {
        guard songs.indices.contains(index) else { return }
        queue = songs
        currentIndex = index
        await loadCurrent(autoPlay: true)
    }

    func play(at index: Int) async {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        await loadCurrent(autoPlay: true)
    }

    func togglePlayPause() {
        guard currentSong != nil else { return }
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func next(userInitiated: Bool = true) async {
        guard !queue.isEmpty else { return }

        if repeatMode == .one, !userInitiated {
            seek(to: 0)
            resume()
            return
        }

        if isShuffleEnabled, queue.count > 1 {
            var index = currentIndex
            while index == currentIndex {
                index = Int.random(in: 0..<queue.count)
            }
            currentIndex = index
            await loadCurrent()
            return
        }

        if currentIndex + 1 < queue.count {
            currentIndex += 1
            await loadCurrent()
        } else if repeatMode == .all {
            currentIndex = 0
            await loadCurrent()
        } else {
            pause()
            seek(to: 0)
        }
    }

    func previous() async {
        guard !queue.isEmpty else { return }
        let elapsed = CMTimeGetSeconds(player.currentTime())
        if elapsed > 3 || currentIndex == 0 {
            seek(to: 0)
            return
        }
        currentIndex -= 1
        await loadCurrent()
    }

    /// 拖动进度条 / 锁屏进度
    func seek(to time: TimeInterval) {
        guard currentSong != nil else { return }
        let maxDuration = duration > 0 ? duration : time
        let clamped = min(max(time, 0), maxDuration)
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in
                self?.updateNowPlaying()
                self?.syncNowPlaying()
                self?.persistPlaybackState()
            }
        }
    }

    func cycleRepeatMode() {
        let modes = RepeatMode.allCases
        guard let index = modes.firstIndex(of: repeatMode) else { return }
        repeatMode = modes[(index + 1) % modes.count]
        UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode")
    }

    func toggleShuffle() {
        isShuffleEnabled.toggle()
        UserDefaults.standard.set(isShuffleEnabled, forKey: "shuffleEnabled")
    }

    /// 重试当前歌曲
    func retry() async {
        guard currentSong != nil else { return }
        await loadCurrent(autoPlay: true)
    }

    // MARK: - 播放

    private func resume() {
        guard player.currentItem != nil else { return }
        player.play()
        isPlaying = true
        updateNowPlaying()
        syncNowPlaying()
    }

    private func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
        syncNowPlaying()
        persistPlaybackState()
    }

    private func loadCurrent(autoPlay: Bool? = nil) async {
        guard queue.indices.contains(currentIndex) else { return }
        let song = queue[currentIndex]
        let shouldPlay = autoPlay ?? AppSettings.autoPlay

        currentSong = song
        isLoading = true
        errorText = nil
        currentTime = 0
        duration = Double(song.duration) / 1000
        lyricLines = []
        lyricError = nil
        coverAccent = nil
        removeEndObserver()
        loadLyrics(for: song)
        persistPlaybackState()
        syncNowPlaying()

        do {
            let remoteURL = try await NeteaseAPI().songURL(
                id: song.id,
                level: AppSettings.audioLevel,
                cookie: cookie
            )

            let item: AVPlayerItem
            if let localURL = AudioCache.cachedURL(songId: song.id) {
                item = AVPlayerItem(url: localURL)
            } else {
                item = AVPlayerItem(url: remoteURL)
                if AppSettings.enableSongCache {
                    cacheInBackground(url: remoteURL, songId: song.id)
                }
            }

            player.replaceCurrentItem(with: item)
            observeItem(item)
            if shouldPlay {
                player.play()
                isPlaying = true
            } else {
                player.pause()
                isPlaying = false
            }
            isLoading = false
            updateNowPlaying()
            syncNowPlaying()
            if AppSettings.preloadNextTrack, AppSettings.enableSongCache {
                preloadNext()
            }
        } catch {
            isLoading = false
            isPlaying = false
            errorText = error.localizedDescription
            syncNowPlaying()
        }
    }

    private func loadLyrics(for song: Song) {
        lyricTask?.cancel()
        isLoadingLyrics = true
        let cookie = self.cookie

        lyricTask = Task { [weak self] in
            guard let self else { return }
            do {
                let bundle = try await NeteaseAPI().lyricBundle(id: song.id, cookie: cookie)
                guard !Task.isCancelled, self.currentSong?.id == song.id else { return }
                self.lyricLines = bundle.lines
                self.lyricError = bundle.lines.isEmpty ? "暂无歌词" : nil
            } catch {
                guard !Task.isCancelled, self.currentSong?.id == song.id else { return }
                self.lyricLines = []
                self.lyricError = error.localizedDescription
            }
            self.isLoadingLyrics = false
            self.syncNowPlaying()
        }
    }

    /// 预载下一曲：提前解析地址并写入本地缓存
    private func preloadNext() {
        let nextIndex = currentIndex + 1
        guard queue.indices.contains(nextIndex) else { return }
        let song = queue[nextIndex]
        guard AudioCache.cachedURL(songId: song.id) == nil,
              !preloadingSongs.contains(song.id)
        else { return }

        preloadingSongs.insert(song.id)
        let cookie = self.cookie
        Task { [weak self] in
            defer { self?.preloadingSongs.remove(song.id) }
            guard let url = try? await NeteaseAPI().songURL(
                id: song.id,
                level: AppSettings.audioLevel,
                cookie: cookie
            ) else { return }
            await self?.download(url: url, songId: song.id)
        }
    }

    private func cacheInBackground(url: URL, songId: Int) {
        Task { [weak self] in
            await self?.download(url: url, songId: songId)
        }
    }

    private func download(url: URL, songId: Int) async {
        guard let (tmpURL, response) = try? await URLSession.shared.download(from: url) else { return }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return
        }
        AudioCache.store(tmpURL: tmpURL, songId: songId)
        if AppSettings.cacheLimitBytes > 0 {
            AudioCache.enforceLimit(maxBytes: AppSettings.cacheLimitBytes)
        }
    }

    private func observeItem(_ item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleTrackEnd()
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.errorText = "播放中断，请检查网络后重试"
                self?.syncNowPlaying()
            }
        }
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            self.failureObserver = nil
        }
    }

    private func handleTrackEnd() async {
        if repeatMode == .one {
            seek(to: 0)
            resume()
            return
        }
        await next(userInitiated: false)
    }

    // MARK: - 记忆播放进度

    func persistPlaybackState() {
        guard AppSettings.rememberLastTrack, currentSong != nil, !queue.isEmpty else { return }
        let snapshot = PlaybackSnapshot(
            queue: queue,
            index: currentIndex,
            time: currentTime,
            savedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: "playbackSnapshot")
    }

    /// 启动时恢复上次的队列与进度（保持暂停）
    func restoreIfNeeded() async {
        guard !isRestored else { return }
        isRestored = true
        guard AppSettings.rememberLastTrack, currentSong == nil,
              let data = UserDefaults.standard.data(forKey: "playbackSnapshot"),
              let snapshot = try? JSONDecoder().decode(PlaybackSnapshot.self, from: data),
              !snapshot.queue.isEmpty
        else { return }

        queue = snapshot.queue
        currentIndex = min(max(0, snapshot.index), queue.count - 1)
        await loadCurrent(autoPlay: false)
        if snapshot.time > 1 {
            seek(to: snapshot.time)
        }
    }

    // MARK: - 音频会话 / 中断

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }

            Task { @MainActor in
                guard let self else { return }
                switch type {
                case .began:
                    self.player.pause()
                    self.isPlaying = false
                    self.syncNowPlaying()
                case .ended:
                    let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                        self.resume()
                    }
                @unknown default:
                    break
                }
            }
        }
    }

    // MARK: - 锁屏控制

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyArtist: song.artistText,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let album = song.albumName, !album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        guard let pic = song.albumPicUrl, let url = URL(string: pic) else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data)
            else { return }
            guard let self, self.currentSong?.id == song.id else { return }

            self.coverAccent = Self.accentColor(from: image)

            var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            current[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = current
        }
    }

    private static func accentColor(from image: UIImage) -> Color? {
        guard let cgImage = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        let base = UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        guard base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return nil
        }
        let adjusted = UIColor(
            hue: hue,
            saturation: max(saturation, 0.55),
            brightness: max(brightness, 0.72),
            alpha: 1
        )
        return Color(uiColor: adjusted)
    }

    // MARK: - 小组件 / 灵动岛同步

    func syncNowPlaying() {
        guard let song = currentSong else {
            SharedStore.save(nil)
            LiveLyricActivity.shared.stop()
            return
        }

        let line = currentLyricLine
        let nextLine: String? = {
            guard let index = currentLyricIndex, lyricLines.indices.contains(index + 1) else { return nil }
            return lyricLines[index + 1].text
        }()

        let payload = SharedNowPlaying(
            songId: song.id,
            title: song.name,
            artist: song.artistText,
            album: song.albumName,
            coverURL: song.albumPicUrl,
            lyricLine: line?.text ?? "",
            lyricTranslation: line?.translation,
            nextLine: nextLine,
            isPlaying: isPlaying,
            progress: currentTime,
            duration: duration,
            updatedAt: Date()
        )
        SharedStore.save(payload)

        if Date().timeIntervalSince(lastWidgetReload) > 10 {
            lastWidgetReload = Date()
            WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind)
        }
        LiveLyricActivity.shared.sync(payload: payload, enabled: AppSettings.liveActivityEnabled)
    }
}
