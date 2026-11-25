package com.splayer.next.web.api

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/**
 * 缓存管理：实现 preload cache.* 契约。
 *
 * 文件类缓存落在应用私有缓存目录（Android 无桌面版「可任选目录」语义）：
 *  - song：播放器级单曲缓存（audioSource 命中查询 / 预载写入）
 *  - covers / artists / backgrounds / motionCovers：预留目录统计与清理
 * DB 类缓存（歌词等）在 Android 端走内存/文件，统计恒为 0。
 */
object CacheManager {

    private const val TAG = "CacheManager"
    private const val DEFAULT_LIMIT_GB = 10
    private const val EVICT_BATCH = 8

    private lateinit var appContext: Context

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    fun handle(method: String, args: List<Any?>): Any? = when (method) {
        "song:lookup" -> songLookup(args.getOrNull(0)?.toString().orEmpty())
        "song:fetch" -> songFetch(
            args.getOrNull(0)?.toString().orEmpty(),
            args.getOrNull(2)?.toString().orEmpty(),
        )
        "song:cancel" -> {
            songCancel(args.getOrNull(0)?.toString().orEmpty())
            null
        }
        "getStats" -> stats()
        "clear" -> {
            clear(args.getOrNull(0)?.toString().orEmpty())
            null
        }
        "clearAllByKind" -> {
            clearAllByKind(args.getOrNull(0)?.toString().orEmpty())
            null
        }
        "getDir" -> cacheRoot().absolutePath
        "pickDir" -> mapOf(
            "ok" to false,
            "dir" to cacheRoot().absolutePath,
            "reason" to "unsupported",
        )
        "resetDir" -> cacheRoot().absolutePath
        else -> throw BridgeUnsupportedException("cache.$method 暂未在 Android 端实现")
    }

    // MARK: - 目录

    private fun cacheRoot(): File = File(appContext.cacheDir, "splayer-cache").apply { mkdirs() }

    private fun songDir(): File = File(cacheRoot(), "songs").apply { mkdirs() }

    private fun categoryDir(id: String): File? = when (id) {
        "covers" -> File(cacheRoot(), "covers")
        "artists" -> File(cacheRoot(), "artists")
        "backgrounds" -> File(cacheRoot(), "backgrounds")
        "motionCovers" -> File(cacheRoot(), "motion_covers")
        "songs" -> songDir()
        else -> null
    }

    private val fileCategories = listOf("covers", "artists", "backgrounds", "songs", "motionCovers")
    private val dbCategories = listOf("lyric", "lyricTTML", "lyricMatch")

    // MARK: - 统计 / 清理

    private fun stats(): List<Map<String, Any?>> {
        val result = ArrayList<Map<String, Any?>>()
        for (id in fileCategories) {
            val dir = categoryDir(id) ?: continue
            result.add(
                linkedMapOf(
                    "id" to id,
                    "kind" to "file",
                    "path" to dir.absolutePath,
                    "size" to dirSize(dir),
                )
            )
        }
        for (id in dbCategories) {
            val label = when (id) {
                "lyric" -> "lyric_cache"
                "lyricTTML" -> "lyric_ttml_cache"
                else -> "lyric_match_cache"
            }
            result.add(linkedMapOf("id" to id, "kind" to "db", "path" to label, "size" to 0L))
        }
        return result
    }

    private fun clear(id: String) {
        if (id == "songs") {
            activeDownloads.values.forEach { it.canceled = true }
            disconnectAll()
        }
        categoryDir(id)?.let { clearDir(it) }
    }

    private fun clearAllByKind(kind: String) {
        if (kind != "file") return
        fileCategories.forEach { clear(it) }
    }

    private fun clearDir(dir: File) {
        if (!dir.exists()) return
        dir.listFiles()?.forEach { runCatching { it.deleteRecursively() } }
    }

    private fun dirSize(dir: File): Long {
        if (!dir.exists()) return 0L
        return dir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }

    private fun disconnectAll() {
        activeDownloads.values.forEach { runCatching { it.conn?.disconnect() } }
    }

    // MARK: - 单曲缓存

    private class ActiveDownload {
        @Volatile
        var canceled = false

        @Volatile
        var conn: HttpURLConnection? = null
    }

    private val activeDownloads = ConcurrentHashMap<String, ActiveDownload>()

    private fun keyPrefix(cacheKey: String): String {
        val md = MessageDigest.getInstance("SHA-1")
        val digest = md.digest(cacheKey.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }.take(16)
    }

    private fun songLookup(cacheKey: String): String? {
        if (cacheKey.isBlank()) return null
        val prefix = keyPrefix(cacheKey)
        val file = songDir().listFiles()?.firstOrNull {
            it.isFile && it.name.startsWith(prefix) && !it.name.endsWith(".part")
        }
        return file?.absolutePath
    }

    /** 与主进程 songCache 对齐：先查命中，未命中则同步下载到 .part 再改名 */
    private fun songFetch(cacheKey: String, streamUrl: String): String? {
        if (cacheKey.isBlank() || streamUrl.isBlank()) return null
        songLookup(cacheKey)?.let { return it }
        // 同键并发：等待已在进行中的下载完成
        if (activeDownloads.containsKey(cacheKey)) {
            repeat(600) {
                Thread.sleep(200)
                songLookup(cacheKey)?.let { return it }
            }
            return null
        }
        val job = ActiveDownload()
        if (activeDownloads.putIfAbsent(cacheKey, job) != null) return null
        return try {
            download(cacheKey, streamUrl, job)
        } catch (e: Exception) {
            android.util.Log.w(TAG, "song cache fetch failed: ${e.message}")
            null
        } finally {
            activeDownloads.remove(cacheKey)
            job.conn = null
        }
    }

    private fun download(cacheKey: String, streamUrl: String, job: ActiveDownload): String? {
        val dir = songDir()
        val prefix = keyPrefix(cacheKey)
        val conn = (URL(streamUrl).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "SPlayer/Android")
        }
        job.conn = conn
        val code = conn.responseCode
        if (code !in 200..299) throw RuntimeException("HTTP $code")
        val mime = conn.contentType
        if (isRejectedMime(mime)) throw RuntimeException("REJECTED_MIME $mime")

        val ext = resolveExt(mime, streamUrl)
        val part = File(dir, "$prefix.part")
        val finalFile = File(dir, "$prefix$ext")
        var received = 0L

        conn.inputStream.use { input ->
            FileOutputStream(part).use { out ->
                val buf = ByteArray(32 * 1024)
                while (true) {
                    if (job.canceled) throw RuntimeException("canceled")
                    val n = input.read(buf)
                    if (n < 0) break
                    out.write(buf, 0, n)
                    received += n
                }
            }
        }
        conn.disconnect()
        if (received == 0L) {
            part.delete()
            return null
        }
        if (!looksLikeAudio(part)) {
            part.delete()
            return null
        }
        if (finalFile.exists()) finalFile.delete()
        if (!part.renameTo(finalFile)) {
            part.copyTo(finalFile, overwrite = true)
            part.delete()
        }
        evictIfNeeded()
        return finalFile.absolutePath
    }

    private fun songCancel(cacheKey: String) {
        activeDownloads[cacheKey]?.let {
            it.canceled = true
            runCatching { it.conn?.disconnect() }
        }
    }

    // MARK: - 校验 / 淘汰

    private fun isRejectedMime(mime: String?): Boolean {
        if (mime.isNullOrEmpty()) return false
        val lower = mime.lowercase()
        return lower.startsWith("text/") ||
            lower.contains("json") ||
            lower.contains("xml") ||
            lower.contains("html")
    }

    /** 部分直链返回 200 + HTML 错误页，按文本首字节拒收 */
    private fun looksLikeAudio(file: File): Boolean {
        return runCatching {
            file.inputStream().use { stream ->
                val head = ByteArray(4)
                val read = stream.read(head)
                if (read <= 0) return false
                val first = head[0].toInt().toChar()
                first != '<' && first != '{' && first != '['
            }
        }.getOrDefault(false)
    }

    private fun resolveExt(mime: String?, url: String): String {
        val byMime = mapOf(
            "audio/flac" to ".flac",
            "audio/x-flac" to ".flac",
            "audio/mpeg" to ".mp3",
            "audio/mp3" to ".mp3",
            "audio/mp4" to ".m4a",
            "audio/x-m4a" to ".m4a",
            "audio/aac" to ".aac",
            "audio/ogg" to ".ogg",
            "audio/opus" to ".opus",
            "audio/wav" to ".wav",
            "audio/x-wav" to ".wav",
        )
        mime?.substringBefore(';')?.trim()?.lowercase()?.let { m ->
            byMime[m]?.let { return it }
        }
        val tail = url.substringBefore('?').substringAfterLast('/')
        val ext = tail.substringAfterLast('.', "").lowercase()
        return if (ext in setOf("flac", "mp3", "m4a", "aac", "ogg", "opus", "wav", "ape", "wv")) {
            ".$ext"
        } else {
            ".mp3"
        }
    }

    private fun sizeLimitBytes(): Long {
        val gb = (ConfigStore.shared(appContext).get("cache.songCache.sizeLimitGb") as? Number)
            ?.toDouble() ?: DEFAULT_LIMIT_GB.toDouble()
        return (gb.coerceAtLeast(0.5) * 1024 * 1024 * 1024).toLong()
    }

    /** 超限按 LRU（lastModified）分批淘汰 */
    private fun evictIfNeeded() {
        val dir = songDir()
        val limit = sizeLimitBytes()
        val files = dir.listFiles()?.filter { it.isFile && !it.name.endsWith(".part") } ?: return
        var total = files.sumOf { it.length() }
        if (total <= limit) return
        val victims = files.sortedBy { it.lastModified() }
        for (victim in victims) {
            if (total <= limit) break
            val size = victim.length()
            if (victim.delete()) total -= size
        }
    }
}
