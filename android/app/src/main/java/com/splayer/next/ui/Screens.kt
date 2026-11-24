package com.splayer.next.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.splayer.next.data.NetEaseApi
import com.splayer.next.data.Playlist
import com.splayer.next.data.SampleData
import com.splayer.next.data.Song
import com.splayer.next.ui.theme.LocalPalette
import com.splayer.next.ui.theme.accentOptions
import kotlinx.coroutines.delay

@Composable
fun HomeScreen(
    glass: Boolean,
    songs: List<Song>,
    playlists: List<Playlist>,
    onPlay: (List<Song>, Int) -> Unit
) {
    val palette = LocalPalette.current
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 6.dp, bottom = 20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            HeroCard {
                if (songs.isNotEmpty()) onPlay(songs, 0)
            }
        }
        item { SectionTitle("最近播放", "查看全部") }
        item {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                items(playlists.size) { index ->
                    PlaylistCard(playlists[index])
                }
            }
        }
        item { SectionTitle("为你推荐", "换一批") }
        items(songs.size) { index ->
            val song = songs[index]
            SongRow(song, glass) { onPlay(songs, index) }
        }
        if (songs.isEmpty()) {
            item {
                Text(
                    text = "暂时没有可播放的歌曲",
                    color = palette.textSecondary,
                    fontSize = 13.sp
                )
            }
        }
    }
}

@Composable
fun LibraryScreen(
    glass: Boolean,
    songs: List<Song>,
    onPlay: (List<Song>, Int) -> Unit
) {
    val palette = LocalPalette.current
    val filters = listOf("全部", "本地", "收藏", "下载", "最近添加")
    var selected by remember { mutableStateOf(0) }
    Column(Modifier.fillMaxSize()) {
        LazyRow(
            contentPadding = PaddingValues(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(filters.size) { index ->
                FilterPill(filters[index], selected == index) { selected = index }
            }
        }
        Spacer(Modifier.height(14.dp))
        LazyColumn(
            modifier = Modifier.fillMaxWidth().weight(1f),
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatChip("歌曲", songs.size.toString(), Modifier.weight(1f), glass)
                    StatChip("歌单", "12", Modifier.weight(1f), glass)
                    StatChip("艺人", "96", Modifier.weight(1f), glass)
                }
            }
            item {
                Text(
                    text = "全部歌曲",
                    color = palette.textPrimary,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(top = 6.dp)
                )
            }
            items(songs.size) { index ->
                val song = songs[index]
                SongRow(song, glass) { onPlay(songs, index) }
            }
        }
    }
}

@Composable
fun DiscoverScreen(glass: Boolean, playlists: List<Playlist>) {
    val palette = LocalPalette.current
    Column(Modifier.fillMaxSize()) {
        Text(
            text = "精选歌单",
            color = palette.textPrimary,
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 6.dp, bottom = 12.dp)
        )
        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            modifier = Modifier.fillMaxWidth().weight(1f),
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            items(playlists.size) { index ->
                DiscoverCard(playlists[index], glass)
            }
        }
    }
}

@Composable
fun SearchScreen(
    query: String,
    glass: Boolean,
    onPlay: (List<Song>, Int) -> Unit
) {
    val palette = LocalPalette.current
    var loading by remember(query) { mutableStateOf(true) }
    var songs by remember(query) { mutableStateOf(emptyList<Song>()) }
    var offline by remember(query) { mutableStateOf(false) }

    LaunchedEffect(query) {
        loading = true
        delay(300)
        val remote = runCatching { NetEaseApi.search(query) }.getOrNull()
        offline = remote.isNullOrEmpty()
        songs = remote?.takeIf { it.isNotEmpty() }
            ?: SampleData.songs.filter {
                it.title.contains(query, ignoreCase = true) ||
                    it.artist.contains(query, ignoreCase = true)
            }
        loading = false
    }

    when {
        loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(
                color = palette.accent,
                strokeWidth = 2.dp,
                modifier = Modifier.size(28.dp)
            )
        }

        songs.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                text = "没有找到与「$query」相关的歌曲",
                color = palette.textSecondary,
                fontSize = 13.sp
            )
        }

        else -> LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 6.dp, bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Text(
                    text = if (offline) "离线结果 · ${songs.size} 首" else "搜索结果 · ${songs.size} 首",
                    color = palette.textSecondary,
                    fontSize = 12.sp,
                    modifier = Modifier.padding(bottom = 2.dp)
                )
            }
            items(songs.size) { index ->
                val song = songs[index]
                SongRow(song, glass) { onPlay(songs, index) }
            }
        }
    }
}

@Composable
fun ProfileScreen(
    glass: Boolean,
    glassMode: Boolean,
    onToggleGlass: () -> Unit,
    dark: Boolean,
    onToggleDark: () -> Unit,
    accentIndex: Int,
    onSelectAccent: (Int) -> Unit
) {
    val palette = LocalPalette.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Panel(glass = glass, modifier = Modifier.fillMaxWidth(), corner = 24.dp) {
            Row(
                Modifier.fillMaxWidth().padding(18.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    Modifier
                        .size(54.dp)
                        .clip(CircleShape)
                        .background(Brush.linearGradient(listOf(palette.accent, Color(0xFF3D7BFF)))),
                    contentAlignment = Alignment.Center
                ) {
                    Text("S", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        text = "本地听众",
                        color = palette.textPrimary,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "登录后同步收藏与歌单",
                        color = palette.textSecondary,
                        fontSize = 12.sp
                    )
                }
                Box(
                    Modifier
                        .clip(RoundedCornerShape(50))
                        .background(palette.textPrimary.copy(alpha = 0.12f))
                        .clickable { }
                        .padding(horizontal = 14.dp, vertical = 7.dp)
                ) {
                    Text("登录", color = palette.textPrimary, fontSize = 13.sp)
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatChip("收藏", "128", Modifier.weight(1f), glass)
            StatChip("歌单", "12", Modifier.weight(1f), glass)
            StatChip("关注", "36", Modifier.weight(1f), glass)
        }
        Text(
            text = "设置",
            color = palette.textPrimary,
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(top = 4.dp)
        )
        Panel(glass = glass, modifier = Modifier.fillMaxWidth(), corner = 22.dp) {
            Column(Modifier.fillMaxWidth()) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("液态玻璃风格", color = palette.textPrimary, fontSize = 14.sp)
                        Text(
                            text = "半透明面板 + 柔光背景",
                            color = palette.textSecondary,
                            fontSize = 11.sp
                        )
                    }
                    Switch(
                        checked = glassMode,
                        onCheckedChange = { onToggleGlass() },
                        colors = switchColors(palette.accent)
                    )
                }
                SettingDivider()
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("深色模式", color = palette.textPrimary, fontSize = 14.sp)
                        Text(
                            text = if (dark) "当前为深色界面" else "当前为浅色界面",
                            color = palette.textSecondary,
                            fontSize = 11.sp
                        )
                    }
                    Switch(
                        checked = dark,
                        onCheckedChange = { onToggleDark() },
                        colors = switchColors(palette.accent)
                    )
                }
                SettingDivider()
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("主题色", color = palette.textPrimary, fontSize = 14.sp)
                        Text(
                            text = accentOptions[accentIndex.coerceIn(0, accentOptions.lastIndex)].label,
                            color = palette.textSecondary,
                            fontSize = 11.sp
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        accentOptions.forEachIndexed { index, option ->
                            Box(
                                Modifier
                                    .size(24.dp)
                                    .clip(CircleShape)
                                    .background(option.color)
                                    .border(
                                        width = 2.dp,
                                        color = if (index == accentIndex) palette.textPrimary else Color.Transparent,
                                        shape = CircleShape
                                    )
                                    .clickable { onSelectAccent(index) }
                            )
                        }
                    }
                }
                SettingDivider()
                SettingRow("播放音质", "自动")
                SettingDivider()
                SettingRow("歌词字号", "标准")
                SettingDivider()
                SettingRow("关于 SPlayer Next", "v0.2.0")
            }
        }
        Spacer(Modifier.height(10.dp))
    }
}

@Composable
private fun switchColors(accent: Color) = SwitchDefaults.colors(
    checkedThumbColor = Color.White,
    checkedTrackColor = accent,
    uncheckedThumbColor = Color(0xFFB9B6C6),
    uncheckedTrackColor = Color(0xFF2A2636)
)

@Composable
private fun SettingDivider() {
    HorizontalDivider(
        color = LocalPalette.current.textPrimary.copy(alpha = 0.06f),
        modifier = Modifier.padding(horizontal = 16.dp)
    )
}

@Composable
private fun HeroCard(onClick: () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(170.dp)
            .clip(RoundedCornerShape(26.dp))
            .background(
                Brush.linearGradient(
                    colors = listOf(Color(0xFFFF6A3D), Color(0xFFFF4FA3), Color(0xFF3D7BFF))
                )
            )
            .pressable(onClick)
    ) {
        Column(
            Modifier.fillMaxSize().padding(20.dp),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Column {
                Text(
                    text = "新歌速递",
                    color = Color.White.copy(alpha = 0.85f),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    text = "网易云推荐 · 立即播放",
                    color = Color.White,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(42.dp).clip(CircleShape).background(Color.White),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Filled.PlayArrow,
                        contentDescription = "播放",
                        tint = Color(0xFFFF4FA3)
                    )
                }
                Spacer(Modifier.width(10.dp))
                Text(
                    text = "点击播放推荐歌曲",
                    color = Color.White.copy(alpha = 0.9f),
                    fontSize = 12.sp
                )
            }
        }
    }
}

@Composable
private fun SectionTitle(title: String, action: String) {
    val palette = LocalPalette.current
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = title,
            color = palette.textPrimary,
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.weight(1f)
        )
        Text(text = action, color = palette.textSecondary, fontSize = 12.sp)
    }
}

@Composable
private fun PlaylistCard(playlist: Playlist) {
    val palette = LocalPalette.current
    Column(Modifier.width(132.dp)) {
        Box(
            Modifier
                .size(132.dp)
                .clip(RoundedCornerShape(20.dp))
                .background(
                    Brush.linearGradient(
                        listOf(playlist.tint.copy(alpha = 0.95f), playlist.tint.copy(alpha = 0.35f))
                    )
                )
        ) {
            Box(
                Modifier
                    .padding(10.dp)
                    .size(30.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.28f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Filled.PlayArrow,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            text = playlist.title,
            color = palette.textPrimary,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = playlist.subtitle,
            color = palette.textSecondary,
            fontSize = 12.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun DiscoverCard(playlist: Playlist, glass: Boolean) {
    val palette = LocalPalette.current
    Panel(glass = glass, modifier = Modifier.fillMaxWidth(), corner = 20.dp) {
        Column(Modifier.fillMaxWidth().padding(12.dp)) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(96.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(
                        Brush.linearGradient(
                            listOf(playlist.tint, playlist.tint.copy(alpha = 0.35f))
                        )
                    )
            )
            Spacer(Modifier.height(10.dp))
            Text(
                text = playlist.title,
                color = palette.textPrimary,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = playlist.subtitle,
                color = palette.textSecondary,
                fontSize = 11.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
fun SongRow(song: Song, glass: Boolean, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Panel(glass = glass, modifier = Modifier.fillMaxWidth().pressable(onClick), corner = 18.dp) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(Brush.linearGradient(listOf(song.tint, song.tint.copy(alpha = 0.3f))))
            )
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    text = song.title,
                    color = palette.textPrimary,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    text = song.artist + " · " + song.album,
                    color = palette.textSecondary,
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Text(text = song.duration, color = palette.textTertiary, fontSize = 12.sp)
        }
    }
}

@Composable
private fun StatChip(label: String, value: String, modifier: Modifier = Modifier, glass: Boolean) {
    val palette = LocalPalette.current
    Panel(glass = glass, modifier = modifier, corner = 18.dp) {
        Column(
            Modifier.fillMaxWidth().padding(vertical = 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(text = value, color = palette.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(2.dp))
            Text(text = label, color = palette.textSecondary, fontSize = 11.sp)
        }
    }
}

@Composable
private fun FilterPill(label: String, selected: Boolean, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Box(
        Modifier
            .clip(RoundedCornerShape(50))
            .background(
                if (selected) palette.accent else palette.textPrimary.copy(alpha = 0.10f)
            )
            .clickable { onClick() }
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        Text(
            text = label,
            color = if (selected) Color.White else palette.textSecondary,
            fontSize = 13.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal
        )
    }
}

@Composable
private fun SettingRow(title: String, value: String) {
    val palette = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .clickable { }
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            color = palette.textPrimary,
            fontSize = 14.sp,
            modifier = Modifier.weight(1f)
        )
        Text(text = value, color = palette.textSecondary, fontSize = 12.sp)
        Spacer(Modifier.width(4.dp))
        Icon(
            imageVector = Icons.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = palette.textTertiary,
            modifier = Modifier.size(16.dp)
        )
    }
}