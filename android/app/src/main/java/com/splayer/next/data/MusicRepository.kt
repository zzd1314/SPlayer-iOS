package com.splayer.next.data

/**
 * 数据仓库：优先请求网易云接口，失败或为空时回退到内置示例数据，
 * 保证无网络 / 接口变更时界面仍然可用。
 */
object MusicRepository {

    suspend fun search(keyword: String): List<Song> {
        val remote = runCatching { NetEaseApi.search(keyword) }.getOrNull()
        if (!remote.isNullOrEmpty()) return remote
        return SampleData.songs.filter {
            it.title.contains(keyword, ignoreCase = true) ||
                it.artist.contains(keyword, ignoreCase = true)
        }
    }

    suspend fun recommendedSongs(): List<Song> =
        runCatching { NetEaseApi.newSongs() }.getOrNull()
            ?.takeIf { it.isNotEmpty() }
            ?: SampleData.songs

    suspend fun recommendedPlaylists(): List<Playlist> =
        runCatching { NetEaseApi.recommendedPlaylists() }.getOrNull()
            ?.takeIf { it.isNotEmpty() }
            ?: SampleData.playlists
}