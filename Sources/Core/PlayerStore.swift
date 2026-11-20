import AVFoundation
import MediaPlayer
import UIKit

/// 播放核心：AVPlayer 队列 + 后台音频 + 锁屏信息/控制 + 本地缓存
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

    /// 登录 Cookie（由 RootView 同步）
    var cookie: String?

    private let player = AVPlayer()
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var timeObserver: Any?
    /// 正在预载/缓存中的歌曲，避免重复下载
    private var preloadingSongs: Set<Int> = []

    init() {
        configureAudioSession()
        registerRemoteCommands()
        observeInterruptions()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
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
        await loadCurrent()
    }

    func togglePlayPause() {
        guard currentSong != nil else { return }
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func next() async {
        guard !queue.isEmpty else { return }
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            await loadCurrent()
        } else {
            pause()
        }
    }

    func previous() async {
        guard !queue.isEmpty else { return }
        let elapsed = CMTimeGetSeconds(player.currentTime())
        if elapsed > 3 || currentIndex == 0 {
            _ = await player.seek(to: .zero)
            updateNowPlaying()
            return
        }
        currentIndex -= 1
        await loadCurrent()
    }

    // MARK: - 播放

    private func resume() {
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    private func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    private func loadCurrent() async {
        guard queue.indices.contains(currentIndex) else { return }
        let song = queue[currentIndex]
        currentSong = song
        isLoading = true
        errorText = nil
        currentTime = 0
        removeEndObserver()

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
                cacheInBackground(url: remoteURL, songId: song.id)
            }

            player.replaceCurrentItem(with: item)
            observeItem(item)
            player.play()
            isPlaying = true
            isLoading = false
            updateNowPlaying()
            preloadNext()
        } catch {
            isLoading = false
            isPlaying = false
            errorText = error.localizedDescription
        }
    }

    /// 重试当前歌曲
    func retry() async {
        guard currentSong != nil else { return }
        await loadCurrent()
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
        Task {
            defer { preloadingSongs.remove(song.id) }
            guard let url = try? await NeteaseAPI().songURL(
                id: song.id,
                level: AppSettings.audioLevel,
                cookie: cookie
            ) else { return }
            await download(url: url, songId: song.id)
        }
    }

    private func cacheInBackground(url: URL, songId: Int) {
        Task {
            await download(url: url, songId: songId)
        }
    }

    private func download(url: URL, songId: Int) async {
        guard let (tmpURL, response) = try? await URLSession.shared.download(from: url) else { return }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return
        }
        AudioCache.store(tmpURL: tmpURL, songId: songId)
    }

    private func observeItem(_ item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.next()
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
    }

    private func updateNowPlaying() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyArtist: song.artistText,
            MPMediaItemPropertyPlaybackDuration: Double(song.duration) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: CMTimeGetSeconds(player.currentTime()),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let album = song.albumName, !album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        guard let pic = song.albumPicUrl, let url = URL(string: pic) else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data)
            else { return }
            guard self.currentSong?.id == song.id else { return }

            var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            current[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = current
        }
    }
}
