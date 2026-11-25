package com.splayer.next.web.lyric

import android.annotation.SuppressLint
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import com.splayer.next.web.SPlayerBridge
import com.splayer.next.web.WebHostActivity
import com.splayer.next.web.api.ConfigStore
import com.splayer.next.web.nowplaying.NowPlayingState
import com.splayer.next.web.playback.PlaybackEngine
import kotlin.math.hypot

/**
 * 桌面歌词控制器：对应上游 electron/main/window/desktopLyric.ts 的窗口开关语义。
 * Android 端以系统悬浮窗（SYSTEM_ALERT_WINDOW）承载，未授权时引导用户去设置页开启。
 */
object DesktopLyricController {

    private const val TAG = "DesktopLyric"

    @Volatile
    private var showing = false

    fun isShowing(): Boolean = showing

    /** 切换悬浮歌词；返回切换后的显示状态 */
    fun toggle(context: Context): Boolean {
        val ctx = context.applicationContext
        if (showing) {
            runCatching {
                ctx.startService(
                    Intent(ctx, DesktopLyricService::class.java).setAction(DesktopLyricService.ACTION_HIDE)
                )
            }
            return false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(ctx)) {
            // 交给 Activity 拉起系统授权页，用户授权后再次点击开关即可
            WebHostActivity.requestOverlayPermissionIfNeeded()
            return false
        }
        val started = runCatching {
            ctx.startService(
                Intent(ctx, DesktopLyricService::class.java).setAction(DesktopLyricService.ACTION_SHOW)
            )
        }.onFailure { Log.e(TAG, "startService failed: ${it.message}") }.isSuccess
        return started
    }

    fun close(context: Context) {
        if (!showing) return
        val ctx = context.applicationContext
        runCatching {
            ctx.startService(
                Intent(ctx, DesktopLyricService::class.java).setAction(DesktopLyricService.ACTION_HIDE)
            )
        }
    }

    internal fun onServiceVisibility(visible: Boolean) {
        showing = visible
        SPlayerBridge.active?.pushEvent("desktopLyric:visibilityChange", if (visible) "true" else "false")
    }
}

/**
 * 系统悬浮歌词窗口：
 *  - 逐字高亮（有逐字时间轴时按词推进，否则整行推进）
 *  - 双行显示（当前 + 下一行）、翻译行
 *  - 拖动移动、点击展开播放控制（上一首 / 播放暂停 / 下一首 / 锁定 / 关闭）
 *  - 锁定后点击穿透，右上角保留解锁按钮
 */
class DesktopLyricService : Service() {

    companion object {
        const val ACTION_SHOW = "com.splayer.next.lyric.action.SHOW"
        const val ACTION_HIDE = "com.splayer.next.lyric.action.HIDE"

        private const val TAG = "DesktopLyricService"
        private const val POS_PREFS = "splayer_floating_lyric"
        private const val CONFIG_PREFS = "splayer_config"
        private const val CONFIG_KEY = "config"
    }

    private lateinit var wm: WindowManager
    private lateinit var posPrefs: SharedPreferences
    private lateinit var configPrefs: SharedPreferences
    private val handler = Handler(Looper.getMainLooper())

    private var view: LyricView? = null
    private var lp: WindowManager.LayoutParams? = null
    private var unlockView: View? = null
    private var unlockLp: WindowManager.LayoutParams? = null

    // MARK: - 配置

    private var playedColor = 0xFFFFFFFF.toInt()
    private var unplayedColor = 0xFF7D7D7D.toInt()
    private var strokeColor = 0x80000000.toInt()
    private var maskColor = 0x4D000000
    private var maskEnabled = false
    private var fontSizeDp = 24f
    private var fontWeight = 600
    private var doubleLine = true
    private var wordByWord = true
    private var showTranslation = true
    private var align = "center"
    private var locked = false

    private val configListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == CONFIG_KEY) handler.post { readConfig(); applyConfig() }
    }

    // MARK: - 生命周期

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        posPrefs = getSharedPreferences(POS_PREFS, MODE_PRIVATE)
        configPrefs = getSharedPreferences(CONFIG_PREFS, MODE_PRIVATE)
        readConfig()
        buildView()
        applyLocked(locked)
        configPrefs.registerOnSharedPreferenceChangeListener(configListener)
        DesktopLyricController.onServiceVisibility(true)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_HIDE) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (view == null) buildView()
        return START_STICKY
    }

    override fun onDestroy() {
        runCatching { configPrefs.unregisterOnSharedPreferenceChangeListener(configListener) }
        handler.removeCallbacksAndMessages(null)
        removeUnlockButton()
        view?.let { runCatching { wm.removeView(it) } }
        view = null
        DesktopLyricController.onServiceVisibility(false)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // MARK: - 窗口

    @SuppressLint("NewApi")
    private fun buildView() {
        if (view != null) return
        val dm = resources.displayMetrics
        val d = dm.density
        val w = (dm.widthPixels * 0.94f).toInt()
        val rows = 1f + (if (showTranslation) 0.55f else 0f) + (if (doubleLine) 1f else 0f)
        val h = (fontSizeDp * d * 1.45f * rows + 22 * d)
            .toInt().coerceIn((56 * d).toInt(), (dm.heightPixels * 0.4f).toInt())

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            w,
            h,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        )
        params.gravity = Gravity.TOP or Gravity.START
        params.x = posPrefs.getInt("x", (dm.widthPixels - w) / 2)
        params.y = posPrefs.getInt("y", (dm.heightPixels * 0.72f).toInt())

        val lyricView = LyricView(this)
        lp = params
        view = lyricView
        runCatching { wm.addView(lyricView, params) }
            .onFailure { Log.e(TAG, "addView failed: ${it.message}") }
    }

    private fun applyConfig() {
        val v = view ?: return
        val dm = resources.displayMetrics
        val d = dm.density
        val w = (dm.widthPixels * 0.94f).toInt()
        val rows = 1f + (if (showTranslation) 0.55f else 0f) + (if (doubleLine) 1f else 0f)
        val h = (fontSizeDp * d * 1.45f * rows + 22 * d)
            .toInt().coerceIn((56 * d).toInt(), (dm.heightPixels * 0.4f).toInt())
        lp?.let {
            it.width = w
            it.height = h
            runCatching { wm.updateViewLayout(v, it) }
        }
        applyLocked(locked)
        v.invalidate()
    }

    // MARK: - 配置读取

    private fun readConfig() {
        val cfg = ConfigStore.shared(this).get("desktopLyric") as? Map<*, *> ?: return
        playedColor = parseColor(cfg["playedColor"], playedColor)
        unplayedColor = parseColor(cfg["unplayedColor"], unplayedColor)
        strokeColor = parseColor(cfg["strokeColor"], strokeColor)
        maskColor = parseColor(cfg["backgroundMaskColor"], maskColor)
        maskEnabled = cfg["backgroundMask"] as? Boolean ?: maskEnabled
        wordByWord = cfg["wordByWord"] as? Boolean ?: wordByWord
        showTranslation = cfg["showTranslation"] as? Boolean ?: showTranslation
        doubleLine = cfg["doubleLine"] as? Boolean ?: doubleLine
        locked = cfg["locked"] as? Boolean ?: locked
        (cfg["fontSize"] as? Number)?.let { fontSizeDp = it.toFloat().coerceIn(12f, 48f) }
        (cfg["fontWeight"] as? Number)?.let { fontWeight = it.toInt() }
        (cfg["align"] as? String)?.takeIf { it.isNotBlank() }?.let { align = it }
    }

    private fun writeConfig(key: String, value: Any?) {
        ConfigStore.shared(this).set("desktopLyric.$key", value)
        val all = ConfigStore.shared(this).get("desktopLyric")
        SPlayerBridge.active?.pushEvent(
            "desktopLyric:configChange",
            com.splayer.next.web.Json.write(all),
        )
    }

    private fun parseColor(raw: Any?, fallback: Int): Int {
        val text = (raw as? String)?.trim().orEmpty()
        if (text.isEmpty()) return fallback
        return runCatching {
            if (text.startsWith("#")) {
                Color.parseColor(text)
            } else if (text.startsWith("rgb")) {
                val parts = text.substringAfter('(').substringBefore(')')
                    .split(',').map { it.trim() }
                if (parts.size < 3) return fallback
                val r = parts[0].toDouble().toInt().coerceIn(0, 255)
                val g = parts[1].toDouble().toInt().coerceIn(0, 255)
                val b = parts[2].toDouble().toInt().coerceIn(0, 255)
                val a = if (parts.size >= 4) {
                    val af = parts[3].toDouble()
                    if (af <= 1.0) (af * 255).toInt().coerceIn(0, 255) else af.toInt().coerceIn(0, 255)
                } else {
                    255
                }
                Color.argb(a, r, g, b)
            } else {
                fallback
            }
        }.getOrDefault(fallback)
    }

    // MARK: - 锁定 / 解锁

    private fun applyLocked(value: Boolean) {
        locked = value
        val v = view ?: return
        val p = lp ?: return
        if (value) {
            p.flags = p.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
            runCatching { wm.updateViewLayout(v, p) }
            showUnlockButton()
        } else {
            p.flags = p.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
            runCatching { wm.updateViewLayout(v, p) }
            removeUnlockButton()
        }
        v.invalidate()
    }

    private fun setLocked(value: Boolean) {
        writeConfig("locked", value)
        applyLocked(value)
    }

    private fun showUnlockButton() {
        if (unlockView != null) return
        val p = lp ?: return
        val d = resources.displayMetrics.density
        val size = (34 * d).toInt()
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            size,
            size,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        )
        params.gravity = Gravity.TOP or Gravity.START
        params.x = p.x + p.width - size - (4 * d).toInt()
        params.y = p.y + (4 * d).toInt()

        val btn = UnlockButtonView(this)
        btn.setOnClickListener { setLocked(false) }
        unlockLp = params
        unlockView = btn
        runCatching { wm.addView(btn, params) }
            .onFailure { Log.e(TAG, "add unlock failed: ${it.message}") }
    }

    private fun removeUnlockButton() {
        unlockView?.let { runCatching { wm.removeView(it) } }
        unlockView = null
        unlockLp = null
    }

    // MARK: - 解锁按钮

    private inner class UnlockButtonView(context: Context) : View(context) {
        private val bg = Paint(Paint.ANTI_ALIAS_FLAG)
        private val icon = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }

        override fun onDraw(canvas: Canvas) {
            val d = resources.displayMetrics.density
            bg.color = maskColor
            if ((bg.color ushr 24) != 0) {
                canvas.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), 10 * d, 10 * d, bg)
            }
            icon.color = 0xFFFFFFFF.toInt()
            icon.textSize = 16 * d
            val fm = icon.fontMetrics
            canvas.drawText(
                "🔓",
                width / 2f,
                height / 2f - (fm.ascent + fm.descent) / 2f,
                icon,
            )
        }
    }

    // MARK: - 歌词视图

    private inner class LyricView(context: Context) : View(context) {

        private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG)
        private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val glyphPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }

        private val rPrev = RectF()
        private val rPlay = RectF()
        private val rNext = RectF()
        private val rLock = RectF()
        private val rClose = RectF()

        private var showControls = false
        private var dragging = false
        private var downX = 0f
        private var downY = 0f
        private var startX = 0
        private var startY = 0

        private val hideControls = Runnable {
            showControls = false
            invalidate()
        }

        private val density: Float get() = resources.displayMetrics.density

        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (locked) return false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = lp?.x ?: 0
                    startY = lp?.y ?: 0
                    dragging = false
                    return true
                }

                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (!dragging && hypot(dx, dy) > 6 * density) dragging = true
                    if (dragging) {
                        lp?.let {
                            it.x = startX + dx.toInt()
                            it.y = startY + dy.toInt()
                            runCatching { wm.updateViewLayout(this, it) }
                        }
                    }
                    return true
                }

                MotionEvent.ACTION_UP -> {
                    if (dragging) {
                        lp?.let {
                            posPrefs.edit().putInt("x", it.x).putInt("y", it.y).apply()
                        }
                    } else if (showControls) {
                        handleButtonTap(event.x, event.y)
                        showControls = false
                        handler.removeCallbacks(hideControls)
                        invalidate()
                    } else {
                        showControls = true
                        invalidate()
                        handler.removeCallbacks(hideControls)
                        handler.postDelayed(hideControls, 5000)
                    }
                    return true
                }
            }
            return super.onTouchEvent(event)
        }

        private fun handleButtonTap(x: Float, y: Float) {
            when {
                rPrev.contains(x, y) -> PlaybackEngine.onSkipToPrevious()
                rPlay.contains(x, y) -> {
                    if (NowPlayingState.isPlaying()) {
                        PlaybackEngine.handle("pause", emptyList())
                    } else {
                        PlaybackEngine.handle("play", emptyList())
                    }
                }

                rNext.contains(x, y) -> PlaybackEngine.onSkipToNext()
                rLock.contains(x, y) -> setLocked(true)
                rClose.contains(x, y) -> {
                    DesktopLyricController.close(this@DesktopLyricService)
                    stopSelf()
                }
            }
        }

        override fun onDraw(canvas: Canvas) {
            val w = width.toFloat()
            val h = height.toFloat()
            if (showControls) {
                drawControls(canvas, w, h)
            } else {
                if (maskEnabled) {
                    bgPaint.color = maskColor
                    if ((bgPaint.color ushr 24) != 0) {
                        canvas.drawRoundRect(0f, 0f, w, h, 14 * density, 14 * density, bgPaint)
                    }
                }
                drawLyrics(canvas, w, h)
            }
            if (NowPlayingState.isPlaying()) postInvalidateOnAnimation()
        }

        // ---------- 控制栏 ----------

        private fun drawControls(canvas: Canvas, w: Float, h: Float) {
            val d = density
            bgPaint.color = 0xE61E1E2E.toInt()
            canvas.drawRoundRect(0f, 0f, w, h, 14 * d, 14 * d, bgPaint)

            val slot = w / 5f
            val top = h * 0.24f
            rPrev.set(0f, top, slot, h)
            rPlay.set(slot, top, slot * 2, h)
            rNext.set(slot * 2, top, slot * 3, h)
            rLock.set(slot * 3, top, slot * 4, h)
            rClose.set(slot * 4, top, w, h)

            glyphPaint.textSize = h * 0.34f
            glyphPaint.color = 0xFFFFFFFF.toInt()
            val fm = glyphPaint.fontMetrics
            val baseY = (top + h) / 2f - (fm.ascent + fm.descent) / 2f
            val playGlyph = if (NowPlayingState.isPlaying()) "⏸" else "▶"
            val glyphs = listOf("⏮", playGlyph, "⏭", "🔒", "✕")
            for (i in 0 until 5) {
                canvas.drawText(glyphs[i], slot * i + slot / 2f, baseY, glyphPaint)
            }
        }

        // ---------- 歌词 ----------

        private fun drawLyrics(canvas: Canvas, w: Float, h: Float) {
            val d = density
            val textSize = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, fontSizeDp, resources.displayMetrics
            )
            val padX = 18 * d
            val lines = NowPlayingState.parsedLines()
            val now = NowPlayingState.lyricTimeMs()
            val index = lineIndex(lines, now)

            if (lines.isEmpty() || index < 0) {
                drawSongInfo(canvas, w, h, textSize)
                return
            }

            val current = lines[index]
            val next = if (doubleLine) lines.getOrNull(index + 1) else null

            val translation = if (showTranslation) current.translation else ""
            val trSize = textSize * 0.62f

            var total = textSize * 1.4f
            if (translation.isNotBlank()) total += trSize * 1.5f
            if (next != null) total += textSize * 0.95f

            var baseline = (h - total) / 2f + textSize * 0.95f
            drawLine(canvas, current, now, padX, baseline, textSize, playedColor, unplayedColor, wordByWord)

            if (translation.isNotBlank()) {
                baseline += trSize * 1.5f
                textPaint.textSize = trSize
                textPaint.typeface = Typeface.DEFAULT
                textPaint.setShadowLayer(2 * d, 0f, 0f, strokeColor)
                textPaint.color = alpha(unplayedColor, 0xCC)
                drawAligned(canvas, translation, w, baseline, padX)
            }

            if (next != null) {
                baseline += textSize * 1.05f
                drawLine(
                    canvas, next, now, padX, baseline, textSize * 0.86f,
                    alpha(unplayedColor, 0xCC), alpha(unplayedColor, 0x99), false,
                )
            }
        }

        private fun drawSongInfo(canvas: Canvas, w: Float, h: Float, textSize: Float) {
            val title = NowPlayingState.trackTitle().ifBlank { "SPlayer" }
            textPaint.textSize = textSize * 0.82f
            textPaint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
            textPaint.setShadowLayer(2 * density, 0f, 0f, strokeColor)
            textPaint.color = 0xBBFFFFFF.toInt()
            drawAligned(canvas, title, w, h * 0.5f + textSize * 0.3f, 18 * density)
        }

        private fun drawLine(
            canvas: Canvas,
            line: NowPlayingState.LyricLine,
            now: Long,
            padX: Float,
            baseline: Float,
            size: Float,
            played: Int,
            unplayed: Int,
            perWord: Boolean,
        ) {
            val text = line.text
            if (text.isEmpty()) return
            val d = density
            textPaint.textSize = size
            textPaint.typeface = Typeface.create(
                Typeface.DEFAULT,
                if (fontWeight >= 600) Typeface.BOLD else Typeface.NORMAL,
            )
            textPaint.setShadowLayer(2 * d, 0f, 0f, strokeColor)

            val available = width - padX * 2
            val measured = textPaint.measureText(text)
            var x = padX
            if (measured <= available) {
                x = when (align) {
                    "left" -> padX
                    "right" -> width - padX - measured
                    else -> (width - measured) / 2f
                }
            } else {
                // 溢出：按行进度横向滚动展示
                val progress = lineProgress(line, now)
                x = padX - (measured - available) * progress
            }

            textPaint.color = unplayed
            canvas.drawText(text, x, baseline, textPaint)

            val top = baseline - size * 1.3f
            val bottom = baseline + size * 0.35f
            if (perWord && line.words.size > 1) {
                var cursor = x
                for (word in line.words) {
                    val wordWidth = textPaint.measureText(word.text)
                    val progress = wordProgress(word, line, now)
                    if (progress > 0f && wordWidth > 0f) {
                        canvas.save()
                        canvas.clipRect(cursor, top, cursor + wordWidth * progress, bottom)
                        textPaint.color = played
                        canvas.drawText(text, x, baseline, textPaint)
                        canvas.restore()
                    }
                    cursor += wordWidth
                }
            } else {
                val progress = lineProgress(line, now)
                if (progress > 0f && measured > 0f) {
                    canvas.save()
                    canvas.clipRect(x, top, x + measured * progress, bottom)
                    textPaint.color = played
                    canvas.drawText(text, x, baseline, textPaint)
                    canvas.restore()
                }
            }
        }

        private fun drawAligned(canvas: Canvas, text: String, w: Float, baseline: Float, padX: Float) {
            val measured = textPaint.measureText(text)
            val x = when (align) {
                "left" -> padX
                "right" -> w - padX - measured
                else -> (w - measured) / 2f
            }
            canvas.drawText(text, maxOf(x, padX - 4 * density), baseline, textPaint)
        }

        private fun lineIndex(lines: List<NowPlayingState.LyricLine>, now: Long): Int {
            var result = -1
            for (i in lines.indices) {
                if (now >= lines[i].start) result = i else break
            }
            return result
        }

        private fun lineProgress(line: NowPlayingState.LyricLine, now: Long): Float {
            if (line.end <= line.start) return if (now >= line.start) 1f else 0f
            if (now <= line.start) return 0f
            if (now >= line.end) return 1f
            return (now - line.start).toFloat() / (line.end - line.start)
        }

        private fun wordProgress(
            word: NowPlayingState.LyricWord,
            line: NowPlayingState.LyricLine,
            now: Long,
        ): Float {
            if (word.end <= word.start) return lineProgress(line, now)
            if (now <= word.start) return 0f
            if (now >= word.end) return 1f
            return (now - word.start).toFloat() / (word.end - word.start)
        }

        private fun alpha(color: Int, value: Int): Int = (color and 0x00FFFFFF) or (value shl 24)
    }
}
