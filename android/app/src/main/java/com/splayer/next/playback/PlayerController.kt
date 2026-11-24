package com.splayer.next.playback

import android.content.ComponentName
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.splayer.next.data.Song
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * UI 与播放服务之间的单例桥接：把 MediaController 的播放状态映射成 Compose State，
 * 便于界面直接用 PlayerController.currentSong / isPlaying / positionMs 渲染。
 */
object PlayerController {

    private var controller: MediaController? = null
    private var connecting = false
    private var queue: List<Song> = emptyList()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    var currentSong by mutableStateOf<Song?>(null)
        private set
    var isPlaying by mutableStateOf(false)
        private set
    var positionMs by mutableStateOf(0L)
        private set
    var durationMs by mutableStateOf(0L)
        private set

    private val listener = object : Player.Listener {
        override fun onIsPlayingChanged(playing: Boolean) {
            isPlaying = playing
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            syncCurrentSong(mediaItem)
            positionMs = 0L
            durationMs = controller?.duration?.coerceAtLeast(0L) ?: 0L
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_READY) {
                durationMs = controller?.duration?.coerceAtLeast(0L) ?: 0L
            }
        }
    }

    init {
        scope.launch {
            while (isActive) {
                controller?.let { active ->
                    if (active.isPlaying) {
                        positionMs = active.currentPosition.coerceAtLeast(0L)
                        if (active.duration > 0) {
                            durationMs = active.duration
                        }
                    }
                }
                delay(500)
            }
        }
    }

    fun connect(context: Context) {
        if (controller != null || connecting) return
        connecting = true
        val appContext = context.applicationContext
        val token = SessionToken(appContext, ComponentName(appContext, PlaybackService::class.java))
        val future = MediaController.Builder(appContext, token).buildAsync()
        future.addListener(
            {
                runCatching {
                    val connected = future.get()
                    controller = connected
                    connected.addListener(listener)
                    syncCurrentSong(connected.currentMediaItem)
                    isPlaying = connected.isPlaying
                }
                connecting = false
            },
            ContextCompat.getMainExecutor(appContext)
        )
    }

    fun play(songs: List<Song>, index: Int) {
        val active = controller ?: return
        if (songs.isEmpty()) return
        queue = songs
        val safeIndex = index.coerceIn(0, songs.lastIndex)
        active.setMediaItems(songs.map { it.toMediaItem() }, safeIndex, 0L)
        active.prepare()
        active.play()
        currentSong = songs[safeIndex]
    }

    fun toggle() {
        val active = controller ?: return
        if (active.isPlaying) {
            active.pause()
        } else {
            if (active.playbackState == Player.STATE_IDLE) {
                active.prepare()
            }
            active.play()
        }
    }

    fun next() {
        controller?.seekToNextMediaItem()
    }

    fun previous() {
        controller?.seekToPreviousMediaItem()
    }

    fun seekTo(position: Long) {
        val safePosition = position.coerceAtLeast(0L)
        controller?.seekTo(safePosition)
        positionMs = safePosition
    }

    private fun syncCurrentSong(mediaItem: MediaItem?) {
        val id = mediaItem?.mediaId ?: return
        currentSong = queue.firstOrNull { it.id == id } ?: currentSong
    }

    private fun Song.toMediaItem(): MediaItem = MediaItem.Builder()
        .setMediaId(id)
        .setUri(url)
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(title)
                .setArtist(artist)
                .setAlbumTitle(album)
                .build()
        )
        .build()
}