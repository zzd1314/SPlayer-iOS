package com.splayer.next.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.view.WindowManager
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BrightnessAuto
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import com.splayer.next.data.AppSettings
import com.splayer.next.data.ArtistItem
import com.splayer.next.data.CoverColorExtractor
import com.splayer.next.data.MusicRepository
import com.splayer.next.data.MvItem
import com.splayer.next.data.Playlist
import com.splayer.next.data.Song
import com.splayer.next.playback.PlayerController
import com.splayer.next.ui.theme.BrandAccent
import com.splayer.next.ui.theme.LocalPalette
import com.splayer.next.ui.theme.SPlayerTheme
import com.splayer.next.ui.theme.parseHexColor

/** 应用根：决定主题（深浅色 + 主题色），并承载主壳层。 */
@Composable
fun SPlayerApp() {
    val systemDark = isSystemInDarkTheme()
    val dark = when (AppSettings.themeMode) {
        "light" -> false
        "dark" -> true
        else -> systemDark
    }

    var coverColor by remember { mutableStateOf<Color?>(null) }
    val currentSong = PlayerController.currentSong

    LaunchedEffect(currentSong?.id, AppSettings.colorSource) {
        coverColor = if (AppSettings.colorSource == "cover" && currentSong != null) {
            CoverColorExtractor.extract(currentSong.coverUrl)
        } else {
            null
        }
    }

    val accent = when (AppSettings.colorSource) {
        "cover" -> coverColor ?: BrandAccent
        "custom" -> parseHexColor(AppSettings.customColorHex) ?: BrandAccent
        else -> BrandAccent
    }

    SPlayerTheme(dark = dark, accent = accent) {
        AppShell(dark)
    }
}

@Composable
private fun AppShell(dark: Boolean) {
    val context = LocalContext.current
    val activity = context.findActivity()
    val view = LocalView.current

    var tab by remember { mutableStateOf(0) }
    var query by remember { mutableStateOf("") }
    var refreshKey by remember { mutableIntStateOf(0) }
    var songs by remember { mutableStateOf<List<Song>>(emptyList()) }
    var playlists by remember { mutableStateOf<List<Playlist>>(emptyList()) }
    var loadingHome by remember { mutableStateOf(true) }
    var showFullPlayer by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var showLogin by remember { mutableStateOf(false) }
    var detailPlaylist by remember { mutableStateOf<Playlist?>(null) }
    var detailArtist by remember { mutableStateOf<ArtistItem?>(null) }
    var detailAlbum by remember { mutableStateOf<Playlist?>(null) }
    var commentSong by remember { mutableStateOf<Song?>(null) }
    var showMvList by remember { mutableStateOf(false) }
    var playingMv by remember { mutableStateOf<MvItem?>(null) }

    val detailOpen = detailPlaylist != null || detailArtist != null ||
        detailAlbum != null || commentSong != null || showMvList

    // 连接播放服务
    LaunchedEffect(Unit) {
        PlayerController.connect(context)
    }

    // 首页数据
    LaunchedEffect(refreshKey) {
        loadingHome = true
        songs = MusicRepository.newSongs(force = refreshKey > 0)
        playlists = MusicRepository.recommendedPlaylists(force = refreshKey > 0)
        loadingHome = false
    }

    // 状态栏 / 导航栏图标明暗
    LaunchedEffect(dark) {
        val window = activity?.window ?: return@LaunchedEffect
        val controller = WindowCompat.getInsetsController(window, view)
        controller.isAppearanceLightStatusBars = !dark
        controller.isAppearanceLightNavigationBars = !dark
    }

    // 播放时保持屏幕常亮
    LaunchedEffect(AppSettings.keepScreenAwake, PlayerController.isPlaying) {
        val window = activity?.window ?: return@LaunchedEffect
        if (AppSettings.keepScreenAwake && PlayerController.isPlaying) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    Box(Modifier.fillMaxSize()) {
        AppBackground()

        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
        ) {
            if (!detailOpen) {
                TopBar(
                    query = query,
                    onQueryChange = {
                        query = it
                        if (it.isNotBlank() && tab != 3) tab = 3
                    },
                    onOpenSettings = { showSettings = true }
                )
            }

            Box(Modifier.weight(1f)) {
                val detail = detailPlaylist
                val artistDetail = detailArtist
                val albumDetail = detailAlbum
                val comment = commentSong
                when {
                    comment != null -> CommentScreen(
                        song = comment,
                        onBack = { commentSong = null }
                    )

                    albumDetail != null -> AlbumDetailScreen(
                        album = albumDetail,
                        onBack = { detailAlbum = null },
                        onPlaySong = { list, index -> PlayerController.play(list, index) },
                        onOpenArtist = { detailArtist = it }
                    )

                    artistDetail != null -> ArtistDetailScreen(
                        artist = artistDetail,
                        onBack = { detailArtist = null },
                        onPlaySong = { list, index -> PlayerController.play(list, index) },
                        onOpenAlbum = { detailAlbum = it }
                    )

                    showMvList -> MvListScreen(
                        onBack = { showMvList = false },
                        onOpenMv = { playingMv = it }
                    )

                    detail != null -> PlaylistDetailScreen(
                        playlist = detail,
                        onBack = { detailPlaylist = null },
                        onPlaySong = { list, index -> PlayerController.play(list, index) }
                    )

                    tab == 0 -> HomeScreen(
                        songs = songs,
                        playlists = playlists,
                        loading = loadingHome,
                        onPlaySong = { list, index -> PlayerController.play(list, index) },
                        onOpenPlaylist = { detailPlaylist = it },
                        onOpenPlayer = { showFullPlayer = true },
                        onOpenLibrary = { tab = 2 }
                    )

                    tab == 1 -> DiscoverScreen(
                        playlists = playlists,
                        loading = loadingHome,
                        onOpenPlaylist = { detailPlaylist = it },
                        onOpenSearch = { tab = 3 },
                        onOpenMv = { playingMv = it },
                        onOpenMvList = { showMvList = true }
                    )

                    tab == 2 -> LibraryScreen(
                        onPlaySong = { list, index -> PlayerController.play(list, index) },
                        onOpenPlayer = { showFullPlayer = true }
                    )

                    tab == 3 -> SearchScreen(
                        onPlaySong = { list, index -> PlayerController.play(list, index) },
                        onOpenPlaylist = { detailPlaylist = it },
                        onOpenArtist = { detailArtist = it }
                    )

                    else -> ProfileScreen(
                        onOpenSettings = { showSettings = true },
                        onOpenLogin = { showLogin = true },
                        onOpenMyLikes = { tab = 2 },
                        onOpenRecent = { tab = 2 }
                    )
                }
            }

            PlayerBar(onOpen = { showFullPlayer = true })

            BottomNav(
                selected = tab,
                onSelect = {
                    tab = it
                    detailPlaylist = null
                    detailArtist = null
                    detailAlbum = null
                    commentSong = null
                    showMvList = false
                }
            )
        }

        AnimatedVisibility(visible = showFullPlayer) {
            FullPlayerScreen(
                onClose = { showFullPlayer = false },
                onOpenComments = { song ->
                    showFullPlayer = false
                    commentSong = song
                },
                onOpenAlbum = { album ->
                    showFullPlayer = false
                    detailAlbum = album
                }
            )
        }

        val mv = playingMv
        if (mv != null) {
            MvPlayerScreen(mv = mv, onBack = { playingMv = null })
        }

        AnimatedVisibility(visible = showSettings) {
            SettingsScreen(
                onBack = { showSettings = false },
                onOpenLogin = { showLogin = true }
            )
        }

        AnimatedVisibility(visible = showLogin) {
            LoginScreen(onBack = { showLogin = false })
        }
    }
}

// MARK: - 顶栏

@Composable
private fun TopBar(
    query: String,
    onQueryChange: (String) -> Unit,
    onOpenSettings: () -> Unit
) {
    val palette = LocalPalette.current
    Column(Modifier.fillMaxWidth().padding(start = 18.dp, end = 8.dp, top = 4.dp, bottom = 6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(28.dp)
                    .clip(RoundedCornerShape(9.dp))
                    .background(
                        Brush.linearGradient(
                            listOf(palette.accent, palette.accent.copy(alpha = 0.55f))
                        )
                    ),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "S",
                    color = Color.White,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold
                )
            }
            Spacer(Modifier.width(9.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    text = "SPlayer",
                    color = palette.textPrimary,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "Next · Android",
                    color = palette.textTertiary,
                    fontSize = 9.sp
                )
            }
            IconButton(onClick = {
                AppSettings.setThemeMode(
                    when (AppSettings.themeMode) {
                        "system" -> "light"
                        "light" -> "dark"
                        else -> "system"
                    }
                )
            }) {
                Icon(
                    imageVector = when (AppSettings.themeMode) {
                        "light" -> Icons.Filled.LightMode
                        "dark" -> Icons.Filled.DarkMode
                        else -> Icons.Filled.BrightnessAuto
                    },
                    contentDescription = "切换主题",
                    tint = palette.textSecondary,
                    modifier = Modifier.size(20.dp)
                )
            }
            IconButton(onClick = onOpenSettings) {
                Icon(
                    imageVector = Icons.Filled.Settings,
                    contentDescription = "设置",
                    tint = palette.textSecondary,
                    modifier = Modifier.size(20.dp)
                )
            }
        }

        Spacer(Modifier.height(8.dp))

        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(50))
                .background(palette.field)
                .padding(horizontal = 12.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Filled.Search,
                contentDescription = null,
                tint = palette.textTertiary,
                modifier = Modifier.size(17.dp)
            )
            Spacer(Modifier.width(7.dp))
            BasicTextField(
                value = query,
                onValueChange = onQueryChange,
                singleLine = true,
                textStyle = TextStyle(color = palette.textPrimary, fontSize = 13.sp),
                cursorBrush = SolidColor(palette.accent),
                modifier = Modifier.weight(1f),
                decorationBox = { innerTextField ->
                    Box {
                        if (query.isEmpty()) {
                            Text(
                                text = "搜索歌曲、歌手或歌单",
                                color = palette.textTertiary,
                                fontSize = 13.sp
                            )
                        }
                        innerTextField()
                    }
                }
            )
            if (query.isNotEmpty()) {
                Box(
                    Modifier
                        .size(24.dp)
                        .clip(CircleShape)
                        .clickable { onQueryChange("") },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = "清空",
                        tint = palette.textTertiary,
                        modifier = Modifier.size(14.dp)
                    )
                }
            }
        }
    }
}

// MARK: - 播放栏

@Composable
private fun PlayerBar(onOpen: () -> Unit) {
    val song = PlayerController.currentSong ?: return
    val palette = LocalPalette.current
    val duration = if (PlayerController.durationMs > 0L) {
        PlayerController.durationMs
    } else {
        song.durationMs
    }
    val progress = if (duration > 0L) {
        (PlayerController.positionMs.toFloat() / duration).coerceIn(0f, 1f)
    } else {
        0f
    }

    Box(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)) {
        Panel(Modifier.fillMaxWidth().pressable(onOpen), corner = 22.dp) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    SongCover(song.coverUrl, song.tint, 42.dp, 10.dp)
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            text = song.title,
                            color = palette.textPrimary,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = song.artist,
                            color = palette.textSecondary,
                            fontSize = 10.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    IconButton(
                        onClick = { PlayerController.toggle() },
                        modifier = Modifier.size(40.dp)
                    ) {
                        Icon(
                            imageVector = if (PlayerController.isPlaying) {
                                Icons.Filled.Pause
                            } else {
                                Icons.Filled.PlayArrow
                            },
                            contentDescription = if (PlayerController.isPlaying) "暂停" else "播放",
                            tint = palette.textPrimary,
                            modifier = Modifier.size(24.dp)
                        )
                    }
                    IconButton(
                        onClick = { PlayerController.next() },
                        modifier = Modifier.size(40.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Filled.SkipNext,
                            contentDescription = "下一首",
                            tint = palette.textPrimary,
                            modifier = Modifier.size(22.dp)
                        )
                    }
                }
                Spacer(Modifier.height(6.dp))
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(3.dp)
                        .clip(RoundedCornerShape(50))
                        .background(palette.textPrimary.copy(alpha = 0.12f))
                ) {
                    Box(
                        Modifier
                            .fillMaxWidth(progress)
                            .fillMaxHeight()
                            .clip(RoundedCornerShape(50))
                            .background(palette.accent)
                    )
                }
            }
        }
    }
}

// MARK: - 底部导航

private data class NavItem(val label: String, val icon: ImageVector)

@Composable
private fun BottomNav(selected: Int, onSelect: (Int) -> Unit) {
    val palette = LocalPalette.current
    val items = listOf(
        NavItem("首页", Icons.Filled.Home),
        NavItem("发现", Icons.Filled.Explore),
        NavItem("资料库", Icons.Filled.LibraryMusic),
        NavItem("搜索", Icons.Filled.Search),
        NavItem("我的", Icons.Filled.Person)
    )
    Row(
        Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        items.forEachIndexed { index, item ->
            val active = index == selected
            Column(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(14.dp))
                    .clickable { onSelect(index) }
                    .padding(vertical = 5.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(
                    imageVector = item.icon,
                    contentDescription = item.label,
                    tint = if (active) palette.accent else palette.textTertiary,
                    modifier = Modifier.size(21.dp)
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    text = item.label,
                    color = if (active) palette.accent else palette.textTertiary,
                    fontSize = 9.sp,
                    fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal
                )
            }
        }
    }
}

// MARK: - 工具

private fun Context.findActivity(): Activity? {
    var current: Context = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return null
}