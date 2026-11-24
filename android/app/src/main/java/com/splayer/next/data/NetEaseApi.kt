package com.splayer.next.data

import androidx.compose.ui.graphics.Color
import com.splayer.next.ui.theme.Accent
import com.splayer.next.ui.theme.AccentBlue
import com.splayer.next.ui.theme.AccentPink
import com.splayer.next.ui.theme.AccentTeal
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * 网易云音乐匿名 Web 接口的最小封装。
 * 仅使用 HttpURLConnection + org.json，避免引入额外的网络/序列化依赖。
 */
object NetEaseApi {

    private const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36"
    private const val REFERER = "https://music.163.com/"

    private val tints = listOf(Accent, AccentBlue, AccentTeal, AccentPink)

    suspend fun search(keyword: String): List<Song> = withContext(Dispatchers.IO) {
        val encoded = URLEncoder.encode(keyword, "UTF-8")
        val body = get(
            "https://music.163.com/api/search/get/web" +
                "?csrf_token=&s=$encoded&type=1&offset=0&total=true&limit=30"
        )
        val songs = JSONObject(body)
            .optJSONObject("result")
            ?.optJSONArray("songs")
            ?: return@withContext emptyList()
        (0 until songs.length()).mapNotNull { index -> songFrom(songs.optJSONObject(index)) }
    }

    suspend fun newSongs(): List<Song> = withContext(Dispatchers.IO) {
        val body = get("https://music.163.com/api/personalized/newsong?limit=20")
        val result = JSONObject(body).optJSONArray("result") ?: return@withContext emptyList()
        (0 until result.length()).mapNotNull { index ->
            val item = result.optJSONObject(index) ?: return@mapNotNull null
            songFrom(item.optJSONObject("song") ?: item)
        }
    }

    suspend fun recommendedPlaylists(): List<Playlist> = withContext(Dispatchers.IO) {
        val body = get("https://music.163.com/api/personalized/playlist?limit=6&total=true&n=1000")
        val result = JSONObject(body).optJSONArray("result") ?: return@withContext emptyList()
        (0 until result.length()).mapNotNull { index ->
            val item = result.optJSONObject(index) ?: return@mapNotNull null
            val id = item.optLong("id")
            if (id <= 0L) return@mapNotNull null
            val name = item.optString("name").ifBlank { "精选歌单" }
            Playlist(
                id = id.toString(),
                title = name,
                subtitle = playCountLabel(item.optLong("playCount")),
                tint = tintFor(id)
            )
        }
    }

    /** 匿名可用的歌曲外链，播放时会 302 到 CDN（可能为 http，需要允许跨协议重定向） */
    fun streamUrl(id: Long): String = "https://music.163.com/song/media/outer/url?id=$id.mp3"

    private fun songFrom(json: JSONObject?): Song? {
        if (json == null) return null
        val id = json.optLong("id")
        if (id <= 0L) return null
        val artists = json.optJSONArray("artists")
        val artist = artists?.optJSONObject(0)?.optString("name").orEmpty().ifBlank { "未知艺人" }
        val album = json.optJSONObject("album")?.optString("name").orEmpty().ifBlank { "未知专辑" }
        return Song(
            id = id.toString(),
            title = json.optString("name").ifBlank { "未知歌曲" },
            artist = artist,
            album = album,
            duration = formatDuration(json.optLong("duration")),
            tint = tintFor(id),
            url = streamUrl(id)
        )
    }

    private fun get(url: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 8000
        connection.readTimeout = 8000
        connection.requestMethod = "GET"
        connection.setRequestProperty("User-Agent", USER_AGENT)
        connection.setRequestProperty("Referer", REFERER)
        connection.setRequestProperty("Accept", "application/json")
        try {
            val code = connection.responseCode
            if (code !in 200..299) throw IOException("HTTP $code")
            return connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    private fun tintFor(id: Long): Color = tints[(id % tints.size).toInt()]

    private fun formatDuration(durationMs: Long): String {
        if (durationMs <= 0L) return "--:--"
        val totalSeconds = durationMs / 1000
        return "%02d:%02d".format(totalSeconds / 60, totalSeconds % 60)
    }

    private fun playCountLabel(playCount: Long): String = when {
        playCount >= 10000L -> "${playCount / 10000}万播放"
        playCount > 0L -> "$playCount 播放"
        else -> "精选推荐"
    }
}