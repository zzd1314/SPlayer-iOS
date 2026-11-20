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
    /// 当前歌曲封面地址（官方缺失时可由音源插件补充）
    @Published private(set) var currentCoverURL: String?
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var isShuffleEnabled = false
    /// 最近播放（最新在前，最多 100 首）
    @Published private(set) var recentSongs: [Song] = []
    /// 我喜欢的音乐（歌曲 id）
    @Published private(set) var likedSongIds: Set<Int> = []
    /// 当前播放速度（0.5x ~ 2.0x）
    @Published private(set) var playbackRate: Float = 1.0
    /// 播放音量（0 ~ 1），仅影响本 App，不改变系统音量
    @Published private(set) var volume: Float = 1.0
    /// 睡眠定时结束时间（nil 表示未开启）
    @Published private(set) var sleepTimerEndDate: Date?
    /// 睡眠定时剩余秒数
    @Published private(set) var sleepTimerRemaining: TimeInterval = 0
    /// 播完当前歌曲后暂停
    @Published private(set) var sleepAfterCurrentTrack = false

    /// 登录 Cookie（由 RootView 同步）
    var cookie: String?
    /// 当前登录用户 id（由 RootView 同步）
    var userID: Int?

    private let player = AVPlayer()
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var lyricTask: Task<Void, Never>?
    private var sleepTimer: Timer?
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
        playbackRate = Float(AppSettings.playbackRate)
        player.defaultRate = playbackRate
        let savedVolume = UserDefaults.standard.object(forKey: "playerVolume") as? Double ?? 1
        volume = Float(savedVolume)
        player.volume = volume
        if let data = UserDefaults.standard.data(forKey: "recentSongs"),
           let saved = try? JSONDecoder().decode([Song].self, from: data) {
            recentSongs = saved
        }

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
        sleepTimer?.invalidate()
    }

    // MARK: - 派生状态

    var currentLyricIndex: Int? {
        guard !lyricLines.isEmpty else { return nil }
        let offset = AppSettings.lyricOffset
        var index: Int?
        for (i, line) in lyricLines.enumerated() where line.time <= currentTime + 0.2 + offset {
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

    // MARK: - 播放速度 / 睡眠定时

    /// 设置播放速度（立即生效并持久化）
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        AppSettings.playbackRate = Double(rate)
        player.defaultRate = rate
        if isPlaying {
            player.rate = rate
        }
        updateNowPlaying()
    }

    /// 音量：只调节 App 内播放音量，不影响系统音量
    func setVolume(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        volume = clamped
        player.volume = clamped
        UserDefaults.standard.set(Double(clamped), forKey: "playerVolume")
    }

    /// 睡眠定时：指定分钟后自动暂停
    func startSleepTimer(minutes: Int) {
        guard minutes > 0 else { return }
        sleepAfterCurrentTrack = false
        let end = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTimerEndDate = end
        sleepTimerRemaining = end.timeIntervalSinceNow
        scheduleSleepTimer()
    }

    /// 播完当前歌曲后暂停
    func startSleepAtTrackEnd() {
        cancelSleepTimer()
        sleepAfterCurrentTrack = true
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerEndDate = nil
        sleepTimerRemaining = 0
        sleepAfterCurrentTrack = false
    }

    /// 睡眠定时状态文案（未开启时为 nil）
    var sleepTimerLabel: String? {
        if sleepAfterCurrentTrack { return "曲末暂停" }
        guard sleepTimerEndDate != nil else { return nil }
        let total = max(0, Int(sleepTimerRemaining.rounded(.up)))
        return String(format: "定时 %d:%02d", total / 60, total % 60)
    }

    private func scheduleSleepTimer() {
        sleepTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickSleepTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
    }

    private func tickSleepTimer() {
        guard let end = sleepTimerEndDate else { return }
        let remaining = end.timeIntervalSinceNow
        guard remaining > 0 else {
            cancelSleepTimer()
            pause()
            return
        }
        sleepTimerRemaining = remaining
    }

    /// 重试当前歌曲
    func retry() async {
        guard currentSong != nil else { return }
        await loadCurrent(autoPlay: true)
    }

    // MARK: - 最近播放 / 收藏

    var isCurrentSongLiked: Bool {
        guard let id = currentSong?.id else { return false }
        return likedSongIds.contains(id)
    }

    func clearRecent() {
        recentSongs = []
        UserDefaults.standard.removeObject(forKey: "recentSongs")
    }

    /// 登录态变化时同步账号信息并刷新收藏
    func applyAccount(userID: Int?) async {
        self.userID = userID
        guard userID != nil else {
            likedSongIds = []
            return
        }
        await refreshLikes()
    }

    /// 拉取「我喜欢的音乐」id 集合
    func refreshLikes() async {
        guard let userID, let cookie, !cookie.isEmpty else { return }
        do {
            let ids = try await NeteaseAPI().likeList(uid: userID, cookie: cookie)
            likedSongIds = Set(ids)
        } catch {
            // 收藏列表加载失败不阻塞播放
        }
    }

    /// 指定歌曲是否已收藏
    func isLiked(_ songId: Int) -> Bool {
        likedSongIds.contains(songId)
    }

    /// 收藏 / 取消收藏指定歌曲（失败时恢复本地状态）
    func toggleLike(songId: Int) async throws {
        guard songId > 0 else {
            throw APIError.business(code: -1, message: "本地歌曲不支持收藏")
        }
        guard let cookie, !cookie.isEmpty else {
            throw APIError.business(code: -1, message: "请先登录")
        }

        let wasLiked = likedSongIds.contains(songId)
        applyLikeState(songId: songId, liked: !wasLiked)

        do {
            try await NeteaseAPI().setLike(songId: songId, like: !wasLiked, cookie: cookie)
        } catch {
            applyLikeState(songId: songId, liked: wasLiked)
            throw error
        }
    }

    /// 收藏 / 取消收藏当前歌曲
    func toggleLikeCurrent() async throws {
        guard let song = currentSong else { return }
        try await toggleLike(songId: song.id)
    }

    private func applyLikeState(songId: Int, liked: Bool) {
        if liked {
            likedSongIds.insert(songId)
        } else {
            likedSongIds.remove(songId)
        }
    }

    /// 调整播放队列顺序，并同步当前播放索引
    func moveQueue(fromOffsets: IndexSet, toOffset: Int) {
        guard !queue.isEmpty else { return }
        let currentSongID = currentSong?.id
        queue.move(fromOffsets: fromOffsets, toOffset: toOffset)
        if let currentSongID, let index = queue.firstIndex(where: { $0.id == currentSongID }) {
            currentIndex = index
        }
        persistPlaybackState()
    }

    /// 将歌曲插入到当前播放之后（已存在时先移除原位置）
    func playNext(_ song: Song) {
        if let index = queue.firstIndex(where: { $0.id == song.id }) {
            guard index != currentIndex else { return }
            queue.remove(at: index)
            if index < currentIndex {
                currentIndex -= 1
            }
        }

        let target = min(currentIndex + 1, queue.count)
        queue.insert(song, at: target)
        persistPlaybackState()
    }

    private func recordRecent(_ song: Song) {
        recentSongs.removeAll { $0.id == song.id }
        recentSongs.insert(song, at: 0)
        if recentSongs.count > 100 {
            recentSongs.removeLast(recentSongs.count - 100)
        }
        if let data = try? JSONEncoder().encode(recentSongs) {
            UserDefaults.standard.set(data, forKey: "recentSongs")
        }
    }

    // MARK: - 播放

    private func resume() {
        guard player.currentItem != nil else { return }
        player.defaultRate = playbackRate
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
        currentCoverURL = song.albumPicUrl
        removeEndObserver()
        loadLyrics(for: song)
        resolveCoverIfNeeded(for: song)
        persistPlaybackState()
        syncNowPlaying()

        do {
            let item: AVPlayerItem
            if let localURL = LocalMusicStore.url(for: song.id) {
                item = AVPlayerItem(url: localURL)
            } else if let downloadURL = DownloadStore.url(for: song.id) {
                item = AVPlayerItem(url: downloadURL)
            } else if let streamURL = MediaServerRegistry.streamURL(for: song.id) {
                item = AVPlayerItem(url: streamURL)
            } else {
                let remoteURL = try await resolveStreamURL(for: song)

                if let cachedURL = AudioCache.cachedURL(songId: song.id) {
                    item = AVPlayerItem(url: cachedURL)
                } else {
                    item = AVPlayerItem(url: remoteURL)
                    if AppSettings.enableSongCache {
                        cacheInBackground(url: remoteURL, songId: song.id)
                    }
                }
            }

            player.replaceCurrentItem(with: item)
            observeItem(item)
            if shouldPlay {
                player.defaultRate = playbackRate
                player.play()
                isPlaying = true
                recordRecent(song)
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

    /// 解析播放地址：官方接口失败（VIP / 无版权 / 上游故障）时回退到音源插件
    private func resolveStreamURL(for song: Song) async throws -> URL {
        do {
            return try await NeteaseAPI().songURL(
                id: song.id,
                level: AppSettings.audioLevel,
                cookie: cookie
            )
        } catch {
            guard let fallback = await PluginManager.shared.resolvePlaybackURL(for: song) else {
                throw error
            }
            return fallback
        }
    }

    /// 官方封面缺失时异步向音源插件补图
    private func resolveCoverIfNeeded(for song: Song) {
        guard song.id > 0, song.albumPicUrl?.isEmpty != false else { return }
        Task { [weak self] in
            guard let self,
                  let cover = await PluginManager.shared.resolveCoverURL(for: song),
                  self.currentSong?.id == song.id else { return }
            self.currentCoverURL = cover
            self.updateNowPlaying()
            self.syncNowPlaying()
        }
    }

    private func loadLyrics(for song: Song) {
        lyricTask?.cancel()
        guard song.id > 0 else {
            lyricLines = []
            isLoadingLyrics = false
            lyricError = "该歌曲暂无歌词"
            return
        }
        isLoadingLyrics = true
        let cookie = self.cookie

        lyricTask = Task { [weak self] in
            guard let self else { return }
            var lines: [LyricLine] = []
            var message: String?
            do {
                let bundle = try await NeteaseAPI().lyricBundle(id: song.id, cookie: cookie)
                lines = bundle.lines
            } catch {
                message = error.localizedDescription
            }

            // 官方歌词缺失时，尝试由音源插件提供（LRC / 逐字）
            if lines.isEmpty,
               let pluginLyric = await PluginManager.shared.resolveLyric(for: song),
               !Task.isCancelled {
                lines = LRC.parse(
                    pluginLyric.text,
                    translation: nil,
                    yrc: pluginLyric.wordText
                ).lines
                if !lines.isEmpty { message = nil }
            }

            guard !Task.isCancelled, self.currentSong?.id == song.id else { return }
            self.lyricLines = lines
            self.lyricError = lines.isEmpty ? (message ?? "暂无歌词") : nil
            self.isLoadingLyrics = false
            self.syncNowPlaying()
        }
    }

    /// 预载下一曲：提前解析地址并写入本地缓存
    private func preloadNext() {
        let nextIndex = currentIndex + 1
        guard queue.indices.contains(nextIndex) else { return }
        let song = queue[nextIndex]
        guard song.id > 0,
              AudioCache.cachedURL(songId: song.id) == nil,
              !preloadingSongs.contains(song.id)
        else { return }

        preloadingSongs.insert(song.id)
        Task { [weak self] in
            defer { self?.preloadingSongs.remove(song.id) }
            guard let url = try? await self?.resolveStreamURL(for: song) else { return }
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
        if sleepAfterCurrentTrack {
            cancelSleepTimer()
            pause()
            return
        }
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
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0
        ]
        if let album = song.albumName, !album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        guard let pic = currentCoverURL ?? song.albumPicUrl, let url = URL(string: pic) else { return }
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
            coverURL: currentCoverURL ?? song.albumPicUrl,
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
