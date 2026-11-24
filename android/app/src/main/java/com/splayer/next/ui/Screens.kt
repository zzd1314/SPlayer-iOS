package com.splayer.next.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.PlaylistPlay
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Podcasts
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.splayer.next.data.AppSettings
import com.splayer.next.data.ArtistItem
import com.splayer.next.data.DownloadStore
import com.splayer.next.data.LocalMusic
import com.splayer.next.data.MusicRepository
import com.splayer.next.data.MvItem
import com.splayer.next.data.Playlist
import com.splayer.next.data.Song
import com.splayer.next.data.UserProfile
import com.splayer.next.data.formatDuration
import com.splayer.next.data.formatPlayCount
import com.splayer.next.playback.PlayerController
import com.splayer.next.ui.theme.BrandAccent
import com.splayer.next.ui.theme.LocalPalette
import kotlinx.coroutines.launch

// MARK: - 首页

@Composable
fun HomeScreen(
    songs: List<Song>,
    playlists: List<Playlist>,
    loading: Boolean,
    onPlaySong: (List<Song>, Int) -> Unit,
    onOpenPlaylist: (Playlist) -> Unit,
    onOpenPlayer: () -> Unit,
    onOpenLibrary: () -> Unit
) {
    val palette = LocalPalette.current
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            GreetingHeader(songsCount = songs.size, playlistCount = playlists.size)
        }
        item {
            HeroCard(
                song = songs.firstOrNull(),
                count = songs.size,
                onPlay = {
                    songs.firstOrNull()?.let {
                        AppSettings.addSearchHistory("")
                        onPlaySong(songs, 0)
                    }
                },
                onOpenPlayer = onOpenPlayer
            )
        }
        if (AppSettings.recentSongs.isNotEmpty()) {
            item {
                SectionHeader("继续聆听", "全部", onOpenLibrary)
            }
            item {
                LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    contentPadding = PaddingValues(horizontal = 0.dp)
                ) {
                    items(AppSettings.recentSongs.take(8)) { song ->
                        RecentCard(song) {
                            val list = AppSettings.recentSongs
                            onPlaySong(list, list.indexOf(song).coerceAtLeast(0))
                        }
                    }
                }
            }
        }
        item {
            SectionHeader("推荐歌单", "更多", onOpenLibrary)
        }
        item {
            if (loading && playlists.isEmpty()) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(160.dp),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator(color = palette.accent, strokeWidth = 2.dp)
                }
            } else if (playlists.isEmpty()) {
                EmptyHint("暂无推荐歌单", Modifier.height(120.dp))
            } else {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(playlists) { playlist ->
                        PlaylistCard(playlist = playlist, onClick = { onOpenPlaylist(playlist) })
                    }
                }
            }
        }
        item {
            SectionHeader("新歌速递", "全部", onOpenLibrary)
        }
        item {
            if (loading && songs.isEmpty()) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(140.dp),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator(color = palette.accent, strokeWidth = 2.dp)
                }
            } else {
                Column {
                    songs.take(5).forEachIndexed { index, song ->
                        SongRow(
                            song = song,
                            index = index,
                            active = PlayerController.currentSong?.id == song.id,
                            playing = PlayerController.isPlaying,
                            showIndex = false,
                            onClick = { onPlaySong(songs, index) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun GreetingHeader(songsCount: Int, playlistCount: Int) {
    val palette = LocalPalette.current
    Column {
        Text(
            text = greetingText(),
            color = palette.textSecondary,
            fontSize = 13.sp
        )
        Spacer(Modifier.height(4.dp))
        Text(
            text = "今天听点什么",
            color = palette.textPrimary,
            fontSize = 26.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MiniStat("$songsCount 首", "新歌")
            MiniStat("$playlistCount 个", "歌单")
            MiniStat("${AppSettings.likedSongs.size} 首", "收藏")
        }
    }
}

@Composable
private fun MiniStat(value: String, label: String) {
    val palette = LocalPalette.current
    Row(
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(5.dp)
                .background(palette.accent, CircleShape)
        )
        Spacer(Modifier.width(5.dp))
        Text(
            text = "$value $label",
            color = palette.textTertiary,
            fontSize = 11.sp
        )
    }
}

@Composable
private fun HeroCard(
    song: Song?,
    count: Int,
    onPlay: () -> Unit,
    onOpenPlayer: () -> Unit
) {
    val palette = LocalPalette.current
    Panel(
        modifier = Modifier
            .fillMaxWidth()
            .height(196.dp)
            .pressable(onPlay),
        corner = 26.dp
    ) {
        Box(Modifier.fillMaxSize()) {
            if (song != null) {
                CoverBox(
                    url = song.coverUrl,
                    tint = song.tint,
                    modifier = Modifier.fillMaxSize(),
                    corner = 26.dp
                )
            } else {
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(
                            Brush.linearGradient(
                                listOf(BrandAccent.copy(alpha = 0.9f), Color(0xFF7B61FF))
                            )
                        )
                )
            }
            Box(
                Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            listOf(Color.Black.copy(alpha = 0.15f), Color.Black.copy(alpha = 0.75f))
                        )
                    )
            )
            Column(
                Modifier
                    .fillMaxSize()
                    .padding(18.dp),
                verticalArrangement = Arrangement.Bottom
            ) {
                Text(
                    text = "每日推荐",
                    color = Color.White.copy(alpha = 0.75f),
                    fontSize = 12.sp
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    text = song?.title ?: "为你挑选的今日歌单",
                    color = Color.White,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    text = song?.artist ?: "共 $count 首",
                    color = Color.White.copy(alpha = 0.7f),
                    fontSize = 12.sp
                )
                Spacer(Modifier.height(14.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(
                        Modifier
                            .height(38.dp)
                            .clip(CircleShape)
                            .background(Color.White)
                            .pressable(onPlay)
                            .padding(horizontal = 18.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Filled.PlayArrow,
                                contentDescription = null,
                                tint = Color(0xFF18181B),
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(Modifier.width(4.dp))
                            Text(
                                "立即播放",
                                color = Color(0xFF18181B),
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }
                    Box(
                        Modifier
                            .height(38.dp)
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = 0.18f))
                            .pressable(onOpenPlayer)
                            .padding(horizontal = 18.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            "打开播放器",
                            color = Color.White,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RecentCard(song: Song, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Column(
        modifier = Modifier
            .width(108.dp)
            .pressable(onClick)
    ) {
        CoverBox(
            url = song.coverUrl,
            tint = song.tint,
            modifier = Modifier
                .fillMaxWidth()
                .height(108.dp),
            corner = 16.dp
        )
        Spacer(Modifier.height(6.dp))
        Text(
            text = song.title,
            color = palette.textPrimary,
            fontSize = 12.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

private fun greetingText(): String {
    val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
    return when {
        hour < 6 -> "凌晨了，来点轻音乐"
        hour < 12 -> "早上好"
        hour < 14 -> "中午好"
        hour < 18 -> "下午好"
        hour < 22 -> "晚上好"
        else -> "夜深了，注意休息"
    }
}

// MARK: - 发现

@Composable
fun DiscoverScreen(
    playlists: List<Playlist>,
    loading: Boolean,
    onOpenPlaylist: (Playlist) -> Unit,
    onOpenSearch: () -> Unit,
    onOpenMv: (MvItem) -> Unit,
    onOpenMvList: () -> Unit,
    onOpenPodcast: () -> Unit
) {
    val palette = LocalPalette.current
    var tops by remember { mutableStateOf<List<Playlist>>(emptyList()) }
    var loadingTops by remember { mutableStateOf(true) }
    var mvs by remember { mutableStateOf<List<MvItem>>(emptyList()) }

    LaunchedEffect(Unit) {
        tops = MusicRepository.topPlaylists()
        loadingTops = false
        mvs = MusicRepository.topMvs()
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Text(
                text = "发现音乐",
                color = palette.textPrimary,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = "根据你的口味推荐",
                color = palette.textSecondary,
                fontSize = 13.sp
            )
        }
        item {
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(18.dp))
                    .background(palette.field)
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Filled.Search,
                    contentDescription = null,
                    tint = palette.textTertiary,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    text = "搜索歌曲、歌手、歌单",
                    color = palette.textTertiary,
                    fontSize = 13.sp,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    text = "搜索",
                    color = palette.accent,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.pressable(onOpenSearch)
                )
            }
        }
        item {
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(18.dp))
                    .background(palette.field)
                    .pressable(onOpenPodcast)
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    Modifier
                        .size(38.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(palette.accentSoft),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        Icons.Filled.Podcasts,
                        contentDescription = null,
                        tint = palette.accent,
                        modifier = Modifier.size(20.dp)
                    )
                }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        text = "播客电台",
                        color = palette.textPrimary,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "电台节目、有声内容，随时收听",
                        color = palette.textTertiary,
                        fontSize = 11.sp
                    )
                }
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = palette.textTertiary,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
        item {
            SectionHeader("推荐歌单")
        }
        item {
            if (loading && playlists.isEmpty()) {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(4) { _ ->
                        Box(
                            Modifier
                                .width(148.dp)
                                .height(148.dp)
                                .background(palette.field, RoundedCornerShape(18.dp))
                        )
                    }
                }
            } else {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(playlists) { playlist ->
                        PlaylistCard(playlist = playlist, onClick = { onOpenPlaylist(playlist) })
                    }
                }
            }
        }
        item {
            SectionHeader("排行榜")
        }
        if (loadingTops && tops.isEmpty()) {
            item {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(120.dp),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator(color = palette.accent, strokeWidth = 2.dp)
                }
            }
        } else {
            items(tops.chunked(2)) { rowItems ->
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    rowItems.forEach { playlist ->
                        PlaylistCard(
                            playlist = playlist,
                            onClick = { onOpenPlaylist(playlist) },
                            modifier = Modifier.weight(1f),
                            width = null
                        )
                    }
                    if (rowItems.size == 1) {
                        Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
        if (mvs.isNotEmpty()) {
            item { SectionHeader("MV 精选", "查看全部", onOpenMvList) }
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(mvs.take(10)) { mv ->
                        MvCard(
                            mv = mv,
                            onClick = { onOpenMv(mv) },
                            modifier = Modifier.width(178.dp)
                        )
                    }
                }
            }
        }
        item { Spacer(Modifier.height(4.dp)) }
    }
}

// MARK: - 资料库

@Composable
fun LibraryScreen(
    onPlaySong: (List<Song>, Int) -> Unit,
    onOpenPlayer: () -> Unit
) {
    val palette = LocalPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var tab by remember { mutableStateOf(0) }
    var localSongs by remember { mutableStateOf<List<Song>>(emptyList()) }
    var scanning by remember { mutableStateOf(false) }
    var permissionDenied by remember { mutableStateOf(false) }

    val permissionName = if (android.os.Build.VERSION.SDK_INT >= 33) {
        Manifest.permission.READ_MEDIA_AUDIO
    } else {
        Manifest.permission.READ_EXTERNAL_STORAGE
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        permissionDenied = !granted
        if (granted) {
            scanning = true
            scope.launch {
                localSongs = LocalMusic.scan(context)
                scanning = false
            }
        }
    }

    LaunchedEffect(tab) {
        if (tab == 2 && localSongs.isEmpty()) {
            val granted = context.checkSelfPermission(permissionName) == PackageManager.PERMISSION_GRANTED
            if (granted) {
                scanning = true
                localSongs = LocalMusic.scan(context)
                scanning = false
            } else {
                permissionLauncher.launch(permissionName)
            }
        }
    }

    val tabs = listOf("我喜欢", "最近播放", "本地音乐", "已下载")
    val current: List<Song> = when (tab) {
        0 -> AppSettings.likedSongs
        1 -> AppSettings.recentSongs
        2 -> localSongs
        else -> DownloadStore.songs
    }

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal = 20.dp)) {
            Spacer(Modifier.height(8.dp))
            Text(
                text = "资料库",
                color = palette.textPrimary,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                tabs.forEachIndexed { index, label ->
                    ChoiceChip(label, tab == index, { tab = index })
                }
            }
            Spacer(Modifier.height(14.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatBlock(
                    value = AppSettings.likedSongs.size.toString(),
                    label = "收藏",
                    modifier = Modifier.weight(1f)
                )
                StatBlock(
                    value = AppSettings.recentSongs.size.toString(),
                    label = "最近",
                    modifier = Modifier.weight(1f)
                )
                StatBlock(
                    value = DownloadStore.songs.size.toString(),
                    label = "下载",
                    modifier = Modifier.weight(1f)
                )
            }
            Spacer(Modifier.height(12.dp))
        }

        when {
            scanning -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = palette.accent, strokeWidth = 2.dp)
                }
            }

            permissionDenied -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            text = "没有读取本地音乐的权限",
                            color = palette.textSecondary,
                            fontSize = 13.sp
                        )
                        Spacer(Modifier.height(10.dp))
                        Text(
                            text = "重新授权",
                            color = palette.accent,
                            fontSize = 13.sp,
                            modifier = Modifier
                                .clip(CircleShape)
                                .pressable { permissionLauncher.launch(permissionName) }
                                .padding(horizontal = 16.dp, vertical = 8.dp)
                        )
                    }
                }
            }

            current.isEmpty() -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            if (tab == 2) Icons.Filled.CloudDownload else Icons.Filled.MusicNote,
                            contentDescription = null,
                            tint = palette.textTertiary,
                            modifier = Modifier.size(34.dp)
                        )
                        Spacer(Modifier.height(10.dp))
                        Text(
                            text = when (tab) {
                                0 -> "还没有收藏的歌曲"
                                1 -> "还没有播放记录"
                                2 -> "本地音乐为空"
                                else -> "还没有下载的歌曲"
                            },
                            color = palette.textTertiary,
                            fontSize = 13.sp
                        )
                    }
                }
            }

            else -> {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)
                ) {
                    items(current.size) { index ->
                        val song = current[index]
                        SongRow(
                            song = song,
                            index = index,
                            active = PlayerController.currentSong?.id == song.id,
                            playing = PlayerController.isPlaying,
                            onClick = { onPlaySong(current, index) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 搜索

@Composable
fun SearchScreen(
    onPlaySong: (List<Song>, Int) -> Unit,
    onOpenPlaylist: (Playlist) -> Unit,
    onOpenArtist: (ArtistItem) -> Unit
) {
    val palette = LocalPalette.current
    var query by remember { mutableStateOf("") }
    var tab by remember { mutableStateOf(0) }
    var loadToken by remember { mutableStateOf(0) }
    var songs by remember { mutableStateOf<List<Song>>(emptyList()) }
    var playlists by remember { mutableStateOf<List<Playlist>>(emptyList()) }
    var artists by remember { mutableStateOf<List<ArtistItem>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }

    LaunchedEffect(query, tab, loadToken) {
        val keyword = query.trim()
        if (keyword.isBlank()) {
            songs = emptyList()
            playlists = emptyList()
            artists = emptyList()
            loading = false
            return@LaunchedEffect
        }
        loading = true
        kotlinx.coroutines.delay(300)
        when (tab) {
            0 -> songs = MusicRepository.searchSongs(keyword)
            1 -> playlists = MusicRepository.searchPlaylists(keyword)
            else -> artists = MusicRepository.searchArtists(keyword)
        }
        loading = false
    }

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal = 20.dp)) {
            Spacer(Modifier.height(8.dp))
            Text(
                text = "搜索",
                color = palette.textPrimary,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(10.dp))
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(palette.field)
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Filled.Search,
                    contentDescription = null,
                    tint = palette.textTertiary,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(Modifier.width(8.dp))
                androidx.compose.foundation.text.BasicTextField(
                    value = query,
                    onValueChange = { query = it },
                    singleLine = true,
                    textStyle = androidx.compose.ui.text.TextStyle(
                        color = palette.textPrimary,
                        fontSize = 14.sp
                    ),
                    modifier = Modifier.weight(1f),
                    decorationBox = { inner ->
                        if (query.isEmpty()) {
                            Text(
                                text = "搜索歌曲、歌手、歌单",
                                color = palette.textTertiary,
                                fontSize = 14.sp
                            )
                        }
                        inner()
                    }
                )
                if (query.isNotEmpty()) {
                    Text(
                        text = "清除",
                        color = palette.textTertiary,
                        fontSize = 12.sp,
                        modifier = Modifier.pressable {
                            query = ""
                        }
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("单曲", "歌单", "歌手").forEachIndexed { index, label ->
                    ChoiceChip(label, tab == index, { tab = index })
                }
            }
            Spacer(Modifier.height(8.dp))
        }

        val history = AppSettings.searchHistory
        if (query.isBlank()) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp)
            ) {
                if (history.isNotEmpty()) {
                    item {
                        SectionHeader("搜索历史", "清空", {
                            AppSettings.clearSearchHistory()
                            loadToken++
                        })
                    }
                    items(history) { keyword ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .pressable {
                                    AppSettings.addSearchHistory(keyword)
                                    query = keyword
                                }
                                .padding(vertical = 11.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                Icons.Filled.History,
                                contentDescription = null,
                                tint = palette.textTertiary,
                                modifier = Modifier.size(16.dp)
                            )
                            Spacer(Modifier.width(10.dp))
                            Text(
                                text = keyword,
                                color = palette.textSecondary,
                                fontSize = 13.sp,
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                }
                item {
                    Spacer(Modifier.height(8.dp))
                    SectionHeader("热门搜索")
                }
                items(listOf("周杰伦", "林俊杰", "科幻", "华语流行", "Lo-Fi", "轻音乐")) { keyword ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .pressable {
                                AppSettings.addSearchHistory(keyword)
                                query = keyword
                            }
                            .padding(vertical = 11.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = keyword,
                            color = palette.textSecondary,
                            fontSize = 13.sp,
                            modifier = Modifier.weight(1f)
                        )
                        Icon(
                            Icons.AutoMirrored.Filled.KeyboardArrowRight,
                            contentDescription = null,
                            tint = palette.textTertiary,
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }
            }
        } else if (loading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = palette.accent, strokeWidth = 2.dp)
            }
        } else {
            when (tab) {
                0 -> LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)
                ) {
                    if (songs.isEmpty()) {
                        item { EmptyHint("没有找到相关单曲", Modifier.height(160.dp)) }
                    }
                    items(songs.size) { index ->
                        val song = songs[index]
                        SongRow(
                            song = song,
                            index = index,
                            active = PlayerController.currentSong?.id == song.id,
                            playing = PlayerController.isPlaying,
                            onClick = {
                                AppSettings.addSearchHistory(query)
                                onPlaySong(songs, index)
                            }
                        )
                    }
                }

                1 -> LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)
                ) {
                    if (playlists.isEmpty()) {
                        item { EmptyHint("没有找到相关歌单", Modifier.height(160.dp)) }
                    }
                    items(playlists.size) { index ->
                        PlaylistRow(playlists[index], onClick = { onOpenPlaylist(playlists[index]) })
                    }
                }

                else -> LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)
                ) {
                    if (artists.isEmpty()) {
                        item { EmptyHint("没有找到相关歌手", Modifier.height(160.dp)) }
                    }
                    items(artists.size) { index ->
                        ArtistRow(artists[index], onClick = { onOpenArtist(artists[index]) })
                    }
                }
            }
        }
    }
}

@Composable
private fun PlaylistRow(playlist: Playlist, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .pressable(onClick)
            .padding(horizontal = 8.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        CoverBox(
            url = playlist.coverUrl,
            tint = playlist.tint,
            modifier = Modifier.size(52.dp),
            corner = 12.dp
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                text = playlist.title,
                color = palette.textPrimary,
                fontSize = 14.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(3.dp))
            Text(
                text = playlist.subtitleLabel,
                color = palette.textTertiary,
                fontSize = 11.sp
            )
        }
    }
}

@Composable
private fun ArtistRow(artist: ArtistItem, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .pressable(onClick)
            .padding(horizontal = 8.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        CoverBox(
            url = artist.coverUrl,
            tint = artist.tint,
            modifier = Modifier.size(52.dp),
            corner = 26.dp,
            circle = true
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                text = artist.name,
                color = palette.textPrimary,
                fontSize = 14.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(3.dp))
            Text(
                text = artist.subtitle,
                color = palette.textTertiary,
                fontSize = 11.sp
            )
        }
    }
}

// MARK: - 我的

@Composable
fun ProfileScreen(
    onOpenSettings: () -> Unit,
    onOpenLogin: () -> Unit,
    onOpenMyLikes: () -> Unit,
    onOpenRecent: () -> Unit
) {
    val palette = LocalPalette.current
    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp)
    ) {
        Spacer(Modifier.height(8.dp))
        Text(
            text = "我的",
            color = palette.textPrimary,
            fontSize = 26.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(Modifier.height(16.dp))

        Panel(
            modifier = Modifier
                .fillMaxWidth()
                .pressable(if (AppSettings.isLoggedIn) onOpenSettings else onOpenLogin),
            corner = 22.dp
        ) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                CoverBox(
                    url = AppSettings.avatarUrl.ifBlank { null },
                    tint = BrandAccent,
                    modifier = Modifier.size(56.dp),
                    circle = true
                )
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        text = if (AppSettings.isLoggedIn) {
                            AppSettings.nickname.ifBlank { "网易云用户" }
                        } else {
                            "未登录"
                        },
                        color = palette.textPrimary,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = if (AppSettings.isLoggedIn) "已同步网易云账号" else "登录后同步歌单与收藏",
                        color = palette.textSecondary,
                        fontSize = 12.sp
                    )
                }
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = palette.textTertiary,
                    modifier = Modifier.size(20.dp)
                )
            }
        }

        Spacer(Modifier.height(14.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatBlock(
                value = AppSettings.likedSongs.size.toString(),
                label = "我喜欢",
                modifier = Modifier.weight(1f),
                onClick = onOpenMyLikes
            )
            StatBlock(
                value = AppSettings.recentSongs.size.toString(),
                label = "最近播放",
                modifier = Modifier.weight(1f),
                onClick = onOpenRecent
            )
            StatBlock(
                value = if (AppSettings.isLoggedIn) "1" else "0",
                label = "歌单",
                modifier = Modifier.weight(1f)
            )
        }

        Spacer(Modifier.height(18.dp))

        Panel(modifier = Modifier.fillMaxWidth(), corner = 18.dp) {
            Column(Modifier.fillMaxWidth()) {
                MenuRow("外观与主题", AppSettings.themeMode, onOpenSettings)
                MenuDivider()
                MenuRow("播放设置", "", onOpenSettings)
                MenuDivider()
                MenuRow("歌词设置", "", onOpenSettings)
                MenuDivider()
                MenuRow("服务与缓存", "", onOpenSettings)
                MenuDivider()
                MenuRow("关于 SPlayer Next", "", onOpenSettings)
            }
        }

        Spacer(Modifier.height(14.dp))

        Panel(
            modifier = Modifier
                .fillMaxWidth()
                .pressable(onOpenSettings),
            corner = 18.dp
        ) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Filled.Settings,
                    contentDescription = null,
                    tint = palette.textSecondary,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(Modifier.width(10.dp))
                Text(
                    text = "设置",
                    color = palette.textPrimary,
                    fontSize = 14.sp,
                    modifier = Modifier.weight(1f)
                )
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = palette.textTertiary,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
    }
}

@Composable
private fun MenuRow(title: String, value: String, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .pressable(onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            color = palette.textPrimary,
            fontSize = 14.sp,
            modifier = Modifier.weight(1f)
        )
        if (value.isNotBlank()) {
            Text(
                text = when (value) {
                    "system" -> "跟随系统"
                    "light" -> "浅色"
                    "dark" -> "深色"
                    else -> value
                },
                color = palette.textTertiary,
                fontSize = 12.sp
            )
            Spacer(Modifier.width(6.dp))
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = palette.textTertiary,
            modifier = Modifier.size(16.dp)
        )
    }
}

@Composable
private fun MenuDivider() {
    val palette = LocalPalette.current
    Box(
        Modifier
            .fillMaxWidth()
            .padding(start = 16.dp)
            .height(0.6.dp)
            .background(palette.divider)
    )
}

// MARK: - 歌单详情

@Composable
fun PlaylistDetailScreen(
    playlist: Playlist,
    onBack: () -> Unit,
    onPlaySong: (List<Song>, Int) -> Unit
) {
    val palette = LocalPalette.current
    var detail by remember(playlist.id) { mutableStateOf<com.splayer.next.data.PlaylistWithSongs?>(null) }
    var loading by remember(playlist.id) { mutableStateOf(true) }

    LaunchedEffect(playlist.id) {
        detail = MusicRepository.playlistDetail(playlist.id)
        loading = false
    }

    val songs = detail?.songs ?: emptyList()
    val subtitle = detail?.playlist?.subtitle.orEmpty()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 28.dp)
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) {
                    Icon(
                        Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = "返回",
                        tint = palette.textSecondary,
                        modifier = Modifier.size(20.dp)
                    )
                }
                Text(
                    text = "歌单",
                    color = palette.textPrimary,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CoverBox(
                    url = detail?.playlist?.coverUrl ?: playlist.coverUrl,
                    tint = detail?.playlist?.tint ?: playlist.tint,
                    modifier = Modifier.size(132.dp),
                    corner = 20.dp
                )
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        text = detail?.playlist?.title ?: playlist.title,
                        color = palette.textPrimary,
                        fontSize = 19.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        text = subtitle.ifBlank { playlist.subtitleLabel },
                        color = palette.textSecondary,
                        fontSize = 12.sp
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = "${songs.size} 首",
                        color = palette.textTertiary,
                        fontSize = 11.sp
                    )
                }
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                PlayButton(
                    onClick = {
                        if (songs.isNotEmpty()) onPlaySong(songs, 0)
                    }
                )
                Box(
                    Modifier
                        .height(54.dp)
                        .clip(CircleShape)
                        .background(palette.field)
                        .pressable {
                            if (songs.isNotEmpty()) onPlaySong(songs, 0)
                        }
                        .padding(horizontal = 18.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Filled.PlayArrow,
                            contentDescription = null,
                            tint = palette.textPrimary,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(
                            text = "随机播放",
                            color = palette.textPrimary,
                            fontSize = 13.sp
                        )
                    }
                }
            }
        }
        if (loading) {
            item {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(120.dp),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator(color = palette.accent, strokeWidth = 2.dp)
                }
            }
        } else if (songs.isEmpty()) {
            item { EmptyHint("歌单暂无可播放歌曲", Modifier.height(120.dp)) }
        } else {
            items(songs.size) { index ->
                val song = songs[index]
                SongRow(
                    song = song,
                    index = index,
                    active = PlayerController.currentSong?.id == song.id,
                    playing = PlayerController.isPlaying,
                    onClick = { onPlaySong(songs, index) }
                )
            }
        }
    }
}