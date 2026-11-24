package com.splayer.next.data

import androidx.compose.ui.graphics.Color
import com.splayer.next.ui.theme.BrandAccent
import org.json.JSONArray
import org.json.JSONObject

/**
 * 歌曲模型：字段与桌面端 Track 对齐（标题 / 歌手 / 专辑 / 时长 / 封面 / 播放地址）。
 * tint 仅作为封面加载前的渐变占位色。
 */
data class Song(
    val id: String,
    val title: String,
    val artist: String,
    val album: String = "",
    val durationMs: Long = 0L,
    val coverUrl: String? = null,
    val streamUrl: String = "",
    val tint: Color = BrandAccent,
    /** 网易云 fee 字段：1/4 为 VIP，8 为低音质免费 */
    val fee: Int = 0,
    /** 副标题（别名 / 版本信息） */
    val alias: String? = null
) {
    val durationLabel: String get() = formatDuration(durationMs)
}

/** 歌单 / 专辑 / 排行榜通用封面条目 */
data class Playlist(
    val id: String,
    val title: String,
    val subtitle: String = "",
    val coverUrl: String? = null,
    val tint: Color = BrandAccent,
    val trackCount: Int = 0,
    val playCount: Long = 0L
) {
    val subtitleLabel: String
        get() = subtitle.ifBlank {
            when {
                trackCount > 0 -> "$trackCount 首"
                playCount > 0 -> formatPlayCount(playCount) + "播放"
                else -> "精选推荐"
            }
        }
}

/** 歌手条目 */
data class ArtistItem(
    val id: String,
    val name: String,
    val coverUrl: String? = null,
    val subtitle: String = "",
    val tint: Color = BrandAccent
)

/** 一行歌词（含翻译） */
data class LyricLine(
    val timeMs: Long,
    val text: String,
    val translation: String? = null
) {
    val displayText: String
        get() = if (translation.isNullOrBlank()) text else "$text\n$translation"
}

data class Lyric(
    val lines: List<LyricLine> = emptyList(),
    val hasTranslation: Boolean = false
) {
    val isEmpty: Boolean get() = lines.isEmpty()
}

/** 登录用户资料 */
data class UserProfile(
    val userId: Long = 0L,
    val nickname: String = "",
    val avatarUrl: String? = null,
    val signature: String = ""
)

/** 毫秒转 "m:ss" */
fun formatDuration(ms: Long): String {
    if (ms <= 0L) return "--:--"
    val total = ms / 1000
    return "%d:%02d".format(total / 60, total % 60)
}

/** 播放量简短显示：1.2万 / 3.4亿 */
fun formatPlayCount(count: Long): String = when {
    count >= 100_000_000L -> "%.1f亿".format(count / 100_000_000.0)
    count >= 10_000L -> "%.1f万".format(count / 10_000.0)
    count > 0L -> count.toString()
    else -> ""
}

/** 根据歌曲 id 生成稳定的封面占位色 */
fun tintForId(id: Long): Color {
    val palette = listOf(
        BrandAccent,
        Color(0xFF3D7BFF),
        Color(0xFF24D3C0),
        Color(0xFFFF4FA3),
        Color(0xFF8C7BFF),
        Color(0xFFF5B942)
    )
    val index = ((id % palette.size) + palette.size).toInt() % palette.size
    return palette[index]
}

// MARK: - JSON 持久化（收藏 / 最近播放）

fun songToJson(song: Song): JSONObject = JSONObject().apply {
    put("id", song.id)
    put("title", song.title)
    put("artist", song.artist)
    put("album", song.album)
    put("durationMs", song.durationMs)
    put("coverUrl", song.coverUrl ?: "")
    put("streamUrl", song.streamUrl)
    put("fee", song.fee)
    put("alias", song.alias ?: "")
}

fun songFromJson(json: JSONObject?): Song? {
    if (json == null) return null
    val id = json.optString("id")
    if (id.isBlank()) return null
    val numericId = id.toLongOrNull() ?: 0L
    return Song(
        id = id,
        title = json.optString("title").ifBlank { "未知歌曲" },
        artist = json.optString("artist").ifBlank { "未知艺人" },
        album = json.optString("album"),
        durationMs = json.optLong("durationMs"),
        coverUrl = json.optString("coverUrl").ifBlank { null },
        streamUrl = json.optString("streamUrl"),
        tint = tintForId(numericId),
        fee = json.optInt("fee"),
        alias = json.optString("alias").ifBlank { null }
    )
}

fun songsToJson(songs: List<Song>): String {
    val array = JSONArray()
    songs.forEach { array.put(songToJson(it)) }
    return array.toString()
}

fun songsFromJson(raw: String?): List<Song> {
    if (raw.isNullOrBlank()) return emptyList()
    return runCatching {
        val array = JSONArray(raw)
        (0 until array.length()).mapNotNull { songFromJson(array.optJSONObject(it)) }
    }.getOrDefault(emptyList())
}

// MARK: - 内置示例数据（接口失败时兜底）

object SampleData {

    private const val DEMO_AUDIO = "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-"

    val songs: List<Song> = listOf(
        Song("demo-1", "夜行列车", "陈默", "城市回声", 252_000, null, DEMO_AUDIO + "1.mp3", Color(0xFFFE7971)),
        Song("demo-2", "液态月光", "Luna", "Glass Hours", 228_000, null, DEMO_AUDIO + "2.mp3", Color(0xFF3D7BFF)),
        Song("demo-3", "海边信号", "旧电台", "未送达的信", 301_000, null, DEMO_AUDIO + "3.mp3", Color(0xFF24D3C0)),
        Song("demo-4", "午夜霓虹", "Neon Kid", "Downtown", 202_000, null, DEMO_AUDIO + "4.mp3", Color(0xFFFF4FA3)),
        Song("demo-5", "风经过", "林岸", "四季", 276_000, null, DEMO_AUDIO + "5.mp3", Color(0xFF8C7BFF)),
        Song("demo-6", "沙漏", "白噪实验", "时间碎片", 178_000, null, DEMO_AUDIO + "6.mp3", Color(0xFF6FD08C)),
        Song("demo-7", "漂浮", "Aero", "Low Gravity", 245_000, null, DEMO_AUDIO + "7.mp3", Color(0xFFF5B942)),
        Song("demo-8", "静默频率", "深海电台", "FM 96.7", 371_000, null, DEMO_AUDIO + "8.mp3", Color(0xFF5AC8FA))
    )

    val playlists: List<Playlist> = listOf(
        Playlist("demo-p1", "深夜通勤", "32 首 · 电子", null, Color(0xFF3D7BFF), 32),
        Playlist("demo-p2", "雨夜钢琴", "18 首 · 轻音乐", null, Color(0xFF8C7BFF), 18),
        Playlist("demo-p3", "清晨慢跑", "24 首 · 独立", null, Color(0xFF24D3C0), 24),
        Playlist("demo-p4", "城市民谣", "21 首 · 民谣", null, Color(0xFFFE7971), 21),
        Playlist("demo-p5", "Neon Drive", "27 首 · 合成器", null, Color(0xFFFF4FA3), 27),
        Playlist("demo-p6", "专注工作", "40 首 · Lo-Fi", null, Color(0xFFF5B942), 40)
    )
}
