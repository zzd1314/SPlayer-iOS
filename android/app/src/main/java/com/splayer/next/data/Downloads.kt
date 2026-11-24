package com.splayer.next.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * 离线下载：把歌曲音频保存到应用私有目录，并持久化曲目信息。
 * 下载完成的歌曲在播放时优先使用本地文件，实现断网播放。
 */
object DownloadStore {

    private const val PREFS_NAME = "splayer_next_downloads"
    private const val KEY_SONGS = "downloaded_songs"
    private const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36"

    var songs by mutableStateOf<List<Song>>(emptyList())
        private set

    /** songId -> 0f..1f 下载进度 */
    val progress = mutableStateMapOf<String, Float>()

    private var prefs: SharedPreferences? = null
    private var dir: File? = null

    fun init(context: Context) {
        if (prefs != null) return
        val app = context.applicationContext
        prefs = app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        dir = File(app.filesDir, "downloads").apply { mkdirs() }
        val stored = songsFromJson(prefs?.getString(KEY_SONGS, null))
        // 过滤已被系统清理的文件，保证列表与实际文件一致
        songs = stored.filter { fileFor(it.id)?.let { file -> file.exists() && file.length() > 0L } == true }
        persist()
    }

    fun isDownloaded(songId: String): Boolean = songs.any { it.id == songId }

    /** 本地音频文件路径（存在且非空才返回） */
    fun localPath(songId: String): String? {
        val file = fileFor(songId) ?: return null
        return if (file.exists() && file.length() > 0L) file.absolutePath else null
    }

    fun delete(songId: String) {
        fileFor(songId)?.delete()
        songs = songs.filterNot { it.id == songId }
        progress.remove(songId)
        persist()
    }

    suspend fun download(context: Context, song: Song): Boolean = withContext(Dispatchers.IO) {
        init(context)
        if (isDownloaded(song.id)) return@withContext true
        val target = fileFor(song.id) ?: return@withContext false
        val sourceUrl = song.streamUrl.ifBlank {
            if (song.id.toLongOrNull() != null) NetEaseApi.streamUrl(song.id) else ""
        }
        if (sourceUrl.isBlank()) return@withContext false

        val temp = File(target.absolutePath + ".part")
        progress[song.id] = 0f
        val success = runCatching { fetchToFile(sourceUrl, temp, song.id) }.isSuccess

        if (success && temp.length() > 0L) {
            if (target.exists()) target.delete()
            if (temp.renameTo(target)) {
                songs = listOf(song.copy(streamUrl = "file://" + target.absolutePath)) +
                    songs.filterNot { it.id == song.id }
                persist()
                progress.remove(song.id)
                true
            } else {
                temp.delete()
                progress.remove(song.id)
                false
            }
        } else {
            temp.delete()
            progress.remove(song.id)
            false
        }
    }

    private fun fetchToFile(sourceUrl: String, temp: File, songId: String) {
        var url = sourceUrl
        var connection: HttpURLConnection
        var redirects = 0

        // 手动跟随重定向：网易云外链可能跨 http/https，默认实现不会自动跳转
        while (true) {
            connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.instanceFollowRedirects = false
            connection.setRequestProperty("User-Agent", USER_AGENT)
            connection.setRequestProperty("Referer", "https://music.163.com/")
            val code = connection.responseCode
            if (code in 300..399) {
                val location = connection.getHeaderField("Location")
                connection.disconnect()
                if (location.isNullOrBlank() || redirects++ >= 5) {
                    throw IOException("重定向失败")
                }
                url = when {
                    location.startsWith("http://") || location.startsWith("https://") -> location
                    location.startsWith("/") -> "https://music.163.com$location"
                    else -> location
                }
                continue
            }
            if (code !in 200..299) {
                connection.disconnect()
                throw IOException("HTTP $code")
            }
            break
        }

        try {
            val total = connection.contentLengthLong
            connection.inputStream.use { input ->
                temp.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var written = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read <= 0) break
                        output.write(buffer, 0, read)
                        written += read
                        if (total > 0L) {
                            progress[songId] = (written.toFloat() / total).coerceIn(0f, 1f)
                        }
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun fileFor(songId: String): File? {
        val folder = dir ?: return null
        val name = songId.filter { it.isLetterOrDigit() || it == '-' || it == '_' }
        if (name.isBlank()) return null
        return File(folder, "$name.mp3")
    }

    private fun persist() {
        prefs?.edit()?.putString(KEY_SONGS, songsToJson(songs))?.apply()
    }
}