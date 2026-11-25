package com.splayer.next.web.playback

import android.content.Context
import android.content.Intent
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.audiofx.Equalizer
import android.media.audiofx.Visualizer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.AudioAttributes
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.splayer.next.web.Json
import com.splayer.next.web.SPlayerBridge
import com.splayer.next.web.api.BridgeUnsupportedException
import com.splayer.next.web.nowplaying.NowPlayingState
import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * 播放引擎：Media3 承接上游 Rust audio-engine 的播放契约（window.api.player.*）。
 *
 * 与上游 `electron/main/ipc/player.ts` 对齐的部分：
 *  - load 返回 mediaInfo（时长 / 采样率 / 声道 / 码率 / 编码），渲染层据此推进进度条与歌词
 *  - 事件：status / position / ended / sourceError / seek / fftData
 *  - 淡入淡出、音频焦点、变速变调、均衡器、暂停即释放频谱
 *
 * 线程模型：Media3 只允许主线程访问播放器，而桥接调用来自 IO 协程，
 * 因此除 load（需要等待 READY 拿时长，阻塞 IO 线程安全）外统一切主线程同步执行。
 */
object PlaybackEngine {

    private const val TAG = "PlaybackEngine"
    private const val CHANNEL_PLAYER = "player:event"
    private const val POSITION_INTERVAL_MS = 200L
    private const val FFT_INTERVAL_MS = 33L
    private const val FADE_STEP_MS = 16L
    private const val LOAD_WAIT_MS = 8_000L
    private const val FFT_BANDS = 128
    private const val DUCK_FACTOR = 0.2f

    private lateinit var appContext: Context
    private var bridgeRef: SPlayerBridge? = null
    private var player: ExoPlayer? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var initialized = false

    // MARK: - 音量 / 淡入淡出

    /** 用户设定的目标音量；淡入淡出围绕它进行 */
    private var targetVolume = 1.0f
    private var fadeDurationMs = 0
    private var fadeRunnable: Runnable? = null
    private var ducked = false

    // MARK: - 音调

    private var pitchSync = true
    private var pitchSemitones = 0.0

    // MARK: - 音频焦点

    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
    private var focusHeld = false
    private var resumeOnFocusGain = false
    private var allowMixWithOthers = false

    // MARK: - FFT

    private var fftEnabled = false
    private var visualizer: Visualizer? = null
    private var visualizerSession = 0
    private val fftLock = Any()
    private var fftLeft = FloatArray(FFT_BANDS)
    private var fftRight = FloatArray(FFT_BANDS)
    private var fftTicker: Runnable? = null

    // MARK: - 均衡器

    private var equalizer: Equalizer? = null
    private var equalizerSession = 0
    private var eqEnabled = false
    private var eqGains: FloatArray? = null

    // MARK: - 生命周期

    fun init(context: Context, bridge: SPlayerBridge) {
        if (initialized) return
        initialized = true
        appContext = context.applicationContext
        bridgeRef = bridge
        installAudioInfrastructure()
        mainHandler.post { ensurePlayer() }
    }

    /** PlaybackService 复用同一播放器实例 */
    fun attachPlayer(context: Context): ExoPlayer {
        if (!initialized) {
            initialized = true
            appContext = context.applicationContext
            installAudioInfrastructure()
        }
        return ensurePlayer()
    }

    /** 服务销毁后释放，待下次播放时重建 */
    fun releasePlayer() {
        cancelFade()
        releaseFftCapture()
        runCatching { equalizer?.release() }
        equalizer = null
        player = null
    }

    private fun ensurePlayer(): ExoPlayer {
        player?.let { return it }
        val attrs = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
            .build()
        val p = ExoPlayer.Builder(appContext)
            .setAudioAttributes(attrs, true)
            // 耳机拔出由引擎直接暂停，再经 onIsPlayingChanged 推给渲染层
            .setHandleAudioBecomingNoisy(true)
            .build()
        p.setWakeMode(C.WAKE_MODE_NETWORK)
        p.volume = if (ducked) targetVolume * DUCK_FACTOR else targetVolume
        p.addListener(listener)
        player = p
        return p
    }

    /** JS 桥线程调用：惰性启动前台服务，保证后台播放与锁屏控制 */
    private fun ensureService() {
        val intent = Intent(appContext, PlaybackService::class.java)
        runCatching { appContext.startForegroundService(intent) }
    }

    // MARK: - 音频焦点

    private fun installAudioInfrastructure() {
        val am = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        audioManager = am
        val attrs = android.media.AudioAttributes.Builder()
            .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attrs)
            .setWillPauseWhenDucked(false)
            .setOnAudioFocusChangeListener({ change -> mainHandler.post { onAudioFocusChange(change) } })
            .build()
    }

    private fun ensureAudioFocus(): Boolean {
        if (allowMixWithOthers) return true
        val am = audioManager ?: return true
        val request = focusRequest ?: return true
        val result = runCatching { am.requestAudioFocus(request) }
            .getOrDefault(AudioManager.AUDIOFOCUS_REQUEST_FAILED)
        focusHeld = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return focusHeld
    }

    private fun abandonAudioFocus() {
        val am = audioManager ?: return
        val request = focusRequest ?: return
        focusHeld = false
        resumeOnFocusGain = false
        runCatching { am.abandonAudioFocusRequest(request) }
    }

    private fun onAudioFocusChange(change: Int) {
        if (allowMixWithOthers) return
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                resumeOnFocusGain = false
                ducked = false
                player?.volume = targetVolume
                player?.pause()
                pushStatus()
            }

            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                resumeOnFocusGain = player?.isPlaying == true
                player?.pause()
                pushStatus()
            }

            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                ducked = true
                player?.volume = targetVolume * DUCK_FACTOR
            }

            AudioManager.AUDIOFOCUS_GAIN -> {
                ducked = false
                player?.volume = targetVolume
                if (resumeOnFocusGain) {
                    resumeOnFocusGain = false
                    player?.play()
                }
                pushStatus()
            }
        }
    }

    // MARK: - 播放器监听

    private val positionTicker = object : Runnable {
        override fun run() {
            val p = player ?: return
            if (p.isPlaying) {
                NowPlayingState.onPosition(p.currentPosition, true)
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
            if (isPlaying) {
                startFftIfNeeded()
                mainHandler.postDelayed(positionTicker, POSITION_INTERVAL_MS)
            } else if (player?.playbackState != Player.STATE_ENDED) {
                releaseFftCapture()
            }
        }

        override fun onPlaybackStateChanged(state: Int) {
            when (state) {
                Player.STATE_ENDED -> {
                    releaseFftCapture()
                    pushEvent("ended", emptyMap<String, Any>())
                }

                Player.STATE_READY -> {
                    pushStatus()
                    applyEqualizer()
                }
            }
        }

        override fun onPlaybackParametersChanged(parameters: PlaybackParameters) {
            pushStatus()
        }

        override fun onPlayerError(error: PlaybackException) {
            releaseFftCapture()
            pushEvent("sourceError", emptyMap<String, Any>())
        }
    }

    // MARK: - 状态快照

    private fun playerState(): String {
        val p = player ?: return "idle"
        return when (p.playbackState) {
            Player.STATE_IDLE -> "idle"
            Player.STATE_ENDED -> "stopped"
            Player.STATE_BUFFERING -> if (p.playWhenReady) "loading" else "paused"
            else -> if (p.isPlaying) "playing" else "paused"
        }
    }

    private fun statusSnapshot(): LinkedHashMap<String, Any?> {
        val p = player
        return linkedMapOf(
            "state" to playerState(),
            "position" to (p?.currentPosition ?: 0L),
            "duration" to (p?.duration?.coerceAtLeast(0L) ?: 0L),
            "volume" to targetVolume.toDouble(),
            "speed" to (p?.playbackParameters?.speed?.toDouble() ?: 1.0),
            "isFinished" to (p?.playbackState == Player.STATE_ENDED),
        )
    }

    private fun pushStatus(
        stateOverride: String? = null,
        positionOverride: Long? = null,
        durationOverride: Long? = null,
    ) {
        val snapshot = statusSnapshot()
        if (stateOverride != null) snapshot["state"] = stateOverride
        if (positionOverride != null) snapshot["position"] = positionOverride
        if (durationOverride != null) snapshot["duration"] = durationOverride
        NowPlayingState.syncStatus(
            state = snapshot["state"] as? String ?: "idle",
            positionMs = (snapshot["position"] as? Number)?.toLong() ?: 0L,
            speedValue = (snapshot["speed"] as? Number)?.toDouble() ?: 1.0,
        )
        pushEvent("status", snapshot)
    }

    private fun pushEvent(type: String, data: Any) {
        val payload = Json.write(mapOf("type" to type, "data" to data))
        bridge()?.pushEvent(CHANNEL_PLAYER, payload)
    }

    private fun bridge(): SPlayerBridge? = bridgeRef

    // MARK: - 桥接分发

    /**
     * 桥接调用入口。Media3 要求主线程访问播放器，而桥接调用来自 Dispatchers.IO，
     * 这里统一切主线程同步执行；load 需要等待 READY 拿时长，单独在 IO 线程等待。
     */
    fun handle(method: String, args: List<Any?>): Any? {
        if (method == "load") return handleLoad(args)
        if (Looper.myLooper() == Looper.getMainLooper()) return handleOnMain(method, args)
        var result: Any? = null
        var failure: Throwable? = null
        val latch = CountDownLatch(1)
        val posted = mainHandler.post {
            try {
                result = handleOnMain(method, args)
            } catch (t: Throwable) {
                failure = t
            } finally {
                latch.countDown()
            }
        }
        if (!posted) throw IllegalStateException("player.$method：主线程不可用")
        if (!latch.await(10, TimeUnit.SECONDS)) {
            throw IllegalStateException("player.$method：主线程执行超时")
        }
        failure?.let { throw it }
        return result
    }

    private fun handleOnMain(method: String, args: List<Any?>): Any? {
        val success: Map<String, Any> = mapOf("success" to true)
        return when (method) {
            "play" -> {
                startPlayback()
                success
            }

            "pause" -> {
                pauseWithFade()
                success
            }

            "stop" -> {
                stopPlayback()
                success
            }

            "seek" -> {
                val position = (args.getOrNull(0) as? Number)?.toLong() ?: 0L
                player?.seekTo(position.coerceAtLeast(0L))
                pushEvent("seek", mapOf("position" to position))
                success
            }

            "setVolume" -> {
                targetVolume = ((args.getOrNull(0) as? Number)?.toFloat() ?: 1f).coerceIn(0f, 1f)
                if (fadeRunnable == null) player?.volume = effectiveVolume()
                pushStatus()
                success
            }

            "getVolume" -> mapOf("success" to true, "data" to targetVolume.toDouble())

            "setFadeDuration" -> {
                fadeDurationMs = ((args.getOrNull(0) as? Number)?.toInt() ?: 0).coerceIn(0, 5000)
                success
            }

            "getFadeDuration" -> mapOf("success" to true, "data" to fadeDurationMs)

            "setSpeed" -> {
                applyPlaybackParameters((args.getOrNull(0) as? Number)?.toFloat() ?: 1f)
                success
            }

            "setPitch" -> {
                pitchSemitones = ((args.getOrNull(0) as? Number)?.toDouble() ?: 0.0).coerceIn(-12.0, 12.0)
                applyPlaybackParameters()
                success
            }

            "setPitchSync" -> {
                pitchSync = args.getOrNull(0) as? Boolean ?: true
                applyPlaybackParameters()
                success
            }

            "setFftEnabled" -> {
                setFftEnabled(args.getOrNull(0) as? Boolean ?: false)
                success
            }

            "getFftData" -> mapOf("success" to true, "data" to fftData())

            "getStatus" -> mapOf("success" to true, "data" to statusSnapshot())

            "getStreamInfo" -> mapOf("success" to true, "data" to streamInfo())

            "getCoverRaw" -> mapOf("success" to true, "data" to coverRaw())

            "readLyricFile" -> readLyricFile(args.getOrNull(0)?.toString().orEmpty())

            "getOutputDevices" -> mapOf(
                "success" to true,
                "data" to listOf(mapOf("id" to "default", "name" to "设备扬声器", "isDefault" to true)),
            )

            "getDefaultDeviceName" -> mapOf("success" to true, "data" to "default")
            "getSelectedDeviceName" -> mapOf("success" to true, "data" to null)

            "setEqualizerEnabled" -> {
                eqEnabled = args.getOrNull(0) as? Boolean ?: false
                applyEqualizer()
                success
            }

            "setEqualizerBands", "setEqualizer" -> {
                eqGains = (args.getOrNull(0) as? List<*>)?.map {
                    (it as? Number)?.toFloat() ?: 0f
                }?.toFloatArray()
                applyEqualizer()
                success
            }

            // Android Equalizer 没有独立前级，按“已应用”返回避免渲染层报错
            "setPreampGain" -> success

            // 智能切歌需要双实例交叉淡入，Media3 单实例无法等价实现；
            // 返回未命中后，渲染层会按 src/core/player/index.ts 的兜底走正常切歌
            "prepareNext" -> mapOf("ready" to false)
            "cancelPrepared" -> true
            "transitionPrepared" -> mapOf("success" to false)

            "setPauseOnDeviceSwitch", "setNormalizationEnabled", "reinit", "setOutputDevice",
            "setAllowMixWithOthers" -> {
                if (method == "setAllowMixWithOthers") {
                    allowMixWithOthers = args.getOrNull(0) as? Boolean ?: false
                    if (allowMixWithOthers) abandonAudioFocus() else ensureAudioFocus()
                }
                success
            }

            // 桌面 / 原生队列能力：Android 端队列由渲染层维护，这里保持无副作用
            else -> success
        }
    }

    // MARK: - 播放控制

    private fun startPlayback() {
        ensureAudioFocus()
        val p = player ?: return
        p.play()
        if (fadeDurationMs > 0 && !ducked) {
            p.volume = 0f
            fadeTo(targetVolume)
        } else {
            p.volume = effectiveVolume()
        }
    }

    private fun pauseWithFade() {
        if (fadeDurationMs > 0) {
            fadeTo(0f) { player?.pause() }
        } else {
            player?.pause()
        }
        abandonAudioFocus()
    }

    private fun stopPlayback() {
        cancelFade()
        releaseFftCapture()
        abandonAudioFocus()
        mainHandler.removeCallbacks(positionTicker)
        player?.stop()
        player?.clearMediaItems()
        pushStatus(stateOverride = "stopped", positionOverride = 0L, durationOverride = 0L)
    }

    private fun applyPlaybackParameters(speedOverride: Float? = null) {
        val p = player ?: return
        val speed = (speedOverride ?: p.playbackParameters.speed).coerceIn(0.5f, 2.0f)
        // 变速保调：pitch 固定 1；关闭保调时 pitch 跟随 speed（磁带式变调）
        val pitch = when {
            !pitchSync -> speed
            else -> Math.pow(2.0, pitchSemitones / 12.0).toFloat()
        }
        p.playbackParameters = PlaybackParameters(speed, pitch.coerceIn(0.5f, 2.0f))
    }

    private fun effectiveVolume(): Float = if (ducked) targetVolume * DUCK_FACTOR else targetVolume

    private fun cancelFade() {
        fadeRunnable?.let { mainHandler.removeCallbacks(it) }
        fadeRunnable = null
    }

    /** 线性音量渐变；结束后回调（用于淡出后再 pause） */
    private fun fadeTo(target: Float, after: (() -> Unit)? = null) {
        cancelFade()
        val p = player
        if (p == null || fadeDurationMs <= 0) {
            p?.volume = target.coerceIn(0f, 1f)
            after?.invoke()
            return
        }
        val start = p.volume
        val steps = (fadeDurationMs / FADE_STEP_MS).coerceAtLeast(1)
        var index = 0
        val runnable = object : Runnable {
            override fun run() {
                index++
                val progress = index.toFloat() / steps
                val current = start + (target - start) * progress
                player?.volume = current.coerceIn(0f, 1f)
                if (index < steps) {
                    mainHandler.postDelayed(this, FADE_STEP_MS)
                } else {
                    player?.volume = target.coerceIn(0f, 1f)
                    fadeRunnable = null
                    after?.invoke()
                }
            }
        }
        fadeRunnable = runnable
        mainHandler.post(runnable)
    }

    // MARK: - FFT 频谱

    private fun setFftEnabled(enabled: Boolean) {
        fftEnabled = enabled
        if (enabled) {
            // Visualizer 依赖录音权限：首次启用频谱时再申请
            com.splayer.next.web.WebHostActivity.requestRecordAudioPermissionIfNeeded()
            startFftIfNeeded()
        } else {
            releaseFftCapture()
        }
    }

    private fun startFftIfNeeded() {
        if (!fftEnabled) return
        val p = player ?: return
        if (!p.isPlaying) return
        ensureVisualizer(p.audioSessionId)
        runCatching { visualizer?.setEnabled(true) }
        if (fftTicker == null) {
            fftTicker = fftRunnable
            mainHandler.post(fftRunnable)
        }
    }

    private val fftRunnable = object : Runnable {
        override fun run() {
            if (!fftEnabled || player?.isPlaying != true) {
                fftTicker = null
                return
            }
            pushEvent("fftData", fftData())
            mainHandler.postDelayed(this, FFT_INTERVAL_MS)
        }
    }

    private fun fftData(): Map<String, Any?> = synchronized(fftLock) {
        mapOf("ldata" to fftLeft.toList(), "rdata" to fftRight.toList())
    }

    /** 原版 Rust 引擎自算 FFT；Android 端用系统 Visualizer 提供同规格数据（128 段，0.0-1.0） */
    private fun ensureVisualizer(audioSessionId: Int) {
        if (audioSessionId == 0) return
        if (visualizer != null && visualizerSession == audioSessionId) return
        releaseFftCapture()
        runCatching {
            @Suppress("DEPRECATION")
            val viz = Visualizer(audioSessionId)
            viz.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(v: Visualizer?, waveform: ByteArray?, samplingRate: Int) = Unit

                override fun onFftDataCapture(v: Visualizer?, fft: ByteArray?, samplingRate: Int) {
                    if (fft == null) return
                    val half = fft.size / 4
                    val left = FloatArray(FFT_BANDS)
                    val right = FloatArray(FFT_BANDS)
                    for (i in 0 until minOf(half, FFT_BANDS)) {
                        left[i] = magnitude(fft, i * 2)
                        right[i] = magnitude(fft, fft.size / 2 + i * 2)
                    }
                    synchronized(fftLock) {
                        fftLeft = left
                        fftRight = right
                    }
                }
            }, Visualizer.getMaxCaptureRate() / 2, false, true)
            visualizer = viz
            visualizerSession = audioSessionId
        }.onFailure {
            // RECORD_AUDIO 未授权或无 audioSession：频谱保持空数据，不影响播放
            android.util.Log.w(TAG, "Visualizer init failed: ${it.message}")
        }
    }

    private fun magnitude(fft: ByteArray, offset: Int): Float {
        if (offset + 1 >= fft.size) return 0f
        val re = fft[offset].toInt()
        val im = fft[offset + 1].toInt()
        // Visualizer FFT 为有符号字节，幅度上限约 180；统一归一化到 0.0-1.0
        return (Math.sqrt((re * re + im * im).toDouble()) / 180.0).toFloat().coerceIn(0f, 1f)
    }

    private fun releaseFftCapture() {
        fftTicker?.let { mainHandler.removeCallbacks(it) }
        fftTicker = null
        runCatching { visualizer?.setEnabled(false) }
        synchronized(fftLock) {
            fftLeft = FloatArray(FFT_BANDS)
            fftRight = FloatArray(FFT_BANDS)
        }
    }

    // MARK: - 均衡器

    private fun applyEqualizer() {
        val p = player ?: return
        val session = p.audioSessionId
        if (session == 0) return
        if (equalizer == null || equalizerSession != session) {
            runCatching { equalizer?.release() }
            equalizer = runCatching { Equalizer(0, session) }.getOrNull()
            equalizerSession = session
        }
        val eq = equalizer ?: return
        runCatching { eq.enabled = eqEnabled }
        val gains = eqGains ?: return
        runCatching {
            val bands = eq.numberOfBands.toInt()
            val range = eq.bandLevelRange
            for (i in 0 until bands) {
                val gainDb = gains.getOrNull(i * gains.size / bands) ?: 0f
                val milliBel = (gainDb * 100).toInt().coerceIn(range[0].toInt(), range[1].toInt())
                eq.setBandLevel(i.toShort(), milliBel.toShort())
            }
        }
    }

    // MARK: - 加载

    /**
     * 加载音源。ExoPlayer 的 prepare 是异步的，渲染层却需要 mediaInfo.duration 来画进度条，
     * 所以在桥接 IO 线程上等待 STATE_READY（最多 8s）；主线程保持可响应，不会死锁。
     */
    private fun handleLoad(args: List<Any?>): Any? {
        val source = args.getOrNull(0)?.toString().orEmpty()
        if (source.isBlank()) throw BridgeUnsupportedException("player.load: 缺少音源")
        val options = args.getOrNull(1) as? Map<*, *>
        val autoPlay = options?.get("autoPlay") as? Boolean ?: true
        val meta = options?.get("meta") as? Map<*, *>

        ensureService()

        val latch = CountDownLatch(1)
        val ready = booleanArrayOf(false)
        val duration = longArrayOf(0L)
        val quality = arrayOfNulls<Map<String, Any?>>(1)

        val oneShot = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_READY) {
                    val p = player
                    if (p != null) {
                        ready[0] = true
                        duration[0] = maxOf(p.duration.coerceAtLeast(0L), p.mediaMetadata.durationMs ?: 0L)
                        quality[0] = readQuality(p)
                    }
                    latch.countDown()
                } else if (state == Player.STATE_ENDED) {
                    latch.countDown()
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                latch.countDown()
            }
        }

        val posted = mainHandler.post {
            val p = ensurePlayer()
            p.addListener(oneShot)
            pushStatus(stateOverride = "loading", positionOverride = 0L, durationOverride = 0L)
            p.setMediaItem(
                MediaItem.Builder()
                    .setUri(source)
                    .setMediaMetadata(buildMetadata(meta))
                    .build()
            )
            p.prepare()
            if (autoPlay) startPlayback()
        }

        if (posted && Looper.myLooper() != Looper.getMainLooper()) {
            latch.await(LOAD_WAIT_MS, TimeUnit.MILLISECONDS)
        }
        mainHandler.post { player?.removeListener(oneShot) }

        // 渲染层在 READY 之前就拿到结果也不会出错：后续 status / position 事件会补上真实时长
        val state = if (ready[0]) playerStateOnMain() else "loading"
        return mapOf(
            "success" to true,
            "data" to mapOf(
                "detail" to mapOf(
                    "quality" to (quality[0] ?: emptyQuality()),
                    "externalLyrics" to sidecarLyrics(source),
                ),
                "mediaInfo" to mediaInfo(meta, duration[0], quality[0]),
                "playback" to mapOf(
                    "position" to positionOnMain(),
                    "state" to state,
                    "speed" to speedOnMain(),
                    "timestamp" to System.currentTimeMillis(),
                ),
            ),
        )
    }

    /** 在调用线程上同步取主线程值（load 期间需要读播放器状态） */
    private fun <T> onMain(block: () -> T, fallback: T): T {
        if (Looper.myLooper() == Looper.getMainLooper()) return block()
        var value: T = fallback
        val latch = CountDownLatch(1)
        val posted = mainHandler.post {
            try {
                value = block()
            } catch (_: Throwable) {
                // 保持 fallback
            } finally {
                latch.countDown()
            }
        }
        if (posted) latch.await(3, TimeUnit.SECONDS)
        return value
    }

    private fun playerStateOnMain(): String = onMain({ playerState() }, "idle")

    private fun positionOnMain(): Long = onMain({ player?.currentPosition ?: 0L }, 0L)

    private fun speedOnMain(): Double =
        onMain({ player?.playbackParameters?.speed?.toDouble() ?: 1.0 }, 1.0)

    private fun emptyQuality(): Map<String, Any?> = mapOf(
        "sampleRate" to 0,
        "channels" to 0,
        "bitsPerSample" to 0,
        "bitRate" to 0,
        "codec" to "",
    )

    private fun currentFormat(p: Player): Format? = runCatching {
        p.currentTracks.groups.firstNotNullOfOrNull { group ->
            if (group.length > 0) group.getTrackFormat(0) else null
        }
    }.getOrNull()

    private fun readQuality(p: Player): Map<String, Any?> {
        val format = currentFormat(p) ?: return emptyQuality()
        return mapOf(
            "sampleRate" to (format.sampleRate.coerceAtLeast(0)),
            "channels" to (format.channelCount.coerceAtLeast(0)),
            "bitsPerSample" to bitsPerSample(format),
            "bitRate" to (format.bitrate.coerceAtLeast(0)),
            "codec" to codecName(format.sampleMimeType.orEmpty()),
        )
    }

    private fun bitsPerSample(format: Format): Int = when (format.pcmEncoding) {
        C.ENCODING_PCM_8BIT -> 8
        C.ENCODING_PCM_16BIT -> 16
        C.ENCODING_PCM_24BIT -> 24
        C.ENCODING_PCM_32BIT, C.ENCODING_PCM_FLOAT -> 32
        else -> 16
    }

    private fun codecName(mime: String): String = when {
        mime.contains("mpeg") -> "MP3"
        mime.contains("flac") -> "FLAC"
        mime.contains("aac") || mime.contains("mp4a") -> "AAC"
        mime.contains("opus") -> "Opus"
        mime.contains("vorbis") -> "Vorbis"
        mime.contains("raw") -> "PCM"
        mime.contains("alac") -> "ALAC"
        mime.contains("wav") -> "PCM"
        mime.isBlank() -> ""
        else -> mime.substringAfter('/').uppercase()
    }

    private fun streamInfo(): Map<String, Any?> {
        val p = player ?: return emptyMap()
        val format = currentFormat(p)
        return mapOf(
            "sampleRate" to (format?.sampleRate ?: 0),
            "channels" to (format?.channelCount ?: 0),
            "bitRate" to (format?.bitrate ?: 0),
            "codec" to codecName(format?.sampleMimeType.orEmpty()),
            "speed" to p.playbackParameters.speed.toDouble(),
            "pitch" to p.playbackParameters.pitch.toDouble(),
        )
    }

    private fun mediaInfo(
        meta: Map<*, *>?,
        durationMs: Long,
        quality: Map<String, Any?>?,
    ): Map<String, Any?> {
        val metadata = onMain({ player?.mediaMetadata }, null as MediaMetadata?)
        val result = linkedMapOf<String, Any?>()
        result["duration"] = maxOf(durationMs, metadata?.durationMs ?: 0L)

        val metaTitle = (meta?.get("title") as? String)?.ifBlank { null }
        val title = metaTitle ?: metadata?.title?.toString()?.ifBlank { null }
        if (title != null) result["title"] = title

        val metaArtists = meta?.get("artists") as? List<*>
        if (!metaArtists.isNullOrEmpty()) {
            result["artists"] = metaArtists
        } else {
            val artist = metadata?.artist?.toString()?.ifBlank { null }
            if (artist != null) result["artists"] = listOf(mapOf("name" to artist))
        }

        val metaAlbum = meta?.get("album") as? Map<*, *>
        if (metaAlbum != null) {
            result["album"] = metaAlbum
        } else {
            val album = metadata?.albumTitle?.toString()?.ifBlank { null }
            if (album != null) result["album"] = mapOf("name" to album)
        }

        result["quality"] = quality ?: emptyQuality()
        return result
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
            .setIsBrowsable(false)
            .setIsPlayable(true)
        (meta["title"] as? String)?.takeIf { it.isNotBlank() }?.let { builder.setTitle(it) }
        artists?.joinToString(" / ")?.takeIf { it.isNotBlank() }?.let { builder.setArtist(it) }
        (meta["album"] as? Map<*, *>)?.get("name")?.toString()?.takeIf { it.isNotBlank() }
            ?.let { builder.setAlbumTitle(it) }
        (meta["album"] as? String)?.takeIf { it.isNotBlank() }?.let { builder.setAlbumTitle(it) }
        if (cover.startsWith("http")) builder.setArtworkUri(Uri.parse(cover))
        return builder.build()
    }

    private fun coverRaw(): String? {
        val data = player?.mediaMetadata?.artworkData ?: return null
        return "data:image/jpeg;base64," +
            android.util.Base64.encodeToString(data, android.util.Base64.NO_WRAP)
    }

    // MARK: - 歌词文件

    private val lyricExtensions = setOf("lrc", "ttml", "lys", "qrc", "krc", "yrc", "ass", "srt")

    /** 本地音频的旁挂歌词（与上游 LYRIC_EXTENSIONS 对齐） */
    private fun sidecarLyrics(source: String): List<Map<String, Any?>> {
        val path = localPath(source) ?: return emptyList()
        val file = File(path)
        val dir = file.parentFile ?: return emptyList()
        val stem = file.nameWithoutExtension
        return listOf("lrc", "ttml", "lys").mapNotNull { ext ->
            val candidate = File(dir, "$stem.$ext")
            if (candidate.isFile) mapOf("format" to ext, "path" to candidate.absolutePath) else null
        }
    }

    private fun readLyricFile(path: String): Any? {
        val real = localPath(path) ?: return mapOf("success" to false, "error" to "仅支持本地歌词文件")
        val file = File(real)
        val ext = file.extension.lowercase()
        if (ext !in lyricExtensions) {
            return mapOf("success" to false, "error" to "不支持的歌词文件类型: $ext")
        }
        val bytes = runCatching { file.readBytes() }.getOrNull()
            ?: return mapOf("success" to false, "error" to "读取失败")
        return mapOf("success" to true, "data" to decodeText(bytes))
    }

    /** 本地路径归一化：file:// → path；网络协议返回 null */
    private fun localPath(source: String): String? = when {
        source.startsWith("content://") -> null
        source.startsWith("file://") -> runCatching { Uri.parse(source).path }.getOrNull()
        source.contains("://") -> null
        source.isBlank() -> null
        else -> source
    }

    private fun decodeText(bytes: ByteArray): String {
        if (bytes.size >= 3 &&
            bytes[0] == 0xEF.toByte() && bytes[1] == 0xBB.toByte() && bytes[2] == 0xBF.toByte()
        ) {
            return String(bytes, 3, bytes.size - 3, Charsets.UTF_8)
        }
        if (bytes.size >= 2 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xFE.toByte()) {
            return String(bytes, 2, bytes.size - 2, Charsets.UTF_16LE)
        }
        if (bytes.size >= 2 && bytes[0] == 0xFE.toByte() && bytes[1] == 0xFF.toByte()) {
            return String(bytes, 2, bytes.size - 2, Charsets.UTF_16BE)
        }
        return try {
            Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(bytes)).toString()
        } catch (_: CharacterCodingException) {
            runCatching { String(bytes, charset("GBK")) }.getOrDefault(String(bytes, Charsets.UTF_8))
        }
    }

    // MARK: - MediaSession 回调（由 PlaybackService 调用）

    /** 系统媒体控件：下一首 / 上一首转发给渲染层 */
    fun onSkipToNext() = pushEvent("next", emptyMap<String, Any>())

    fun onSkipToPrevious() = pushEvent("prev", emptyMap<String, Any>())

    /** 系统媒体控件：seekTo */
    fun onSeekTo(positionMs: Long) {
        mainHandler.post { player?.seekTo(positionMs) }
        pushEvent("seek", mapOf("position" to positionMs))
    }
}
