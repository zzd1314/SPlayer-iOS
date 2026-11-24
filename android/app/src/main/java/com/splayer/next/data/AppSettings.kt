package com.splayer.next.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * 全局设置与本地用户数据（SharedPreferences 持久化）。
 * 所有可观察字段用 Compose State 承载，修改即触发界面刷新。
 */
object AppSettings {

    private var prefs: SharedPreferences? = null

    // MARK: - 主题与外观

    /** system / light / dark */
    var themeMode by mutableStateOf("system")
        private set

    /** default / cover / custom */
    var colorSource by mutableStateOf("default")
        private set

    var customColorHex by mutableStateOf("#FE7971")
        private set

    /** glass / classic */
    var uiStyle by mutableStateOf("glass")
        private set

    var followCoverColor by mutableStateOf(true)
        private set

    var keepScreenAwake by mutableStateOf(true)
        private set

    // MARK: - 播放与歌词

    var playbackRate by mutableStateOf(1f)
        private set

    var volume by mutableStateOf(1f)
        private set

    /** 0 顺序 / 1 列表循环 / 2 单曲循环 */
    var repeatMode by mutableStateOf(0)
        private set

    var shuffle by mutableStateOf(false)
        private set

    var showTranslation by mutableStateOf(true)
        private set

    var lyricAlignCenter by mutableStateOf(true)
        private set

    /** 歌词字号倍率 0.8 ~ 1.6 */
    var lyricFontScale by mutableStateOf(1f)
        private set

    // MARK: - 账号

    var cookie by mutableStateOf("")
        private set

    var nickname by mutableStateOf("")
        private set

    var avatarUrl by mutableStateOf("")
        private set

    var userId by mutableStateOf(0L)
        private set

    // MARK: - 本地数据

    var likedSongs by mutableStateOf<List<Song>>(emptyList())
        private set

    var recentSongs by mutableStateOf<List<Song>>(emptyList())
        private set

    var searchHistory by mutableStateOf<List<String>>(emptyList())
        private set

    val isLoggedIn: Boolean get() = cookie.isNotBlank()

    // MARK: - 初始化

    fun init(context: Context) {
        if (prefs != null) return
        val store = context.applicationContext
            .getSharedPreferences("splayer_next_settings", Context.MODE_PRIVATE)
        prefs = store

        themeMode = store.getString("theme_mode", "system") ?: "system"
        colorSource = store.getString("color_source", "default") ?: "default"
        customColorHex = store.getString("custom_color", "#FE7971") ?: "#FE7971"
        uiStyle = store.getString("ui_style", "glass") ?: "glass"
        followCoverColor = store.getBoolean("follow_cover_color", true)
        keepScreenAwake = store.getBoolean("keep_screen_awake", true)

        playbackRate = store.getFloat("playback_rate", 1f)
        volume = store.getFloat("volume", 1f)
        repeatMode = store.getInt("repeat_mode", 0).coerceIn(0, 2)
        shuffle = store.getBoolean("shuffle", false)
        showTranslation = store.getBoolean("show_translation", true)
        lyricAlignCenter = store.getBoolean("lyric_align_center", true)
        lyricFontScale = store.getFloat("lyric_font_scale", 1f).coerceIn(0.8f, 1.6f)

        cookie = store.getString("cookie", "") ?: ""
        nickname = store.getString("nickname", "") ?: ""
        avatarUrl = store.getString("avatar_url", "") ?: ""
        userId = store.getLong("user_id", 0L)

        likedSongs = songsFromJson(store.getString("liked_songs", null))
        recentSongs = songsFromJson(store.getString("recent_songs", null))
        searchHistory = store.getString("search_history", null)
            ?.split("\u0001")
            ?.filter { it.isNotBlank() }
            ?: emptyList()

        NetEaseApi.cookie = cookie
    }

    // MARK: - 主题

    fun setThemeMode(value: String) {
        themeMode = value
        prefs.edit("theme_mode", value)
    }

    fun setColorSource(value: String) {
        colorSource = value
        prefs.edit("color_source", value)
    }

    fun setCustomColor(hex: String) {
        customColorHex = hex
        prefs.edit("custom_color", hex)
    }

    fun setUiStyle(value: String) {
        uiStyle = value
        prefs.edit("ui_style", value)
    }

    fun setFollowCoverColor(value: Boolean) {
        followCoverColor = value
        prefs.edit("follow_cover_color", value)
    }

    fun setKeepScreenAwake(value: Boolean) {
        keepScreenAwake = value
        prefs.edit("keep_screen_awake", value)
    }

    // MARK: - 播放与歌词

    fun setPlaybackRate(value: Float) {
        playbackRate = value
        prefs.edit("playback_rate", value)
    }

    fun setVolume(value: Float) {
        volume = value.coerceIn(0f, 1f)
        prefs.edit("volume", volume)
    }

    fun setRepeatMode(value: Int) {
        repeatMode = value.coerceIn(0, 2)
        prefs.edit("repeat_mode", repeatMode)
    }

    fun setShuffle(value: Boolean) {
        shuffle = value
        prefs.edit("shuffle", value)
    }

    fun setShowTranslation(value: Boolean) {
        showTranslation = value
        prefs.edit("show_translation", value)
    }

    fun setLyricAlignCenter(value: Boolean) {
        lyricAlignCenter = value
        prefs.edit("lyric_align_center", value)
    }

    fun setLyricFontScale(value: Float) {
        lyricFontScale = value.coerceIn(0.8f, 1.6f)
        prefs.edit("lyric_font_scale", lyricFontScale)
    }

    // MARK: - 账号

    fun saveLogin(cookieValue: String, profile: UserProfile?) {
        cookie = cookieValue
        nickname = profile?.nickname ?: ""
        avatarUrl = profile?.avatarUrl ?: ""
        userId = profile?.userId ?: 0L
        prefs?.edit()
            ?.putString("cookie", cookie)
            ?.putString("nickname", nickname)
            ?.putString("avatar_url", avatarUrl)
            ?.putLong("user_id", userId)
            ?.apply()
        NetEaseApi.cookie = cookie
    }

    fun logout() {
        cookie = ""
        nickname = ""
        avatarUrl = ""
        userId = 0L
        prefs?.edit()
            ?.remove("cookie")
            ?.remove("nickname")
            ?.remove("avatar_url")
            ?.remove("user_id")
            ?.apply()
        NetEaseApi.cookie = null
    }

    // MARK: - 收藏 / 最近播放 / 搜索历史

    fun isLiked(songId: String): Boolean = likedSongs.any { it.id == songId }

    fun toggleLike(song: Song) {
        likedSongs = if (isLiked(song.id)) {
            likedSongs.filterNot { it.id == song.id }
        } else {
            listOf(song) + likedSongs.filterNot { it.id == song.id }
        }
        prefs?.edit()?.putString("liked_songs", songsToJson(likedSongs))?.apply()
    }

    fun addRecent(song: Song) {
        if (song.id.isBlank()) return
        recentSongs = (listOf(song) + recentSongs.filterNot { it.id == song.id }).take(100)
        prefs?.edit()?.putString("recent_songs", songsToJson(recentSongs))?.apply()
    }

    fun addSearchHistory(keyword: String) {
        val trimmed = keyword.trim()
        if (trimmed.isBlank()) return
        searchHistory = (listOf(trimmed) + searchHistory.filterNot { it == trimmed }).take(12)
        prefs?.edit()?.putString("search_history", searchHistory.joinToString("\u0001"))?.apply()
    }

    fun clearSearchHistory() {
        searchHistory = emptyList()
        prefs?.edit()?.remove("search_history")?.apply()
    }

    private fun SharedPreferences?.edit(key: String, value: String) {
        this?.edit()?.putString(key, value)?.apply()
    }

    private fun SharedPreferences?.edit(key: String, value: Boolean) {
        this?.edit()?.putBoolean(key, value)?.apply()
    }

    private fun SharedPreferences?.edit(key: String, value: Float) {
        this?.edit()?.putFloat(key, value)?.apply()
    }

    private fun SharedPreferences?.edit(key: String, value: Int) {
        this?.edit()?.putInt(key, value)?.apply()
    }
}
