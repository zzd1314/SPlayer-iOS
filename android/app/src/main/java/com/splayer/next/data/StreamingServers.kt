package com.splayer.next.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest

/**
 * 流媒体服务器支持：Subsonic / Navidrome、Jellyfin、Emby。
 * 只做「浏览 + 在线播放」：歌曲、专辑、歌单，播放地址直接写入 Song.streamUrl，
 * 播放链路的其余部分（队列、封面、下载）复用现有实现。
 */

/** 服务器协议类型 */
enum class ServerType(val label: String, val hint: String) {
    SUBSONIC("Subsonic / Navidrome", "兼容 OpenSubsonic 的服务器"),
    JELLYFIN("Jellyfin", "开源媒体服务器"),
    EMBY("Emby", "Emby 媒体服务器")
}

/** 一台已保存的流媒体服务器 */
data class MusicServer(
    val id: String,
    val type: ServerType,
    val name: String,
    val baseUrl: String,
    val username: String = "",
    /** Subsonic 密码 / Jellyfin 密码，仅保存在本机 */
    val password: String = "",
    /** Jellyfin / Emby 登录后拿到的 AccessToken */
    val token: String = "",
    /** Jellyfin / Emby 用户 id */
    val userId: String = ""
) {
    val authorized: Boolean get() = when (type) {
        ServerType.SUBSONIC -> username.isNotBlank() && password.isNotBlank()
        else -> token.isNotBlank() && userId.isNotBlank()
    }
}

/** 服务器列表持久化（SharedPreferences + JSON） */
object ServerStore {

    private const val PREFS_NAME = "splayer_next_servers"
    private const val KEY_SERVERS = "servers"

    private var prefs: SharedPreferences? = null

    var servers by mutableStateOf<List<MusicServer>>(emptyList())
        private set

    fun init(context: Context) {
        if (prefs != null) return
        val store = context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs = store
        servers = parse(store.getString(KEY_SERVERS, null))
    }

    /** 新增或更新；id 为空时自动生成 */
    fun save(server: MusicServer): MusicServer {
        val normalized = if (server.id.isBlank()) {
            server.copy(id = "srv-" + System.nanoTime().toString(36))
        } else {
            server
        }
        servers = if (servers.any { it.id == normalized.id }) {
            servers.map { if (it.id == normalized.id) normalized else it }
        } else {
            servers + normalized
        }
        persist()
        return normalized
    }

    fun remove(id: String) {
        servers = servers.filterNot { it.id == id }
        persist()
    }

    /** Jellyfin / Emby 登录后缓存 Token，避免每次请求都重新认证 */
    fun updateAuth(id: String, token: String, userId: String) {
        if (servers.none { it.id == id }) return
        servers = servers.map {
            if (it.id == id) it.copy(token = token, userId = userId) else it
        }
        persist()
    }

    fun byId(id: String): MusicServer? = servers.firstOrNull { it.id == id }

    private fun persist() {
        prefs?.edit()?.putString(KEY_SERVERS, encode(servers))?.apply()
    }

    private fun encode(list: List<MusicServer>): String {
        val array = JSONArray()
        list.forEach { server ->
            array.put(
                JSONObject().apply {
                    put("id", server.id)
                    put("type", server.type.name)
                    put("name", server.name)
                    put("baseUrl", server.baseUrl)
                    put("username", server.username)
                    put("password", server.password)
                    put("token", server.token)
                    put("userId", server.userId)
                }
            )
        }
        return array.toString()
    }

    private fun parse(raw: String?): List<MusicServer> {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { index ->
                val item = array.optJSONObject(index) ?: return@mapNotNull null
                val id = item.optString("id").ifBlank { return@mapNotNull null }
                MusicServer(
                    id = id,
                    type = runCatching {
                        ServerType.valueOf(item.optString("type"))
                    }.getOrDefault(ServerType.SUBSONIC),
                    name = item.optString("name").ifBlank { "流媒体服务器" },
                    baseUrl = item.optString("baseUrl"),
                    username = item.optString("username"),
                    password = item.optString("password"),
                    token = item.optString("token"),
                    userId = item.optString("userId")
                )
            }
        }.getOrDefault(emptyList())
    }
}

// MARK: - 通用工具

private const val USER_AGENT = "SPlayer-Next-Android/0.6.0"

private fun encode(value: String): String = URLEncoder.encode(value, "UTF-8")

private fun md5(value: String): String {
    val digest = MessageDigest.getInstance("MD5").digest(value.toByteArray())
    return digest.joinToString("") { "%02x".format(it) }
}

private fun httpGet(url: String): String = requestText(url, "GET", null, emptyMap())

private fun httpPost(url: String, body: String, headers: Map<String, String>): String =
    requestText(url, "POST", body, headers)

private fun requestText(
    url: String,
    method: String,
    body: String?,
    headers: Map<String, String>
): String {
    val connection = URL(url).openConnection() as HttpURLConnection
    connection.connectTimeout = 12_000
    connection.readTimeout = 20_000
    connection.requestMethod = method
    connection.setRequestProperty("User-Agent", USER_AGENT)
    connection.setRequestProperty("Accept", "application/json")
    headers.forEach { (key, value) -> connection.setRequestProperty(key, value) }
    if (body != null) {
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
        connection.outputStream.use { it.write(body.toByteArray()) }
    }
    try {
        val code = connection.responseCode
        val stream = if (code in 200..299) connection.inputStream else connection.errorStream
        val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        if (code !in 200..299) {
            val detail = text.take(160).replace("\n", " ")
            throw IOException("HTTP $code" + if (detail.isNotBlank()) "：$detail" else "")
        }
        return text
    } finally {
        connection.disconnect()
    }
}

// MARK: - Subsonic / Navidrome

object SubsonicClient {

    private const val API_VERSION = "1.16.1"
    private const val CLIENT_NAME = "SPlayer"

    private fun base(server: MusicServer): String = server.baseUrl.trim().trimEnd('/')

    private fun endpoint(server: MusicServer, method: String, extra: Map<String, String> = emptyMap()): String {
        val salt = (System.nanoTime() and 0xFFFFFFF).toString(36)
        val params = linkedMapOf(
            "u" to server.username,
            "t" to md5(server.password + salt),
            "s" to salt,
            "v" to API_VERSION,
            "c" to CLIENT_NAME,
            "f" to "json"
        )
        params.putAll(extra)
        val query = params.entries.joinToString("&") { (key, value) -> "$key=${encode(value)}" }
        return "${base(server)}/rest/$method?$query"
    }

    fun streamUrl(server: MusicServer, songId: String): String =
        endpoint(server, "stream.view", mapOf("id" to songId))

    fun coverUrl(server: MusicServer, coverArtId: String?): String? {
        if (coverArtId.isNullOrBlank()) return null
        return endpoint(
            server,
            "getCoverArt.view",
            mapOf("id" to coverArtId, "size" to "300")
        )
    }

    private suspend fun request(
        server: MusicServer,
        method: String,
        extra: Map<String, String> = emptyMap()
    ): JSONObject = withContext(Dispatchers.IO) {
        val root = JSONObject(httpGet(endpoint(server, method, extra)))
        val sub = root.optJSONObject("subsonic-response")
            ?: throw IOException("不是有效的 Subsonic 响应")
        if (!sub.optString("status").equals("ok", ignoreCase = true)) {
            val message = sub.optJSONObject("error")
                ?.optString("message")
                ?.ifBlank { null }
            throw IOException(message ?: "服务器返回错误")
        }
        sub
    }

    suspend fun ping(server: MusicServer): String = withContext(Dispatchers.IO) {
        val sub = request(server, "ping.view")
        val type = sub.optString("type").ifBlank { "Subsonic" }
        val version = sub.optString("version")
        "连接成功：$type" + if (version.isNotBlank()) " v$version" else ""
    }

    suspend fun randomSongs(server: MusicServer, size: Int = 100): List<Song> =
        withContext(Dispatchers.IO) {
            val sub = request(server, "getRandomSongs.view", mapOf("size" to size.toString()))
            val array = sub.optJSONObject("randomSongs")?.optJSONArray("song")
                ?: return@withContext emptyList()
            (0 until array.length()).mapNotNull { songFrom(server, array.optJSONObject(it)) }
        }

    suspend fun albums(server: MusicServer): List<Playlist> = withContext(Dispatchers.IO) {
        val params = mapOf("type" to "alphabeticalByName", "size" to "100")
        // 老服务器可能不支持 ID3 版接口，回退到 getAlbumList
        val sub = runCatching { request(server, "getAlbumList2.view", params) }
            .getOrElse { request(server, "getAlbumList.view", params) }
        val array = sub.optJSONObject("albumList2")?.optJSONArray("album")
            ?: sub.optJSONObject("albumList")?.optJSONArray("album")
            ?: JSONArray()
        (0 until array.length()).mapNotNull { index ->
            val item = array.optJSONObject(index) ?: return@mapNotNull null
            val id = item.optString("id").ifBlank { return@mapNotNull null }
            val songCount = item.optInt("songCount")
            Playlist(
                id = id,
                title = item.optString("name").ifBlank { "未知专辑" },
                subtitle = item.optString("artist").ifBlank {
                    if (songCount > 0) "$songCount 首" else "专辑"
                },
                coverUrl = coverUrl(server, item.optString("coverArt").ifBlank { id }),
                tint = tintForId(id.hashCode().toLong()),
                trackCount = songCount
            )
        }
    }

    suspend fun albumSongs(server: MusicServer, albumId: String): List<Song> =
        withContext(Dispatchers.IO) {
            val sub = request(server, "getAlbum.view", mapOf("id" to albumId))
            val album = sub.optJSONObject("album") ?: return@withContext emptyList()
            val coverArt = album.optString("coverArt").ifBlank { albumId }
            val array = album.optJSONArray("song") ?: return@withContext emptyList()
            (0 until array.length()).mapNotNull {
                songFrom(server, array.optJSONObject(it), coverArt)
            }
        }

    suspend fun playlists(server: MusicServer): List<Playlist> = withContext(Dispatchers.IO) {
        val sub = request(server, "getPlaylists.view")
        val array = sub.optJSONObject("playlists")?.optJSONArray("playlist")
            ?: return@withContext emptyList()
        (0 until array.length()).mapNotNull { index ->
            val item = array.optJSONObject(index) ?: return@mapNotNull null
            val id = item.optString("id").ifBlank { return@mapNotNull null }
            val songCount = item.optInt("songCount")
            Playlist(
                id = id,
                title = item.optString("name").ifBlank { "未命名歌单" },
                subtitle = item.optString("owner").ifBlank {
                    if (songCount > 0) "$songCount 首" else "歌单"
                },
                coverUrl = coverUrl(server, item.optString("coverArt")),
                tint = tintForId(id.hashCode().toLong()),
                trackCount = songCount
            )
        }
    }

    suspend fun playlistSongs(server: MusicServer, playlistId: String): List<Song> =
        withContext(Dispatchers.IO) {
            val sub = request(server, "getPlaylist.view", mapOf("id" to playlistId))
            val playlist = sub.optJSONObject("playlist") ?: return@withContext emptyList()
            val array = playlist.optJSONArray("entry") ?: return@withContext emptyList()
            (0 until array.length()).mapNotNull { songFrom(server, array.optJSONObject(it)) }
        }

    private fun songFrom(server: MusicServer, item: JSONObject?, albumCoverArt: String? = null): Song? {
        if (item == null) return null
        val rawId = item.optString("id").ifBlank { return null }
        val coverArt = item.optString("coverArt")
            .ifBlank { item.optString("albumId") }
            .ifBlank { albumCoverArt ?: "" }
        return Song(
            id = "sub-${server.id}-$rawId",
            title = item.optString("title").ifBlank { "未知歌曲" },
            artist = item.optString("artist").ifBlank { "未知艺人" },
            album = item.optString("album"),
            durationMs = item.optLong("duration") * 1000L,
            coverUrl = coverUrl(server, coverArt),
            streamUrl = streamUrl(server, rawId),
            tint = tintForId(rawId.hashCode().toLong())
        )
    }
}

// MARK: - Jellyfin / Emby

object JellyfinClient {

    private const val CLIENT_NAME = "SPlayer Next"
    private const val DEVICE_NAME = "Android"
    private const val DEVICE_ID = "splayer-next-android"
    private const val VERSION = "0.6.0"

    private fun api(server: MusicServer): String {
        val base = server.baseUrl.trim().trimEnd('/')
        return if (server.type == ServerType.EMBY && !base.endsWith("/emby", ignoreCase = true)) {
            "$base/emby"
        } else {
            base
        }
    }

    private fun authHeader(): String =
        "MediaBrowser Client=\"$CLIENT_NAME\", Device=\"$DEVICE_NAME\", " +
            "DeviceId=\"$DEVICE_ID\", Version=\"$VERSION\""

    fun streamUrl(server: MusicServer, itemId: String): String =
        "${api(server)}/Audio/${encode(itemId)}/stream?static=true&api_key=${encode(server.token)}"

    private fun imageUrl(server: MusicServer, itemId: String, tag: String?): String? {
        if (tag.isNullOrBlank() || itemId.isBlank()) return null
        return "${api(server)}/Items/${encode(itemId)}/Images/Primary" +
            "?maxWidth=300&maxHeight=300&quality=90&api_key=${encode(server.token)}"
    }

    /** 使用用户名密码认证，返回带 Token 的服务器对象（不写回存储） */
    private suspend fun authenticate(server: MusicServer): MusicServer = withContext(Dispatchers.IO) {
        val body = JSONObject().apply {
            put("Username", server.username)
            put("Pw", server.password)
        }
        val root = JSONObject(
            httpPost(
                "${api(server)}/Users/AuthenticateByName",
                body.toString(),
                mapOf("Authorization" to authHeader())
            )
        )
        val token = root.optString("AccessToken")
        if (token.isBlank()) throw IOException("登录失败：未返回 AccessToken")
        val userId = root.optJSONObject("User")?.optString("Id").orEmpty()
        if (userId.isBlank()) throw IOException("登录失败：未返回用户 ID")
        server.copy(token = token, userId = userId)
    }

    /** 优先使用缓存 Token，否则用账号密码登录并持久化 */
    private suspend fun ensureAuthorized(server: MusicServer): MusicServer = withContext(Dispatchers.IO) {
        val current = ServerStore.byId(server.id) ?: server
        if (current.token.isNotBlank() && current.userId.isNotBlank()) {
            return@withContext current
        }
        val authed = authenticate(current)
        ServerStore.updateAuth(current.id, authed.token, authed.userId)
        authed
    }

    suspend fun test(server: MusicServer): String = withContext(Dispatchers.IO) {
        val authed = authenticate(server)
        val info = runCatching {
            JSONObject(httpGet("${api(authed)}/System/Info/Public"))
        }.getOrNull()
        val name = info?.optString("ServerName")?.ifBlank { null }
            ?: server.name.ifBlank { "Jellyfin" }
        val version = info?.optString("Version").orEmpty()
        "连接成功：$name" + if (version.isNotBlank()) " v$version" else ""
    }

    private fun itemsUrl(server: MusicServer, params: Map<String, String>): String {
        val base = api(server)
        val query = linkedMapOf(
            "api_key" to server.token,
            "userId" to server.userId
        )
        query.putAll(params)
        return "$base/Items?" + query.entries.joinToString("&") { (k, v) -> "$k=${encode(v)}" }
    }

    private suspend fun fetchItems(server: MusicServer, params: Map<String, String>): JSONArray =
        withContext(Dispatchers.IO) {
            val body = httpGet(itemsUrl(server, params))
            JSONObject(body).optJSONArray("Items") ?: JSONArray()
        }

    suspend fun randomSongs(server: MusicServer, limit: Int = 100): List<Song> =
        withContext(Dispatchers.IO) {
            val authed = ensureAuthorized(server)
            val items = fetchItems(
                authed,
                mapOf(
                    "Recursive" to "true",
                    "IncludeItemTypes" to "Audio",
                    "SortBy" to "Random",
                    "Limit" to limit.toString(),
                    "Fields" to "AlbumId,AlbumPrimaryImageTag,ImageTags,RunTimeTicks"
                )
            )
            (0 until items.length()).mapNotNull { songFrom(authed, items.optJSONObject(it)) }
        }

    suspend fun albums(server: MusicServer): List<Playlist> = withContext(Dispatchers.IO) {
        val authed = ensureAuthorized(server)
        val items = fetchItems(
            authed,
            mapOf(
                "Recursive" to "true",
                "IncludeItemTypes" to "MusicAlbum",
                "SortBy" to "SortName",
                "SortOrder" to "Ascending",
                "Limit" to "200",
                "Fields" to "ImageTags,ChildCount"
            )
        )
        (0 until items.length()).mapNotNull { index ->
            val item = items.optJSONObject(index) ?: return@mapNotNull null
            val id = item.optString("Id").ifBlank { return@mapNotNull null }
            val artist = item.optJSONArray("AlbumArtists")
                ?.optJSONObject(0)
                ?.optString("Name")
                .orEmpty()
                .ifBlank { item.optString("AlbumArtist") }
            val count = item.optInt("ChildCount")
            Playlist(
                id = id,
                title = item.optString("Name").ifBlank { "未知专辑" },
                subtitle = artist.ifBlank { if (count > 0) "$count 首" else "专辑" },
                coverUrl = imageUrl(
                    authed,
                    id,
                    item.optJSONObject("ImageTags")?.optString("Primary")
                ),
                tint = tintForId(id.hashCode().toLong()),
                trackCount = count
            )
        }
    }

    suspend fun albumSongs(server: MusicServer, albumId: String): List<Song> =
        withContext(Dispatchers.IO) {
            val authed = ensureAuthorized(server)
            val items = fetchItems(
                authed,
                mapOf(
                    "ParentId" to albumId,
                    "Recursive" to "true",
                    "IncludeItemTypes" to "Audio",
                    "SortBy" to "ParentIndexNumber,IndexNumber",
                    "Limit" to "500",
                    "Fields" to "AlbumId,AlbumPrimaryImageTag,ImageTags,RunTimeTicks"
                )
            )
            (0 until items.length()).mapNotNull { songFrom(authed, items.optJSONObject(it)) }
        }

    suspend fun playlists(server: MusicServer): List<Playlist> = withContext(Dispatchers.IO) {
        val authed = ensureAuthorized(server)
        val items = fetchItems(
            authed,
            mapOf(
                "Recursive" to "true",
                "IncludeItemTypes" to "Playlist",
                "SortBy" to "SortName",
                "Limit" to "200",
                "Fields" to "ImageTags,ChildCount"
            )
        )
        (0 until items.length()).mapNotNull { index ->
            val item = items.optJSONObject(index) ?: return@mapNotNull null
            val id = item.optString("Id").ifBlank { return@mapNotNull null }
            val count = item.optInt("ChildCount")
            Playlist(
                id = id,
                title = item.optString("Name").ifBlank { "未命名歌单" },
                subtitle = if (count > 0) "$count 首" else "歌单",
                coverUrl = imageUrl(
                    authed,
                    id,
                    item.optJSONObject("ImageTags")?.optString("Primary")
                ),
                tint = tintForId(id.hashCode().toLong()),
                trackCount = count
            )
        }
    }

    suspend fun playlistSongs(server: MusicServer, playlistId: String): List<Song> =
        withContext(Dispatchers.IO) {
            val authed = ensureAuthorized(server)
            val url = "${api(authed)}/Playlists/${encode(playlistId)}/Items" +
                "?userId=${encode(authed.userId)}" +
                "&api_key=${encode(authed.token)}" +
                "&Fields=AlbumId,AlbumPrimaryImageTag,ImageTags,RunTimeTicks" +
                "&Limit=500"
            val items = JSONObject(httpGet(url)).optJSONArray("Items") ?: JSONArray()
            (0 until items.length()).mapNotNull { songFrom(authed, items.optJSONObject(it)) }
        }

    private fun songFrom(server: MusicServer, item: JSONObject?): Song? {
        if (item == null) return null
        val id = item.optString("Id").ifBlank { return null }
        val artists = item.optJSONArray("Artists")?.let { array ->
            (0 until array.length())
                .mapNotNull { array.optString(it).ifBlank { null } }
        }.orEmpty()
        val artist = artists.joinToString(" / ").ifBlank {
            item.optString("AlbumArtist").ifBlank { "未知艺人" }
        }
        val albumId = item.optString("AlbumId")
        val albumTag = item.optString("AlbumPrimaryImageTag")
        val coverUrl = imageUrl(server, albumId, albumTag)
            ?: imageUrl(server, id, item.optJSONObject("ImageTags")?.optString("Primary"))
        val ticks = item.optLong("RunTimeTicks")
        return Song(
            id = "jf-${server.id}-$id",
            title = item.optString("Name").ifBlank { "未知歌曲" },
            artist = artist,
            album = item.optString("Album"),
            durationMs = if (ticks > 0L) ticks / 10_000L else 0L,
            coverUrl = coverUrl,
            streamUrl = streamUrl(server, id),
            tint = tintForId(id.hashCode().toLong())
        )
    }
}