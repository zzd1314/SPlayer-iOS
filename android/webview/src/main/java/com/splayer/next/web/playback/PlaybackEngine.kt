package com.splayer.next.web.playback

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.splayer.next.web.Json
import com.splayer.next.web.SPlayerBridge
import com.splayer.next.web.api.BridgeUnsupportedException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 播放引擎：Media3 内核承接原 Rust audio-engine 的播放契约（window.api.player.*）。
 * 负责状态快照推送、进度推送、结束事件与系统媒体会话元数据。
 */
object PlaybackEngine {

    private const val CHANNEL_PLAYER = "player:event"
    private const val POSITION_INTERVAL_MS = 200L

    private lateinit var appContext: Context
    private var bridgeRef: SPlayerBridge? = null
    private var player: ExoPlayer? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var initialized = false

    // MARK: - 生命周期

    fun init(context: Context, bridge: SPlayerBridge) {
        if (initialized) return
        initialized = true
        appContext = context.applicationContext
        bridgeRef = bridge
        mainHandler.post { ensurePlayer() }
    }

    private fun bridge(): SPlayerBridge? = bridgeRef

    /** PlaybackService 复用同一播放器实例 */
    fun attachPlayer(context: Context): ExoPlayer {
        if (!initialized) {
            initialized = true
            appContext = context.applicationContext
        }
        return ensurePlayer()
    }

    /** 服务销毁后释放，待下次播放时重建 */
    fun releasePlayer() {
        player = null
    }

    private fun ensurePlayer(): ExoPlayer {
        player?.let { return it }
        val p = ExoPlayer.Builder(appContext).build()
        p.addListener(listener)
        player = p
        return p
    }

    /** JS 桥线程调用：惰性启动前台服务，保证后台播放与锁屏控制 */
    private fun ensureService() {
        val intent = Intent(appContext, PlaybackService::class.java)
        appContext.startForegroundService(intent)
    }

    // MARK: - 播放器监听

    private val positionTicker = object : Runnable {
        override fun run() {
            val p = player ?: return
            if (p.isPlaying) {
                pushEvent(
                    "position",
                    mapOf("position" to p.currentPosition, "duration" to p.duration.coerceAtLeast(0))
                )
                mainHandler.postDelayed(this, POSITION_INTERVAL_MS)
            }
        }
    }

    private val listener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            pushStatus()
            if (isPlaying) mainHandler.postDelayed(positionTicker, POSITION_INTERVAL_MS)
        }

        override fun onPlaybackStateChanged(state: Int) {
            if (state == Player.STATE_ENDED) {
                pushEvent("ended", emptyMap<String, Any>())
            }
            pushStatus()
        }

        override fun onPlaybackParametersChanged(parameters: PlaybackParameters) {
            pushStatus()
        }

        override fun onPlayerError(error: PlaybackException) {
            pushEvent("sourceError", emptyMap<String, Any>())
        }
    }

    // MARK: - 状态快照

    private fun playerState(): String {
        val p = player ?: return "idle"
        return when (p.playbackState) {
            Player.STATE_IDLE -> "idle"
            Player.STATE_ENDED -> "stopped"
            else -> if (p.playWhenReady) "playing" else "paused"
        }
    }

    private fun statusSnapshot(): Map<String, Any> {
        val p = player
        return mapOf(
            "state" to playerState(),
            "position" to (p?.currentPosition ?: 0L),
            "duration" to (p?.duration?.coerceAtLeast(0) ?: 0L),
            "volume" to (p?.volume?.toDouble() ?: 1.0),
            "speed" to (p?.playbackParameters?.speed?.toDouble() ?: 1.0),
            "isFinished" to (p?.playbackState == Player.STATE_ENDED),
        )
    }

    private fun pushStatus() {
        pushEvent("status", statusSnapshot())
    }

    private fun pushEvent(type: String, data: Any) {
        val payload = Json.write(mapOf("type" to type, "data" to data))
        bridge()?.pushEvent(CHANNEL_PLAYER, payload)
    }

    // MARK: - 桥接分发

    fun handle(method: String, args: List<Any?>): Any? {
        val success: Map<String, Any> = mapOf("success" to true)
        return when (method) {
            "load" -> handleLoad(args)
            "play" -> { main { player?.play() }; success }
            "pause" -> { main { player?.pause() }; success }
            "stop" -> { main { player?.stop(); player?.clearMediaItems() }; success }
            "seek" -> {
                val position = (args.getOrNull(0) as? Number)?.toLong() ?: 0L
                main { player?.seekTo(position) }
                pushEvent("seek", mapOf("position" to position))
                success
            }

            "setVolume" -> {
                val volume = ((args.getOrNull(0) as? Number)?.toFloat() ?: 1f).coerceIn(0f, 1f)
                main { player?.volume = volume }
                pushStatus()
                success
            }

            "getVolume" -> mapOf("success" to true, "data" to (player?.volume?.toDouble() ?: 1.0))
            "setSpeed" -> {
                val speed = (args.getOrNull(0) as? Number)?.toFloat() ?: 1f
                main { player?.setPlaybackSpeed(speed) }
                success
            }

            "getStatus" -> mapOf("success" to true, "data" to statusSnapshot())
            "getOutputDevices" -> mapOf(
                "success" to true,
                "data" to listOf(
                    mapOf("id" to "default", "name" to "设备扬声器", "isDefault" to true),
                ),
            )

            "getDefaultDeviceName" -> mapOf("success" to true, "data" to "default")
            "getSelectedDeviceName" -> mapOf("success" to true, "data" to null)
            "getFftData" -> mapOf(
                "success" to true,
                "data" to mapOf("ldata" to emptyList<Int>(), "rdata" to emptyList<Int>()),
            )

            "getCoverRaw" -> mapOf("success" to true, "data" to null)
            "readLyricFile" -> mapOf("success" to false, "error" to "not supported")

            // 桌面专属 / 预载相关：默认成功空实现，保证渲染层流程不中断
            else -> success
        }
    }

    private fun handleLoad(args: List<Any?>): Any? {
        val source = args.getOrNull(0)?.toString() ?: throw BridgeUnsupportedException("load: 缺少音源")
        val options = args.getOrNull(1) as? Map<*, *>
        val meta = options?.get("meta") as? Map<*, *>
        ensureService()
        main {
            val p = ensurePlayer()
            val item = MediaItem.Builder()
                .setUri(source)
                .setMediaMetadata(buildMetadata(meta))
                .build()
            p.setMediaItem(item)
            p.prepare()
            p.play()
        }
        return mapOf(
            "success" to true,
            "data" to mapOf(
                "detail" to mapOf(
                    "quality" to null,
                    "externalLyrics" to emptyList<Any>(),
                ),
                "mediaInfo" to mapOf("duration" to 0),
            ),
        )
    }

    private fun buildMetadata(meta: Map<*, *>?): MediaMetadata {
        if (meta == null) return MediaMetadata.EMPTY
        val artists = (meta["artists"] as? List<*>)?.mapNotNull {
            (it as? Map<*, *>)?.get("name")?.toString()?.ifBlank { null }
        }
        val cover = (meta["cover"] as? String).orEmpty().ifBlank {
            (meta["coverOriginal"] as? String).orEmpty()
        }
        val builder = MediaMetadata.Builder()
        (meta["title"] as? String)?.takeIf { it.isNotBlank() }?.let { builder.setTitle(it) }
        artists?.joinToString(" / ")?.takeIf { it.isNotBlank() }?.let { builder.setArtist(it) }
        (meta["album"] as? String)?.takeIf { it.isNotBlank() }?.let { builder.setAlbumTitle(it) }
        if (cover.startsWith("http")) builder.setArtworkUri(android.net.Uri.parse(cover))
        return builder.build()
    }

    private fun main(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
    }

    // MARK: - MediaSession 回调（由 PlaybackService 调用）

    /** 系统媒体控件：下一首 / 上一首转发给渲染层 */
    fun onSkipToNext() = pushEvent("next", emptyMap<String, Any>())

    fun onSkipToPrevious() = pushEvent("prev", emptyMap<String, Any>())

    /** 系统媒体控件：seekTo */
    fun onSeekTo(positionMs: Long) {
        main { player?.seekTo(positionMs) }
        pushEvent("seek", mapOf("position" to positionMs))
    }
}