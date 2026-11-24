package com.splayer.next.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * 网易云音乐 Web 接口封装。
 * 与 iOS 端的 NeteaseAPI 保持同构：搜索、推荐、歌单详情、歌词、账号资料。
 * 仅使用 HttpURLConnection + org.json，避免额外依赖。
 */
object NetEaseApi {

    private const val BASE = "https://music.163.com"
    private const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36"

    /** 登录 Cookie（由设置页写入） */
    @Volatile
    var cookie: String? = null

    // MARK: - 搜索

    suspend fun searchSongs(keyword: String): List<Song> = withContext(Dispatchers.IO) {
        val encoded = URLEncoder.encode(keyword, "UTF-8")
        val body = get("$BASE/api/search/get/web?csrf_token=&s=$encoded&type=1&offset=0&total=true&limit=50")
        val songs = JSONObject(body).optJSONObject("result")?.optJSONArray("songs")
            ?: return@withContext emptyList()
        (0 until songs.length()).mapNotNull { songFrom(songs.optJSONObject(it)) }
    }

    suspend fun searchPlaylists(keyword: String): List<Playlist> = withContext(Dispatchers.IO) {
        val encoded = URLEncoder.encode(keyword, "UTF-8")
        val body = get("$BASE/api/search/get/web?csrf_token=&s=$encoded&type=1000&offset=0&total=true&limit=30")
        val list = JSONObject(body).optJSONObject("result")?.optJSONArray("playlists")
            ?: return@withContext emptyList()
        (0 until list.length()).mapNotNull { playlistFrom(list.optJSONObject(it)) }
    }

    suspend fun searchArtists(keyword: String): List<ArtistItem> = withContext(Dispatchers.IO) {
        val encoded = URLEncoder.encode(keyword, "UTF-8")
        val body = get("$BASE/api/search/get/web?csrf_token=&s=$encoded&type=100&offset=0&total=true&limit=30")
        val list = JSONObject(body).optJSONObject("result")?.optJSONArray("artists")
            ?: return@withContext emptyList()
        (0 until list.length()).mapNotNull { index ->
            val item = list.optJSONObject(index) ?: return@mapNotNull null
            val id = item.optLong("id")
            if (id <= 0L) return@mapNotNull null
            ArtistItem(
                id = id.toString(),
                name = item.optString("name").ifBlank { "未知艺人" },
                coverUrl = httpsUrl(
                    item.optString("picUrl").ifBlank { item.optString("img1v1Url") }
                ),
                subtitle = "歌手",
                tint = tintForId(id)
            )
        }
    }

    // MARK: - 推荐

    suspend fun newSongs(): List<Song> = withContext(Dispatchers.IO) {
        val body = get("$BASE/api/personalized/newsong?limit=20")
        val result = JSONObject(body).optJSONArray("result") ?: return@withContext emptyList()
        (0 until result.length()).mapNotNull { index ->
            val item = result.optJSONObject(index) ?: return@mapNotNull null
            songFrom(item.optJSONObject("song") ?: item)
        }
    }

    suspend fun recommendedPlaylists(): List<Playlist> = withContext(Dispatchers.IO) {
        val body = get("$BASE/api/personalized/playlist?limit=12&total=true&n=1000")
        val result = JSONObject(body).optJSONArray("result") ?: return@withContext emptyList()
        (0 until result.length()).mapNotNull { playlistFrom(result.optJSONObject(it)) }
    }

    /** 排行榜：飙升榜 / 新歌榜 / 原创榜等 */
    suspend fun topPlaylists(): List<Playlist> = withContext(Dispatchers.IO) {
        val body = get("$BASE/api/toplist")
        val root = JSONObject(body)
        val list = root.optJSONArray("list") ?: root.optJSONArray("result")
            ?: return@withContext emptyList()
        (0 until list.length()).mapNotNull { playlistFrom(list.optJSONObject(it)) }
    }

    // MARK: - 歌单详情

    suspend fun playlistDetail(id: String): PlaylistWithSongs? = withContext(Dispatchers.IO) {
        val body = get("$BASE/api/playlist/detail?id=$id")
        val root = JSONObject(body)
        val result = root.optJSONObject("result") ?: return@withContext null
        val playlistObj = result.optJSONObject("playlist") ?: result
        val tracks = playlistObj.optJSONArray("tracks")
            ?: result.optJSONArray("tracks")
            ?: JSONArray()

        val songs = (0 until tracks.length()).mapNotNull { songFrom(tracks.optJSONObject(it)) }
        val playlistId = playlistObj.optLong("id").takeIf { it > 0L } ?: id.toLongOrNull() ?: 0L
        val creator = playlistObj.optJSONObject("creator")?.optString("nickname").orEmpty()
        val playlist = Playlist(
            id = playlistId.toString(),
            title = playlistObj.optString("name").ifBlank { "歌单" },
            subtitle = creator.ifBlank { "" },
            coverUrl = httpsUrl(playlistObj.optString("coverImgUrl")),
            tint = tintForId(playlistId),
            trackCount = playlistObj.optInt("trackCount", songs.size),
            playCount = playlistObj.optLong("playCount")
        )
        PlaylistWithSongs(playlist, songs)
    }

    // MARK: - 歌词

    suspend fun lyric(songId: String): Lyric = withContext(Dispatchers.IO) {
        val body = get("$BASE/api/song/lyric?id=$songId&lv=1&kv=1&tv=-1")
        val root = JSONObject(body)
        val lrc = root.optJSONObject("lrc")?.optString("lyric")
        val translation = root.optJSONObject("tlyric")?.optString("lyric")
        LrcParser.parse(lrc, translation)
    }

    // MARK: - 账号

    suspend fun account(): UserProfile? = withContext(Dispatchers.IO) {
        val body = get("$BASE/api/nuser/account/get")
        val root = JSONObject(body)
        val profile = root.optJSONObject("profile") ?: return@withContext null
        val userId = profile.optLong("userId")
        if (userId <= 0L) return@withContext null
        UserProfile(
            userId = userId,
            nickname = profile.optString("nickname").ifBlank { "网易云用户" },
            avatarUrl = httpsUrl(profile.optString("avatarUrl")),
            signature = profile.optString("signature")
        )
    }

    /** 匿名可用的歌曲外链，播放时会 302 到 CDN（可能为 http，需要允许跨协议重定向） */
    fun streamUrl(id: String): String = "$BASE/song/media/outer/url?id=$id.mp3"

    // MARK: - 评论

    /** 歌曲评论：精彩评论在前，普通评论在后，按评论 id 去重 */
    suspend fun songComments(songId: String, limit: Int = 50): List<Comment> = withContext(Dispatchers.IO) {
        val body = get("$BASE/api/v1/resource/comments/R_SO_4_$songId?limit=$limit&offset=0")
        val root = JSONObject(body)
        val result = mutableListOf<Comment>()
        val seen = HashSet<String>()

        fun append(array: JSONArray?, hot: Boolean) {
            if (array == null) return
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                val cid = item.optLong("commentId").takeIf { it > 0L }?.toString() ?: continue
                if (!seen.add(cid)) continue
                result.add(commentFrom(item, hot, cid))
            }
        }

        append(root.optJSONArray("hotComments"), true)
        append(root.optJSONArray("comments"), false)
        result
    }

    // MARK: - 专辑

    suspend fun albumDetail(id: String): AlbumDetail? = withContext(Dispatchers.IO) {
        val root = JSONObject(get("$BASE/api/v1/album/$id"))
        val albumObj = root.optJSONObject("album") ?: root
        val albumId = albumObj.optLong("id").takeIf { it > 0L } ?: id.toLongOrNull() ?: 0L
        val artistObj = albumObj.optJSONObject("artist")
        val artistName = artistObj?.optString("name").orEmpty()
        val artistId = artistObj?.optLong("id")?.takeIf { it > 0L }?.toString()
        val songsArray = root.optJSONArray("songs") ?: JSONArray()
        val songs = (0 until songsArray.length())
            .mapNotNull { songFrom(songsArray.optJSONObject(it)) }
        val size = albumObj.optInt("size").takeIf { it > 0 } ?: songs.size
        val album = Playlist(
            id = albumId.toString(),
            title = albumObj.optString("name").ifBlank { "专辑" },
            subtitle = artistName,
            coverUrl = httpsUrl(albumObj.optString("picUrl")),
            tint = tintForId(albumId),
            trackCount = size
        )
        AlbumDetail(
            album = album,
            songs = songs,
            description = albumObj.optString("description"),
            artistId = artistId,
            artistName = artistName
        )
    }

    // MARK: - 歌手

    suspend fun artistDetail(id: String): ArtistDetail? = withContext(Dispatchers.IO) {
        val root = JSONObject(get("$BASE/api/artists?id=$id"))
        val artistObj = root.optJSONObject("artist") ?: return@withContext null
        val numericId = id.toLongOrNull() ?: 0L
        val name = artistObj.optString("name").ifBlank { "未知艺人" }
        val musicSize = artistObj.optInt("musicSize")
        val albumSize = artistObj.optInt("albumSize")
        val subtitle = buildString {
            if (musicSize > 0) append("$musicSize 首单曲")
            if (albumSize > 0) {
                if (isNotEmpty()) append(" · ")
                append("$albumSize 张专辑")
            }
        }.ifBlank { "歌手" }
        val artist = ArtistItem(
            id = id,
            name = name,
            coverUrl = httpsUrl(
                artistObj.optString("picUrl").ifBlank { artistObj.optString("img1v1Url") }
            ),
            subtitle = subtitle,
            tint = tintForId(numericId)
        )

        // 热门单曲：优先使用 /api/v1/artist/songs，失败时退回 hotSongs
        var songs = (0 until (root.optJSONArray("hotSongs")?.length() ?: 0)).mapNotNull {
            songFrom(root.optJSONArray("hotSongs")?.optJSONObject(it))
        }
        runCatching { get("$BASE/api/v1/artist/songs?id=$id&order=hot&limit=50&offset=0") }
            .getOrNull()
            ?.let { songBody ->
                val array = JSONObject(songBody).optJSONArray("songs")
                if (array != null && array.length() > 0) {
                    songs = (0 until array.length()).mapNotNull { songFrom(array.optJSONObject(it)) }
                }
            }

        val albums = runCatching {
            val albumRoot = JSONObject(get("$BASE/api/artist/albums/$id?limit=30&offset=0"))
            val array = albumRoot.optJSONArray("hotAlbums") ?: albumRoot.optJSONArray("more")
                ?: JSONArray()
            (0 until array.length()).mapNotNull { index ->
                val item = array.optJSONObject(index) ?: return@mapNotNull null
                val albumId = item.optLong("id")
                if (albumId <= 0L) return@mapNotNull null
                val albumArtist = item.optJSONObject("artist")?.optString("name").orEmpty()
                Playlist(
                    id = albumId.toString(),
                    title = item.optString("name").ifBlank { "专辑" },
                    subtitle = albumArtist.ifBlank { name },
                    coverUrl = httpsUrl(item.optString("picUrl")),
                    tint = tintForId(albumId),
                    trackCount = item.optInt("size")
                )
            }
        }.getOrDefault(emptyList())

        ArtistDetail(
            artist = artist,
            description = artistObj.optString("briefDesc"),
            songs = songs,
            albums = albums
        )
    }

    // MARK: - MV

    suspend fun topMvs(limit: Int = 20): List<MvItem> = withContext(Dispatchers.IO) {
        val root = JSONObject(get("$BASE/api/mv/toplist?limit=$limit&offset=0"))
        val array = root.optJSONArray("data") ?: return@withContext emptyList()
        (0 until array.length()).mapNotNull { mvFrom(array.optJSONObject(it)) }
    }

    suspend fun mvDetail(id: String): MvItem? = withContext(Dispatchers.IO) {
        val root = JSONObject(get("$BASE/api/mv/detail?id=$id"))
        mvFrom(root.optJSONObject("data"))
    }

    // MARK: - 播客 / 电台

    /** 推荐电台节目（匿名可用） */
    suspend fun djRecommendPrograms(limit: Int = 20): List<DjProgram> = withContext(Dispatchers.IO) {
        val root = JSONObject(get("$BASE/api/dj/program/recommend?limit=$limit&offset=0"))
        val array = root.optJSONArray("programs")
            ?: root.optJSONArray("data")
            ?: root.optJSONArray("result")
            ?: return@withContext emptyList()
        (0 until array.length()).mapNotNull { djProgramFrom(array.optJSONObject(it)) }
    }

    /** 热门电台：从推荐节目中提取并去重，避免使用需要登录的接口 */
    suspend fun djRadios(limit: Int = 12): List<DjRadio> = withContext(Dispatchers.IO) {
        val programs = djRecommendPrograms(limit = 40)
        val seen = HashSet<String>()
        programs.mapNotNull { program ->
            val radioId = program.radioId
            if (radioId.isBlank() || !seen.add(radioId)) return@mapNotNull null
            DjRadio(
                id = radioId,
                name = program.radioName.ifBlank { "播客电台" },
                djName = program.djName,
                coverUrl = program.coverUrl,
                tint = program.tint
            )
        }.take(limit)
    }

    /** 电台详情 + 节目列表 */
    suspend fun djRadioDetail(id: String, limit: Int = 30): DjRadioDetail? = withContext(Dispatchers.IO) {
        runCatching {
            val root = JSONObject(get("$BASE/api/djradio/detail?id=$id"))
            val radioObj = root.optJSONObject("data") ?: root.optJSONObject("djRadio") ?: root
            val numericId = id.toLongOrNull() ?: 0L
            val radio = DjRadio(
                id = id,
                name = radioObj.optString("name").ifBlank { "播客电台" },
                djName = radioObj.optJSONObject("dj")?.optString("nickname").orEmpty(),
                coverUrl = httpsUrl(radioObj.optString("picUrl")),
                description = radioObj.optString("desc").ifBlank {
                    radioObj.optString("description")
                },
                programCount = radioObj.optInt("programCount"),
                subscriberCount = radioObj.optLong("subCount"),
                tint = tintForId(numericId)
            )
            DjRadioDetail(radio = radio, programs = djPrograms(id, limit))
        }.getOrNull()
    }

    /** 电台节目列表 */
    suspend fun djPrograms(radioId: String, limit: Int = 30): List<DjProgram> = withContext(Dispatchers.IO) {
        runCatching {
            val root = JSONObject(
                get("$BASE/api/dj/program/byradio?radioId=$radioId&limit=$limit&offset=0&asc=false")
            )
            val array = root.optJSONArray("programs") ?: return@runCatching emptyList()
            (0 until array.length()).mapNotNull { djProgramFrom(array.optJSONObject(it)) }
        }.getOrDefault(emptyList())
    }

    /** 单个节目详情 */
    suspend fun djProgramDetail(id: String): DjProgram? = withContext(Dispatchers.IO) {
        runCatching {
            val root = JSONObject(get("$BASE/api/dj/program/detail?id=$id"))
            djProgramFrom(root.optJSONObject("program") ?: root.optJSONObject("data"))
        }.getOrNull()
    }

    // MARK: - 音质

    private val urlCache = java.util.concurrent.ConcurrentHashMap<String, String>()

    /**
     * 按音质获取播放地址。level: standard / higher / exhigh。
     * 未登录或版权受限时返回 null，由上层回退到外链接口。
     */
    suspend fun songPlayUrl(songId: String, level: String): String? = withContext(Dispatchers.IO) {
        if (songId.startsWith("demo-") || songId.startsWith("local-") || songId.startsWith("dj-")) {
            return@withContext null
        }
        if (songId.toLongOrNull() == null) return@withContext null
        val cacheKey = "$songId@$level"
        urlCache[cacheKey]?.let { return@withContext it }
        runCatching {
            val body = get(
                "$BASE/api/song/enhance/player/url/v1?id=$songId&level=$level&encodeType=mp3"
            )
            val raw = JSONObject(body).optJSONArray("data")
                ?.optJSONObject(0)
                ?.optString("url")
                ?.ifBlank { null }
                ?: return@runCatching null
            val url = httpsUrl(raw) ?: raw
            urlCache[cacheKey] = url
            url
        }.getOrNull()
    }

    // MARK: - 二维码登录

    /** 创建二维码登录会话 */
    suspend fun createQrLogin(): QrCodeLogin? = withContext(Dispatchers.IO) {
        runCatching {
            val root = JSONObject(get("$BASE/api/login/qrcode/unikey?type=1"))
            if (root.optInt("code") != 200) return@runCatching null
            val key = root.optString("unikey").ifBlank { return@runCatching null }
            QrCodeLogin(
                key = key,
                url = "https://music.163.com/login?codekey=$key"
            )
        }.getOrNull()
    }

    /** 轮询扫码状态：800 过期 / 801 待扫码 / 802 已扫码 / 803 成功 */
    suspend fun checkQrLogin(key: String): QrLoginResult = withContext(Dispatchers.IO) {
        runCatching {
            val headers = mutableListOf<String>()
            val body = get("$BASE/api/login/qrcode/client/login?key=$key&type=1", cookieSink = headers)
            val code = JSONObject(body).optInt("code")
            val cookie = headers.firstNotNullOfOrNull { line ->
                Regex("MUSIC_U=([^;\\s]+)").find(line)?.groupValues?.get(1)
                    ?.let { "MUSIC_U=$it" }
            }
            QrLoginResult(code = code, message = qrMessage(code), cookie = cookie)
        }.getOrDefault(QrLoginResult(code = -1, message = "网络异常，请重试"))
    }

    private fun qrMessage(code: Int): String = when (code) {
        800 -> "二维码已过期，请刷新"
        801 -> "等待扫码"
        802 -> "已扫码，请在手机上确认"
        803 -> "登录成功"
        else -> "等待扫码"
    }

    /** MV 播放地址（受版权限制时可能为空） */
    suspend fun mvUrl(id: String): String? = withContext(Dispatchers.IO) {
        runCatching {
            val root = JSONObject(get("$BASE/api/mv/url?id=$id&r=1080"))
            root.optJSONObject("data")?.optString("url")?.ifBlank { null }
        }.getOrNull()
    }

    // MARK: - 解析

    private fun songFrom(json: JSONObject?): Song? {
        if (json == null) return null
        val id = json.optLong("id").takeIf { it > 0L }
            ?: json.optString("id").toLongOrNull()?.takeIf { it > 0L }
            ?: return null
        val artists = json.optJSONArray("artists") ?: json.optJSONArray("ar")
        val album = json.optJSONObject("album") ?: json.optJSONObject("al")
        val aliasArray = json.optJSONArray("alias") ?: json.optJSONArray("alia")
        val alias = aliasArray?.optString(0)?.ifBlank { null }
        val duration = json.optLong("duration").takeIf { it > 0L }
            ?: json.optLong("dt").takeIf { it > 0L }
            ?: 0L
        val albumId = album?.optLong("id")?.takeIf { it > 0L }?.toString()
        val artistId = artists?.optJSONObject(0)?.optLong("id")?.takeIf { it > 0L }?.toString()

        return Song(
            id = id.toString(),
            title = json.optString("name").ifBlank { "未知歌曲" },
            artist = artistNames(artists).ifBlank { "未知艺人" },
            album = album?.optString("name").orEmpty(),
            durationMs = duration,
            coverUrl = httpsUrl(
                album?.optString("picUrl").orEmpty().ifBlank { json.optString("picUrl") }
            ),
            streamUrl = streamUrl(id.toString()),
            tint = tintForId(id),
            fee = json.optInt("fee"),
            alias = alias,
            albumId = albumId,
            artistId = artistId
        )
    }

    private fun commentFrom(json: JSONObject, hot: Boolean, cid: String): Comment {
        val user = json.optJSONObject("user")
        val timestamp = json.optLong("time")
        return Comment(
            id = cid,
            user = user?.optString("nickname").orEmpty().ifBlank { "网易云用户" },
            avatarUrl = httpsUrl(user?.optString("avatarUrl")),
            content = json.optString("content"),
            likedCount = json.optInt("likedCount"),
            timeLabel = formatCommentTime(timestamp),
            hot = hot
        )
    }

    private fun mvFrom(json: JSONObject?): MvItem? {
        if (json == null) return null
        val id = json.optLong("id").takeIf { it > 0L } ?: return null
        val artist = json.optString("artistName").ifBlank {
            json.optJSONObject("artist")?.optString("name").orEmpty().ifBlank {
                json.optString("artist")
            }
        }
        return MvItem(
            id = id.toString(),
            name = json.optString("name").ifBlank { "未知 MV" },
            artist = artist.ifBlank { "未知艺人" },
            coverUrl = httpsUrl(
                json.optString("cover").ifBlank { json.optString("picUrl") }
            ),
            durationMs = json.optLong("duration"),
            playCount = json.optLong("playCount"),
            tint = tintForId(id)
        )
    }

    private fun djProgramFrom(json: JSONObject?): DjProgram? {
        if (json == null) return null
        val id = json.optLong("id").takeIf { it > 0L } ?: return null
        val radio = json.optJSONObject("radio")
        val audio = songFrom(json.optJSONObject("mainSong") ?: json.optJSONObject("song"))
        val radioId = radio?.optLong("id")?.takeIf { it > 0L }?.toString().orEmpty()
        val radioName = radio?.optString("name").orEmpty()
        val djName = radio?.optJSONObject("dj")?.optString("nickname")
            ?: json.optJSONObject("dj")?.optString("nickname").orEmpty()
        val cover = httpsUrl(json.optString("coverUrl").ifBlank { json.optString("cover") })
            ?: httpsUrl(radio?.optString("picUrl"))
            ?: audio?.coverUrl
        return DjProgram(
            id = id.toString(),
            name = json.optString("name").ifBlank { audio?.title ?: "电台节目" },
            radioId = radioId,
            radioName = radioName,
            djName = djName,
            coverUrl = cover,
            durationMs = json.optLong("duration").takeIf { it > 0L } ?: audio?.durationMs ?: 0L,
            listenerCount = json.optLong("listenerCount"),
            description = json.optString("description"),
            createTime = json.optLong("createTime"),
            tint = tintForId(id),
            audio = audio
        )
    }

    /** 评论时间：yyyy-MM-dd，异常时间戳返回空串 */
    private fun formatCommentTime(timestamp: Long): String {
        if (timestamp <= 0L) return ""
        return runCatching {
            java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.CHINA)
                .format(java.util.Date(timestamp))
        }.getOrDefault("")
    }

    private fun artistNames(array: JSONArray?): String {
        if (array == null) return ""
        val names = (0 until array.length()).mapNotNull { index ->
            array.optJSONObject(index)?.optString("name")?.ifBlank { null }
        }
        return names.joinToString(" / ")
    }

    private fun playlistFrom(json: JSONObject?): Playlist? {
        if (json == null) return null
        val id = json.optLong("id")
        if (id <= 0L) return null
        val name = json.optString("name").ifBlank { "精选歌单" }
        val creator = json.optJSONObject("creator")?.optString("nickname").orEmpty()
        val trackCount = json.optInt("trackCount")
        return Playlist(
            id = id.toString(),
            title = name,
            subtitle = creator,
            coverUrl = httpsUrl(json.optString("coverImgUrl")),
            tint = tintForId(id),
            trackCount = trackCount,
            playCount = json.optLong("playCount")
        )
    }

    /** 统一把封面/头像地址升级为 https，避免明文图片被拦截 */
    private fun httpsUrl(url: String?): String? {
        if (url.isNullOrBlank()) return null
        return if (url.startsWith("http://")) "https://" + url.removePrefix("http://") else url
    }

    // MARK: - HTTP

    private fun get(url: String, cookieSink: MutableList<String>? = null): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        connection.requestMethod = "GET"
        connection.setRequestProperty("User-Agent", USER_AGENT)
        connection.setRequestProperty("Referer", "$BASE/")
        connection.setRequestProperty("Accept", "application/json")
        cookie?.takeIf { it.isNotBlank() }?.let {
            connection.setRequestProperty("Cookie", it)
        }
        try {
            val code = connection.responseCode
            if (code !in 200..299) throw IOException("HTTP $code")
            cookieSink?.let { sink ->
                connection.headerFields?.forEach { (name, values) ->
                    if (name.equals("Set-Cookie", ignoreCase = true)) sink.addAll(values)
                }
            }
            return connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }
}

/** 二维码登录会话 */
data class QrCodeLogin(
    val key: String,
    val url: String
)

/** 二维码扫码状态（code 800/801/802/803） */
data class QrLoginResult(
    val code: Int,
    val message: String,
    val cookie: String? = null
)

/** 歌单详情：歌单元信息 + 曲目列表 */
data class PlaylistWithSongs(
    val playlist: Playlist,
    val songs: List<Song>
)