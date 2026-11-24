package com.splayer.next.data

/**
 * 数据仓库：优先请求网易云接口，失败或为空时回退到内置示例数据，
 * 保证无网络 / 接口变更时界面仍然可用。
 */
object MusicRepository {

    @Volatile
    private var cachedSongs: List<Song>? = null

    @Volatile
    private var cachedPlaylists: List<Playlist>? = null

    @Volatile
    private var cachedToplists: List<Playlist>? = null

    suspend fun newSongs(force: Boolean = false): List<Song> {
        if (!force) cachedSongs?.let { if (it.isNotEmpty()) return it }
        val remote = runCatching { NetEaseApi.newSongs() }.getOrNull()
        val songs = remote?.takeIf { it.isNotEmpty() } ?: SampleData.songs
        cachedSongs = songs
        return songs
    }

    suspend fun recommendedPlaylists(force: Boolean = false): List<Playlist> {
        if (!force) cachedPlaylists?.let { if (it.isNotEmpty()) return it }
        val remote = runCatching { NetEaseApi.recommendedPlaylists() }.getOrNull()
        val playlists = remote?.takeIf { it.isNotEmpty() } ?: SampleData.playlists
        cachedPlaylists = playlists
        return playlists
    }

    suspend fun topPlaylists(): List<Playlist> {
        cachedToplists?.let { if (it.isNotEmpty()) return it }
        val remote = runCatching { NetEaseApi.topPlaylists() }.getOrNull()
        val playlists = remote?.takeIf { it.isNotEmpty() } ?: SampleData.playlists
        cachedToplists = playlists
        return playlists
    }

    suspend fun searchSongs(keyword: String): List<Song> {
        val remote = runCatching { NetEaseApi.searchSongs(keyword) }.getOrNull()
        if (!remote.isNullOrEmpty()) return remote
        return SampleData.songs.filter {
            it.title.contains(keyword, ignoreCase = true) ||
                it.artist.contains(keyword, ignoreCase = true) ||
                it.album.contains(keyword, ignoreCase = true)
        }
    }

    suspend fun searchPlaylists(keyword: String): List<Playlist> =
        runCatching { NetEaseApi.searchPlaylists(keyword) }.getOrDefault(emptyList())

    suspend fun searchArtists(keyword: String): List<ArtistItem> =
        runCatching { NetEaseApi.searchArtists(keyword) }.getOrDefault(emptyList())

    suspend fun playlistDetail(id: String): PlaylistWithSongs? {
        val remote = runCatching { NetEaseApi.playlistDetail(id) }.getOrNull()
        if (remote != null && remote.songs.isNotEmpty()) return remote
        // 演示歌单：返回示例曲目，保证离线可用
        val demo = SampleData.playlists.firstOrNull { it.id == id }
        if (demo != null) return PlaylistWithSongs(demo, SampleData.songs)
        return null
    }

    suspend fun lyric(songId: String): Lyric {
        if (songId.startsWith("demo-") || songId.startsWith("local-")) return Lyric()
        return runCatching { NetEaseApi.lyric(songId) }.getOrDefault(Lyric())
    }

    suspend fun account(): UserProfile? =
        runCatching { NetEaseApi.account() }.getOrNull()
}
