package com.splayer.next.playback

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.splayer.next.data.AppSettings
import com.splayer.next.data.Lyric
import com.splayer.next.data.MusicRepository
import com.splayer.next.data.NetEaseApi
import com.splayer.next.data.Song
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * UI 与播放服务之间的单例桥接：把 MediaController 的播放状态映射成 Compose State，
 * 并维护队列、播放模式、歌词、倍速、音量与睡眠定时。
 */
object PlayerController {

    private var controller: MediaController? = null
    private var connecting = false
    private var appContext: Context? = null
    private var pending: (() -> Unit)? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    var currentSong by mutableStateOf<Song?>(null)
        private set
    var queue by mutableStateOf<List<Song>>(emptyList())
        private set
    var currentIndex by mutableStateOf(0)
        private set
    var isPlaying by mutableStateOf(false)
        private set
    var isBuffering by mutableStateOf(false)
        private set
    var positionMs by mutableStateOf(0L)
        private set
    var durationMs by mutableStateOf(0L)
        private set
    var errorText by mutableStateOf<String?>(null)
        private set
    var isReady by mutableStateOf(false)
        private set

    var lyric by mutableStateOf(Lyric())
        private set
    var isLoadingLyric by mutableStateOf(false)
        private set
    var currentLyricIndex by mutableStateOf(-1)
        private set

    /** 0 顺序 / 1 列表循环 / 2 单曲循环 */
    var repeatMode by mutableStateOf(AppSettings.repeatMode)
        private set
    var shuffle by mutableStateOf(AppSettings.shuffle)
        private set
    var playbackRate by mutableStateOf(AppSettings.playbackRate)
        private set
    var volume by mutableStateOf(AppSettings.volume)
        private set

    var sleepTimerActive by mutableStateOf(false)
        private set
    var sleepRemainingSeconds by mutableStateOf(0L)
        private set
    var sleepAtTrackEnd by mutableStateOf(false)
        private set

    private var lyricJob: Job? = null
    private var sleepJob: Job? = null
    private var sleepEndAt = 0L
    private var pauseAfterTrack = false

    val sleepLabel: String?
        get() = when {
            sleepAtTrackEnd -> "曲末暂停"
            sleepTimerActive -> "定时 %d:%02d".format(
                sleepRemainingSeconds / 60,
                sleepRemainingSeconds % 60
            )
            else -> null
        }

    private val listener = object : Player.Listener {
        override fun onIsPlayingChanged(playing: Boolean) {
            isPlaying = playing
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            isBuffering = playbackState == Player.STATE_BUFFERING
            if (playbackState == Player.STATE_READY) {
                val itemDuration = controller?.duration ?: 0L
                if (itemDuration > 0L) durationMs = itemDuration
            }
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            syncCurrentSong(mediaItem)
            positionMs = 0L
            durationMs = currentSong?.durationMs ?: 0L
            currentLyricIndex = -1
            loadLyrics(currentSong)
            if (pauseAfterTrack && reason == Player.MEDIA_ITEM_TRANSITION_REASON_AUTO) {
                controller?.pause()
                cancelSleepTimer()
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            errorText = "播放失败：${error.errorCodeName}"
            isBuffering = false
        }

        override fun onRepeatModeChanged(repeatMode: Int) {
            val mapped = when (repeatMode) {
                Player.REPEAT_MODE_ALL -> 1
                Player.REPEAT_MODE_ONE -> 2
                else -> 0
            }
            if (PlayerController.repeatMode != mapped) {
                PlayerController.repeatMode = mapped
                AppSettings.setRepeatMode(mapped)
            }
        }

        override fun onShuffleModeEnabledChanged(enabled: Boolean) {
            shuffle = enabled
            AppSettings.setShuffle(enabled)
        }

        override fun onPlaybackParametersChanged(params: PlaybackParameters) {
            playbackRate = params.speed
            AppSettings.setPlaybackRate(params.speed)
        }
    }

    init {
        // 进度与歌词索引轮询
        scope.launch {
            while (isActive) {
                controller?.let { active ->
                    positionMs = active.currentPosition.coerceAtLeast(0L)
                    val itemDuration = active.duration
                    if (itemDuration > 0L) {
                        durationMs = itemDuration
                    } else if (durationMs <= 0L) {
                        durationMs = currentSong?.durationMs ?: 0L
                    }
                    updateLyricIndex()
                }
                delay(400)
            }
        }
    }

    // MARK: - 连接

    fun connect(context: Context) {
        if (controller != null || connecting) return
        connecting = true
        val app = context.applicationContext
        appContext = app
        val token = SessionToken(app, ComponentName(app, PlaybackService::class.java))
        val future = MediaController.Builder(app, token).buildAsync()
        future.addListener(
            {
                runCatching {
                    val connected = future.get()
                    controller = connected
                    connected.addListener(listener)
                    connected.repeatMode = mapRepeat(repeatMode)
                    connected.shuffleModeEnabled = shuffle
                    connected.setPlaybackParameters(PlaybackParameters(playbackRate))
                    connected.volume = volume
                    syncCurrentSong(connected.currentMediaItem)
                    isPlaying = connected.isPlaying
                    isReady = true
                    pending?.invoke()
                    pending = null
                }
                connecting = false
            },
            ContextCompat.getMainExecutor(app)
        )
    }

    // MARK: - 播放控制

    fun play(songs: List<Song>, index: Int) {
        if (songs.isEmpty()) return
        queue = songs
        val safeIndex = index.coerceIn(0, songs.lastIndex)
        currentIndex = safeIndex
        currentSong = songs[safeIndex]
        positionMs = 0L
        durationMs = songs[safeIndex].durationMs
        currentLyricIndex = -1
        errorText = null
        AppSettings.addRecent(songs[safeIndex])
        loadLyrics(songs[safeIndex])

        val active = controller
        if (active == null) {
            pending = { play(songs, safeIndex) }
            appContext?.let { connect(it) }
            return
        }
        active.setMediaItems(songs.map { it.toMediaItem() }, safeIndex, 0L)
        active.prepare()
        active.play()
    }

    fun playAt(index: Int) {
        val active = controller ?: return
        if (index !in queue.indices) return
        currentIndex = index
        currentSong = queue[index]
        positionMs = 0L
        durationMs = queue[index].durationMs
        currentLyricIndex = -1
        errorText = null
        AppSettings.addRecent(queue[index])
        loadLyrics(queue[index])
        active.seekToDefaultPosition(index)
        active.play()
    }

    fun addToQueue(song: Song) {
        val active = controller ?: return
        active.addMediaItem(song.toMediaItem())
        queue = queue + song
    }

    fun removeFromQueue(index: Int) {
        val active = controller ?: return
        if (index !in queue.indices) return
        active.removeMediaItem(index)
        queue = queue.filterIndexed { i, _ -> i != index }
    }

    fun toggle() {
        val active = controller ?: return
        if (active.isPlaying) {
            active.pause()
        } else {
            if (active.playbackState == Player.STATE_IDLE) active.prepare()
            active.play()
        }
    }

    fun next() {
        controller?.seekToNextMediaItem()
    }

    fun previous() {
        val active = controller ?: return
        if (active.currentPosition > 3_000L) {
            active.seekTo(0L)
        } else {
            active.seekToPreviousMediaItem()
        }
    }

    fun seekTo(positionMs: Long) {
        val active = controller ?: return
        val safe = positionMs.coerceAtLeast(0L)
        active.seekTo(safe)
        this.positionMs = safe
        updateLyricIndex()
    }

    /** 进度条拖拽得到的是比例换算后的 Float 毫秒，这里统一转换 */
    fun seekTo(positionMs: Float) = seekTo(positionMs.toLong())

    fun setRepeatMode(mode: Int) {
        repeatMode = mode.coerceIn(0, 2)
        AppSettings.setRepeatMode(repeatMode)
        controller?.repeatMode = mapRepeat(repeatMode)
    }

    fun cycleRepeatMode() {
        setRepeatMode((repeatMode + 1) % 3)
    }

    fun toggleShuffle() {
        shuffle = !shuffle
        AppSettings.setShuffle(shuffle)
        controller?.shuffleModeEnabled = shuffle
    }

    fun setPlaybackRate(rate: Float) {
        playbackRate = rate
        AppSettings.setPlaybackRate(rate)
        controller?.setPlaybackParameters(PlaybackParameters(rate))
    }

    fun setVolume(value: Float) {
        volume = value.coerceIn(0f, 1f)
        AppSettings.setVolume(volume)
        controller?.volume = volume
    }

    fun clearError() {
        errorText = null
    }

    // MARK: - 睡眠定时

    fun startSleepTimer(minutes: Int) {
        if (minutes <= 0) return
        cancelSleepTimer()
        pauseAfterTrack = false
        sleepAtTrackEnd = false
        sleepEndAt = System.currentTimeMillis() + minutes * 60_000L
        sleepTimerActive = true
        sleepRemainingSeconds = minutes * 60L
        sleepJob = scope.launch {
            while (isActive) {
                val remain = (sleepEndAt - System.currentTimeMillis()) / 1000L
                sleepRemainingSeconds = remain.coerceAtLeast(0L)
                if (remain <= 0L) {
                    sleepTimerActive = false
                    controller?.pause()
                    break
                }
                delay(1000)
            }
        }
    }

    fun startSleepAtTrackEnd() {
        cancelSleepTimer()
        pauseAfterTrack = true
        sleepAtTrackEnd = true
        sleepTimerActive = true
    }

    fun cancelSleepTimer() {
        sleepJob?.cancel()
        sleepJob = null
        sleepTimerActive = false
        sleepRemainingSeconds = 0L
        sleepAtTrackEnd = false
        pauseAfterTrack = false
    }

    // MARK: - 内部

    private fun loadLyrics(song: Song?) {
        lyricJob?.cancel()
        lyric = Lyric()
        currentLyricIndex = -1
        if (song == null) {
            isLoadingLyric = false
            return
        }
        isLoadingLyric = true
        lyricJob = scope.launch {
            val result = MusicRepository.lyric(song.id)
            if (currentSong?.id == song.id) {
                lyric = result
                isLoadingLyric = false
                updateLyricIndex()
            }
        }
    }

    private fun updateLyricIndex() {
        val lines = lyric.lines
        if (lines.isEmpty()) {
            if (currentLyricIndex != -1) currentLyricIndex = -1
            return
        }
        var index = -1
        for (i in lines.indices) {
            if (lines[i].timeMs <= positionMs + 200L) index = i else break
        }
        if (index != currentLyricIndex) currentLyricIndex = index
    }

    private fun syncCurrentSong(mediaItem: MediaItem?) {
        val id = mediaItem?.mediaId ?: return
        val index = controller?.currentMediaItemIndex ?: queue.indexOfFirst { it.id == id }
        if (index in queue.indices) {
            currentIndex = index
            val song = queue[index]
            if (currentSong?.id != song.id) {
                currentSong = song
                AppSettings.addRecent(song)
            }
        } else {
            queue.firstOrNull { it.id == id }?.let { currentSong = it }
        }
    }

    private fun mapRepeat(mode: Int): Int = when (mode) {
        1 -> Player.REPEAT_MODE_ALL
        2 -> Player.REPEAT_MODE_ONE
        else -> Player.REPEAT_MODE_OFF
    }

    private fun Song.toMediaItem(): MediaItem {
        val uri = streamUrl.ifBlank {
            if (id.toLongOrNull() != null) NetEaseApi.streamUrl(id) else ""
        }
        val artwork = coverUrl?.takeIf { it.isNotBlank() }
        val metadata = MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(artist)
            .setAlbumTitle(album)
            .apply { artwork?.let { setArtworkUri(Uri.parse(it)) } }
            .build()
        return MediaItem.Builder()
            .setMediaId(id)
            .setUri(uri)
            .setMediaMetadata(metadata)
            .build()
    }
}