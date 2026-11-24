package com.splayer.next.web.api

import android.content.ContentUris
import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.MediaStore
import android.util.LruCache
import com.splayer.next.web.Json
import com.splayer.next.web.SPlayerBridge
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Android 端本地音乐库：对应主进程 services/library 的 SQLite 实现。
 * - 扫描：MediaStore（Audio.Media），元数据经 MediaMetadataRetriever 补全
 * - 持久化：library.db（tracks / scan_dirs / cover_tokens 三表）
 * - 封面：内嵌 art 提取到应用缓存文件，经 WebViewAssetLoader 域名以
 *   /assets/localfile/<token> 提供给渲染层 <img> 加载
 * - 播放：track.path 为 content:// URI，ExoPlayer 经 ContentDataSource 直接播放
 * - 事件：library:scan-progress {scanned,total,path} 推送给渲染层
 */
class LibraryStore(context: Context) {

    private val appContext = context.applicationContext
    private val scope = CoroutineScope(Dispatchers.IO)
    private val scanning = AtomicBoolean(false)
    private val scanCanceled = AtomicBoolean(false)

    /** token → 封面文件缓存（同时落库，进程重启后仍可用） */
    private val tokenCache = LruCache<String, String>(512)

    private val db by lazy {
        appContext.openOrCreateDatabase("library.db", Context.MODE_PRIVATE, null).apply {
            execSQL(
                """
                CREATE TABLE IF NOT EXISTS tracks (
                  id TEXT PRIMARY KEY, data TEXT NOT NULL, title TEXT NOT NULL,
                  artist TEXT NOT NULL DEFAULT '', album TEXT NOT NULL DEFAULT '',
                  searchText TEXT NOT NULL DEFAULT '', path TEXT NOT NULL,
                  mtime INTEGER NOT NULL DEFAULT 0
                )""".trimIndent(),
            )
            execSQL("CREATE INDEX IF NOT EXISTS idx_tracks_search ON tracks(searchText)")
            execSQL("CREATE TABLE IF NOT EXISTS scan_dirs (path TEXT PRIMARY KEY, addedAt INTEGER NOT NULL)")
            execSQL(
                "CREATE TABLE IF NOT EXISTS cover_tokens (token TEXT PRIMARY KEY, source TEXT NOT NULL)",
            )
        }
    }

    // MARK: - 桥接方法（library.*）

    fun handle(method: String, args: List<Any?>): Any? = when (method) {
        "scan" -> {
            scan()
            null
        }
        "cancelScan" -> {
            scanCanceled.set(true)
            null
        }
        "isScanning" -> scanning.get()
        "getTracks" -> allTracks()
        "getAlbums" -> aggregate(
            column = "album",
            emptyIsOther = true,
        ) { row -> albumOf(row) }
        "getArtists" -> aggregate(
            column = "artist",
            emptyIsOther = true,
        ) { row -> artistOf(row) }
        "getAlbumTracks" -> tracksWhere("album = ?", listOf(str(args, 0)))
        "getArtistTracks" -> tracksWhere("artist = ?", listOf(str(args, 0)))
        "getTracksByIds" -> {
            val ids = (args.getOrNull(0) as? List<*>)?.mapNotNull { it?.toString() } ?: emptyList()
            if (ids.isEmpty()) emptyList() else tracksWhere(
                "id IN (${ids.joinToString(",") { "?" }})",
                ids,
            )
        }
        "searchTracks" -> {
            val q = "%${str(args, 0).trim()}%"
            if (str(args, 0).isBlank()) emptyList()
            else tracksWhere("searchText LIKE ?", listOf(q))
        }
        "quickSearch" -> {
            val q = "%${str(args, 0).trim()}%"
            JSONObject().apply {
                put(
                    "tracks",
                    JSONArray(tracksWhere("searchText LIKE ?", listOf(q)).take(30)),
                )
                put(
                    "albums",
                    JSONArray(aggregate("album", true) { row -> albumOf(row) }
                        .filter { it["name"]?.toString()?.contains(str(args, 0), true) == true }
                        .take(10)),
                )
                put(
                    "artists",
                    JSONArray(aggregate("artist", true) { row -> artistOf(row) }
                        .filter { it["name"]?.toString()?.contains(str(args, 0), true) == true }
                        .take(10)),
                )
            }
        }
        "getTrackCount" -> {
            db.rawQuery("SELECT COUNT(*) FROM tracks", null).use { c -> c.moveToFirst(); c.getInt(0) }
        }
        "getRandomTrack" -> tracksWhere("1=1 ORDER BY RANDOM() LIMIT 1").firstOrNull()
        "getRandomTracks" -> {
            val limit = (args.getOrNull(0) as? Number)?.toInt() ?: 20
            tracksWhere("1=1 ORDER BY RANDOM() LIMIT $limit")
        }
        "addScanDir" -> {
            // 与原版不同：Android 无法自由浏览任意目录，改用 MediaStore 全库扫描 + 可选排除
            scan()
            null
        }
        "removeScanDir" -> {
            db.delete("scan_dirs", "path = ?", arrayOf(str(args, 0)))
            null
        }
        "getScanDirs" -> {
            val out = mutableListOf<String>()
            db.rawQuery("SELECT path FROM scan_dirs", null).use { c ->
                while (c.moveToNext()) out.add(c.getString(0))
            }
            out
        }
        "deleteTracks" -> {
            val paths = (args.getOrNull(0) as? List<*>)?.mapNotNull { it?.toString() } ?: emptyList()
            paths.forEach { p ->
                runCatching {
                    appContext.contentResolver.delete(Uri.parse(p), null, null)
                }
                db.delete("tracks", "path = ?", arrayOf(p))
            }
            null
        }
        "readTags" -> readTags(str(args, 0))
        "writeTags" -> throw BridgeUnsupportedException(
            "library.writeTags：Android 端暂不支持写文件标签（待后续版本引入标签库）",
        )
        "pickCoverImage" -> throw BridgeUnsupportedException(
            "library.pickCoverImage：待接入系统图片选择器",
        )
        "fetchArtistAvatar" -> null
        "prefetchArtistAvatars" -> null
        else -> throw BridgeUnsupportedException("library.$method 暂未在 Android 端实现")
    }

    private fun str(args: List<Any?>, i: Int): String = args.getOrNull(i)?.toString() ?: ""

    // MARK: - 扫描

    /** MediaStore 全库扫描，增量更新并推送进度事件 */
    private fun scan() {
        if (!scanning.compareAndSet(false, true)) return
        scope.launch {
            try {
                scanCanceled.set(false)
                val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
                val projection = arrayOf(
                    MediaStore.Audio.Media._ID,
                    MediaStore.Audio.Media.TITLE,
                    MediaStore.Audio.Media.ARTIST,
                    MediaStore.Audio.Media.ALBUM,
                    MediaStore.Audio.Media.ALBUM_ID,
                    MediaStore.Audio.Media.ARTIST_ID,
                    MediaStore.Audio.Media.DURATION,
                    MediaStore.Audio.Media.SIZE,
                    MediaStore.Audio.Media.DATE_MODIFIED,
                    MediaStore.Audio.Media.DATA,
                    MediaStore.Audio.Media.MIME_TYPE,
                )
                val selection =
                    "${MediaStore.Audio.Media.IS_MUSIC} = 1 AND ${MediaStore.Audio.Media.DURATION} >= 30000"
                val found = mutableListOf<JSONObject>()
                appContext.contentResolver.query(
                    collection,
                    projection,
                    selection,
                    null,
                    "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE",
                )?.use { c ->
                    val total = c.count
                    var scanned = 0
                    while (c.moveToNext() && !scanCanceled.get()) {
                        val uri = ContentUris.withAppendedId(
                            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                            c.getLong(0),
                        )
                        val track = buildTrack(c, uri)
                        if (track != null) {
                            upsertTrack(track)
                            found.add(track)
                        }
                        scanned++
                        if (scanned % 20 == 0 || scanned == total) {
                            pushProgress(scanned, total, c.getString(1) ?: "")
                        }
                    }
                }
            } finally {
                scanning.set(false)
                pushProgress(-1, -1, "")
            }
        }
    }

    private fun buildTrack(c: android.database.Cursor, uri: Uri): JSONObject? {
        val title = c.getString(1) ?: return null
        val artistName = c.getString(2) ?: "未知歌手"
        val albumName = c.getString(3) ?: "未知专辑"
        val albumId = c.getLong(4)
        val duration = c.getLong(6)
        val size = c.getLong(7)
        val mtime = c.getLong(8) * 1000
        val mime = c.getString(10) ?: "audio/mpeg"

        // 专辑封面：album art content uri 延迟解析，这里先登记 token
        val albumArtUri = Uri.parse("content://media/external/audio/albumart/$albumId")
        val coverUrl = registerCover(albumArtUri, albumId.toString())
        val codec = when {
            mime.contains("flac") -> "flac"
            mime.contains("ogg") -> "ogg"
            mime.contains("aac") || mime.contains("m4a") -> "aac"
            mime.contains("wav") -> "wav"
            else -> "mp3"
        }
        return JSONObject().apply {
            put("id", "local:${c.getLong(0)}")
            put("source", "local")
            put("path", uri.toString())
            put("title", title)
            put("artists", JSONArray().put(JSONObject().put("name", artistName)))
            put(
                "album",
                JSONObject().put("name", albumName).putOpt("cover", coverUrl),
            )
            put("duration", duration)
            put("cover", coverUrl)
            put("fileSize", size)
            put("mtime", mtime)
            put(
                "quality",
                JSONObject().put("codec", codec).put("sampleRate", 0).put("channels", 0)
                    .put("bitsPerSample", 0).put("bitRate", 0),
            )
        }
    }

    private fun pushProgress(scanned: Int, total: Int, current: String) {
        com.splayer.next.web.SPlayerBridge.active?.pushEvent(
            "library:scan-progress",
            JSONObject().apply {
                put("scanned", scanned)
                put("total", total)
                put("current", current)
            }.toString(),
        )
    }

    // MARK: - 封面 token

    /** 登记 token → 封面源；渲染层以 /assets/localfile/<token> 访问 */
    fun registerCover(sourceUri: Uri, key: String): String {
        val token = md5(key).take(16)
        tokenCache.put(token, sourceUri.toString())
        db.execSQL(
            "INSERT OR REPLACE INTO cover_tokens(token, source) VALUES(?, ?)",
            arrayOf(token, sourceUri.toString()),
        )
        return "https://appassets.androidplatform.net/assets/localfile/$token"
    }

    /** WebViewAssetHandler 调用：token → 打开的 URI（无则 null） */
    fun resolveCoverToken(token: String): Uri? {
        tokenCache.get(token)?.let { return Uri.parse(it) }
        var out: Uri? = null
        db.rawQuery("SELECT source FROM cover_tokens WHERE token = ?", arrayOf(token)).use { c ->
            if (c.moveToFirst()) {
                out = Uri.parse(c.getString(0))
                tokenCache.put(token, c.getString(0))
            }
        }
        return out
    }

    private fun md5(input: String): String =
        MessageDigest.getInstance("MD5").digest(input.toByteArray())
            .joinToString("") { "%02x".format(it) }

    // MARK: - 数据访问

    private fun upsertTrack(track: JSONObject) {
        val id = track.optString("id")
        val title = track.optString("title")
        val artist = track.optJSONArray("artists")?.optJSONObject(0)?.optString("name") ?: ""
        val album = track.optJSONObject("album")?.optString("name") ?: ""
        val searchText = "$title\n$artist\n$album"
        db.execSQL(
            """
            INSERT OR REPLACE INTO tracks(id, data, title, artist, album, searchText, path, mtime)
            VALUES(?,?,?,?,?,?,?,?)
            """.trimIndent(),
            arrayOf(
                id,
                track.toString(),
                title,
                artist,
                album,
                searchText,
                track.optString("path"),
                track.optLong("mtime"),
            ),
        )
    }

    private fun rowToTrack(c: android.database.Cursor): JSONObject {
        val map = Json.toMap(JSONObject(c.getString(1)))
        return JSONObject(Json.write(map))
    }

    private fun allTracks(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        db.rawQuery(
            "SELECT id, data FROM tracks ORDER BY artist COLLATE NOCASE, album COLLATE NOCASE, title COLLATE NOCASE",
            null,
        ).use { c -> while (c.moveToNext()) out.add(Json.toMap(rowToTrack(c))) }
        return out
    }

    private fun tracksWhere(where: String, sel: List<String> = emptyList()): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        db.rawQuery(
            "SELECT id, data FROM tracks WHERE $where ORDER BY title COLLATE NOCASE",
            sel.toTypedArray(),
        ).use { c -> while (c.moveToNext()) out.add(Json.toMap(rowToTrack(c))) }
        return out
    }

    /** 聚合专辑/艺术家：column 为 tracks 表列名，builder 由调用方提供 */
    private fun aggregate(
        column: String,
        @Suppress("UNUSED_PARAMETER") emptyIsOther: Boolean,
        builder: (android.database.Cursor) -> JSONObject,
    ): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        db.rawQuery(
            """
            SELECT $column, COUNT(*), COUNT(DISTINCT album) FROM tracks
            GROUP BY $column ORDER BY $column COLLATE NOCASE
            """.trimIndent(),
            null,
        ).use { c -> while (c.moveToNext()) out.add(Json.toMap(builder(c))) }
        return out
    }

    private fun albumOf(c: android.database.Cursor): JSONObject {
        val name = c.getString(0)
        return JSONObject().apply {
            put("name", name)
            put("trackCount", c.getInt(1))
        }
    }

    private fun artistOf(c: android.database.Cursor): JSONObject {
        val name = c.getString(0)
        return JSONObject().apply {
            put("name", name)
            put("albumCount", c.getInt(2))
        }
    }

    // MARK: - 标签读取

    private fun readTags(path: String): Map<String, Any?>? {
        if (path.isBlank()) return null
        val mmr = MediaMetadataRetriever()
        return try {
            mmr.setDataSource(appContext, Uri.parse(path))
            mapOf(
                "title" to mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE),
                "artists" to listOf(
                    mapOf(
                        "name" to (
                            mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
                                ?: "未知歌手"
                            ),
                    ),
                ),
                "album" to mapOf(
                    "name" to (
                        mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
                            ?: "未知专辑"
                        ),
                ),
                "track" to mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER),
                "duration" to (
                    mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        ?.toLongOrNull() ?: 0L
                    ),
            )
        } catch (_: Exception) {
            null
        } finally {
            runCatching { mmr.release() }
        }
    }

    companion object {
        @Volatile
        private var instance: LibraryStore? = null

        fun shared(context: Context): LibraryStore =
            instance ?: synchronized(this) {
                instance ?: LibraryStore(context.applicationContext).also { instance = it }
            }
    }
}