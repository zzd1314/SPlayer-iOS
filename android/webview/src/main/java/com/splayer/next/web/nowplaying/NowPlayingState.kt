package com.splayer.next.web.nowplaying

import android.content.Context
import com.splayer.next.web.SPlayerBridge
import com.splayer.next.web.api.BridgeUnsupportedException
import com.splayer.next.web.api.ConfigStore

/**
 * 当前播放状态中枢：对应上游 electron/main/services/nowPlaying.ts。
 *
 * 渲染层通过 nowPlaying.update 同步 track / 完整歌词 / 歌词源，
 * 桌面悬浮歌词、灵动岛等原生窗口读取同一份快照，不再依赖 DOM 事件。
 */
object NowPlayingState {

    private const val OFFSETS_KEY = "player.lyricOffsets"
    private const val OFFSET_LIMIT_MS = 60_000L

    private val lock = Any()
    private var store: ConfigStore? = null

    private var track: Map<*, *>? = null
    private var rawLyric: List<*> = emptyList<Any>()
    private var lines: List<LyricLine> = emptyList()
    private var source: Map<*, *>? = null

    private var position = 0L
    private var positionAt = 0L
    private var playing = false
    private var playState = "idle"
    private var speed = 1.0
    private var lyricOffsetMs = 0L
    private var offsetKey = ""

    /** 解析后的歌词行（仅 !isBG），供原生悬浮窗逐字渲染 */
    data class LyricWord(val text: String, val start: Long, val end: Long)

    data class LyricLine(
        val start: Long,
        val end: Long,
        val text: String,
        val words: List<LyricWord>,
        val translation: String,
        val isBG: Boolean,
    )

    fun init(context: Context) {
        if (store == null) store = ConfigStore.shared(context.applicationContext)
    }

    fun handle(method: String, args: List<Any?>): Any? = when (method) {
        "update" -> {
            update(args.getOrNull(0) as? Map<*, *>)
            null
        }

        "requestSnapshot" -> snapshot()

        "setLyricOffset" -> {
            setLyricOffset(
                args.getOrNull(0)?.toString().orEmpty(),
                (args.getOrNull(1) as? Number)?.toLong() ?: 0L,
            )
            null
        }

        else -> throw BridgeUnsupportedException("nowPlaying.$method 暂未在 Android 端实现")
    }

    // MARK: - 渲染层同步

    /** 渲染层同步当前播放状态（track + 歌词 + 歌词源） */
    private fun update(payload: Map<*, *>?) {
        val newTrack = payload?.get("track") as? Map<*, *>
        val newLyric = payload?.get("lyric") as? List<*> ?: emptyList<Any>()
        val newSource = payload?.get("source") as? Map<*, *>

        val trackChanged: Boolean
        synchronized(lock) {
            trackChanged = trackId(track) != trackId(newTrack)
            track = newTrack
            rawLyric = newLyric
            lines = parseLines(newLyric)
            source = newSource
            if (trackChanged) {
                position = 0L
                positionAt = System.currentTimeMillis()
            }
        }

        if (trackChanged) {
            emit("nowPlaying:track-change", mapOf("track" to newTrack))
        }

        val key = trackId(newTrack)?.let { offsetKey(it, newSource) }.orEmpty()
        val needOffset = synchronized(lock) {
            val changed = trackChanged || key != offsetKey
            if (changed) {
                offsetKey = key
                lyricOffsetMs = readOffset(trackId(newTrack), newSource)
            }
            changed
        }
        if (needOffset) {
            emit(
                "nowPlaying:lyric-offset-change",
                mapOf("trackId" to trackId(newTrack), "offsetMs" to lyricOffsetMs),
            )
        }
        emit("nowPlaying:lyric-change", snapshot())
    }

    // MARK: - 播放进度 / 状态

    /** 播放位置锚点（播放中由引擎 5Hz 推送） */
    fun onPosition(positionMs: Long, isPlaying: Boolean) {
        synchronized(lock) {
            position = positionMs
            positionAt = System.currentTimeMillis()
            playing = isPlaying
            if (isPlaying) playState = "playing"
        }
        emitPositionSync()
    }

    /** 播放状态 + 进度 + 倍速统一同步（引擎 status 快照触发） */
    fun syncStatus(state: String, positionMs: Long, speedValue: Double) {
        synchronized(lock) {
            playState = state
            playing = state == "playing"
            position = positionMs
            positionAt = System.currentTimeMillis()
            speed = if (speedValue.isFinite() && speedValue > 0) speedValue else 1.0
        }
        emitPositionSync()
    }

    private fun emitPositionSync() {
        val data = synchronized(lock) {
            mapOf(
                "position" to position,
                "playing" to playing,
                "state" to playState,
                "speed" to speed,
                "sendTimestamp" to (if (positionAt > 0) positionAt else System.currentTimeMillis()),
            )
        }
        emit("nowPlaying:position-sync", data)
    }

    // MARK: - 歌词偏移

    /**
     * 写入指定曲目的歌词偏移；0 视为清除。
     * 偏移按（曲目, 歌词源）分键存储，在线歌词再按平台区分。
     */
    private fun setLyricOffset(id: String, offsetMs: Long) {
        if (id.isBlank()) return
        val value = offsetMs.coerceIn(-OFFSET_LIMIT_MS, OFFSET_LIMIT_MS)
        val cfg = store ?: return
        val key = offsetKey(id, source)
        val map = (cfg.get(OFFSETS_KEY) as? Map<*, *>)?.entries
            ?.associate { it.key.toString() to it.value }?.toMutableMap() ?: mutableMapOf()
        if (value == 0L) map.remove(key) else map[key] = value
        cfg.set(OFFSETS_KEY, map)

        val isCurrent = synchronized(lock) {
            if (trackId(track) == id) {
                lyricOffsetMs = value
                true
            } else {
                false
            }
        }
        if (isCurrent) {
            emit("nowPlaying:lyric-offset-change", mapOf("trackId" to id, "offsetMs" to value))
        }
    }

    private fun readOffset(trackId: String?, src: Map<*, *>?): Long {
        if (trackId == null) return 0L
        val cfg = store ?: return 0L
        val map = cfg.get(OFFSETS_KEY) as? Map<*, *> ?: return 0L
        return (map[offsetKey(trackId, src)] as? Number)?.toLong() ?: 0L
    }

    private fun offsetKey(trackId: String, src: Map<*, *>?): String {
        if (src == null) return trackId
        val type = src["source"]?.toString().orEmpty()
        val platform = src["platform"]?.toString().orEmpty()
        val tag = if (type == "online" && platform.isNotEmpty()) "online:$platform" else type
        return "$trackId|$tag"
    }

    // MARK: - 快照

    fun snapshot(): Map<String, Any?> = synchronized(lock) {
        linkedMapOf(
            "track" to track,
            "lyric" to rawLyric,
            "source" to source,
            "position" to position,
            "playing" to playing,
            "state" to playState,
            "speed" to speed,
            "lyricOffsetMs" to lyricOffsetMs,
            "sendTimestamp" to (positionAt.takeIf { it > 0 } ?: System.currentTimeMillis()),
        )
    }

    // MARK: - 原生窗口读取

    /** 已应用歌词偏移与倍速的当前歌词时间（ms） */
    fun lyricTimeMs(): Long = synchronized(lock) {
        val elapsed = if (playing && positionAt > 0) {
            ((System.currentTimeMillis() - positionAt).coerceAtLeast(0) * speed).toLong()
        } else {
            0L
        }
        position + elapsed + lyricOffsetMs
    }

    fun parsedLines(): List<LyricLine> = synchronized(lock) { lines }

    fun isPlaying(): Boolean = synchronized(lock) { playing }

    fun trackTitle(): String {
        val t = synchronized(lock) { track } ?: return ""
        val title = t["title"]?.toString().orEmpty()
        val artists = (t["artists"] as? List<*>)?.mapNotNull {
            (it as? Map<*, *>)?.get("name")?.toString()
        }.orEmpty()
        return if (artists.isEmpty()) title else "$title - ${artists.joinToString(" / ")}"
    }

    // MARK: - 解析

    private fun parseLines(raw: List<*>): List<LyricLine> {
        val result = ArrayList<LyricLine>(raw.size)
        for (item in raw) {
            val obj = item as? Map<*, *> ?: continue
            if (obj["isBG"] == true) continue
            val words = ArrayList<LyricWord>()
            (obj["words"] as? List<*>)?.forEach { w ->
                val word = w as? Map<*, *> ?: return@forEach
                words.add(
                    LyricWord(
                        text = word["word"]?.toString().orEmpty(),
                        start = (word["startTime"] as? Number)?.toLong() ?: 0L,
                        end = (word["endTime"] as? Number)?.toLong() ?: 0L,
                    )
                )
            }
            val text = words.joinToString("") { it.text }
            result.add(
                LyricLine(
                    start = (obj["startTime"] as? Number)?.toLong() ?: 0L,
                    end = (obj["endTime"] as? Number)?.toLong() ?: 0L,
                    text = text,
                    words = words,
                    translation = obj["translatedLyric"]?.toString().orEmpty(),
                    isBG = false,
                )
            )
        }
        return result
    }

    private fun trackId(t: Map<*, *>?): String? = t?.get("id")?.toString()?.takeIf { it.isNotBlank() }

    // MARK: - 事件

    private fun emit(channel: String, payload: Any?) {
        SPlayerBridge.active?.pushEvent(channel, com.splayer.next.web.Json.write(payload))
    }
}
