package com.splayer.next.ui

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BlurOn
import androidx.compose.material.icons.filled.Contrast
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.splayer.next.data.MusicRepository
import com.splayer.next.data.Playlist
import com.splayer.next.data.SampleData
import com.splayer.next.data.Song
import com.splayer.next.playback.PlayerController
import com.splayer.next.ui.theme.LocalPalette
import com.splayer.next.ui.theme.SPlayerTheme
import com.splayer.next.ui.theme.accentOptions

private val tabTitles = listOf("首页", "曲库", "发现", "我的")

private data class NavItem(val label: String, val icon: ImageVector)

private val navItems = listOf(
    NavItem("首页", Icons.Filled.Home),
    NavItem("曲库", Icons.Filled.LibraryMusic),
    NavItem("发现", Icons.Filled.Explore),
    NavItem("我的", Icons.Filled.Person)
)

@Composable
fun SPlayerApp() {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("splayer_next", Context.MODE_PRIVATE) }
    var dark by remember { mutableStateOf(prefs.getBoolean("dark_mode", true)) }
    var accentIndex by remember {
        mutableStateOf(prefs.getInt("accent_index", 0).coerceIn(0, accentOptions.lastIndex))
    }

    SPlayerTheme(dark = dark, accent = accentOptions[accentIndex].color) {
        AppContent(
            prefs = prefs,
            dark = dark,
            accentIndex = accentIndex,
            onToggleDark = {
                dark = !dark
                prefs.edit().putBoolean("dark_mode", dark).apply()
            },
            onSelectAccent = { index ->
                accentIndex = index.coerceIn(0, accentOptions.lastIndex)
                prefs.edit().putInt("accent_index", accentIndex).apply()
            }
        )
    }
}

@Composable
private fun AppContent(
    prefs: SharedPreferences,
    dark: Boolean,
    accentIndex: Int,
    onToggleDark: () -> Unit,
    onSelectAccent: (Int) -> Unit
) {
    val context = LocalContext.current
    var glassMode by remember { mutableStateOf(prefs.getBoolean("glass_mode", true)) }
    var selectedTab by remember { mutableStateOf(0) }
    var query by remember { mutableStateOf("") }
    var homeSongs by remember { mutableStateOf(SampleData.songs) }
    var playlists by remember { mutableStateOf(SampleData.playlists) }

    val toggleGlass: () -> Unit = {
        glassMode = !glassMode
        prefs.edit().putBoolean("glass_mode", glassMode).apply()
    }

    LaunchedEffect(Unit) {
        PlayerController.connect(context)
        homeSongs = MusicRepository.recommendedSongs()
        playlists = MusicRepository.recommendedPlaylists()
    }

    Box(Modifier.fillMaxSize()) {
        GlassBackground()
        Column(Modifier.fillMaxSize().statusBarsPadding()) {
            TopBar(
                title = tabTitles[selectedTab],
                query = query,
                onQueryChange = { query = it },
                glassMode = glassMode,
                onToggleGlass = toggleGlass
            )
            Box(Modifier.weight(1f).fillMaxWidth()) {
                if (query.isNotBlank()) {
                    SearchScreen(query = query, glass = glassMode) { songs, index ->
                        PlayerController.play(songs, index)
                    }
                } else {
                    AnimatedContent(
                        targetState = selectedTab,
                        transitionSpec = {
                            fadeIn(tween(220)) togetherWith fadeOut(tween(160))
                        },
                        label = "tabContent"
                    ) { tab ->
                        when (tab) {
                            0 -> HomeScreen(glassMode, homeSongs, playlists) { songs, index ->
                                PlayerController.play(songs, index)
                            }

                            1 -> LibraryScreen(glassMode, homeSongs) { songs, index ->
                                PlayerController.play(songs, index)
                            }

                            2 -> DiscoverScreen(glassMode, playlists)

                            else -> ProfileScreen(
                                glass = glassMode,
                                glassMode = glassMode,
                                onToggleGlass = toggleGlass,
                                dark = dark,
                                onToggleDark = onToggleDark,
                                accentIndex = accentIndex,
                                onSelectAccent = onSelectAccent
                            )
                        }
                    }
                }
            }
            PlayerController.currentSong?.let { song ->
                PlayerBar(
                    song = song,
                    playing = PlayerController.isPlaying,
                    positionMs = PlayerController.positionMs,
                    durationMs = PlayerController.durationMs,
                    glass = glassMode,
                    onToggle = { PlayerController.toggle() },
                    onPrevious = { PlayerController.previous() },
                    onNext = { PlayerController.next() },
                    onSeek = { PlayerController.seekTo(it) }
                )
            }
            BottomNav(selected = selectedTab, onSelect = { selectedTab = it })
        }
    }
}

@Composable
private fun TopBar(
    title: String,
    query: String,
    onQueryChange: (String) -> Unit,
    glassMode: Boolean,
    onToggleGlass: () -> Unit
) {
    val palette = LocalPalette.current
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    text = "SPLAYER NEXT",
                    color = palette.textTertiary,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = title,
                    color = palette.textPrimary,
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Bold
                )
            }
            Box(
                Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(palette.textPrimary.copy(alpha = 0.10f))
                    .clickable { onToggleGlass() },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = if (glassMode) Icons.Filled.BlurOn else Icons.Filled.Contrast,
                    contentDescription = "切换界面风格",
                    tint = palette.textPrimary,
                    modifier = Modifier.size(20.dp)
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        Panel(glass = glassMode, modifier = Modifier.fillMaxWidth().height(42.dp), corner = 21.dp) {
            Row(
                Modifier.fillMaxSize().padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Filled.Search,
                    contentDescription = null,
                    tint = palette.textSecondary,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(Modifier.width(8.dp))
                Box(Modifier.weight(1f)) {
                    if (query.isEmpty()) {
                        Text("搜索歌曲、歌手、专辑", color = palette.textTertiary, fontSize = 13.sp)
                    }
                    BasicTextField(
                        value = query,
                        onValueChange = onQueryChange,
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyMedium.copy(color = palette.textPrimary),
                        cursorBrush = SolidColor(palette.accent),
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
        }
    }
}

@Composable
private fun PlayerBar(
    song: Song,
    playing: Boolean,
    positionMs: Long,
    durationMs: Long,
    glass: Boolean,
    onToggle: () -> Unit,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onSeek: (Long) -> Unit
) {
    val palette = LocalPalette.current
    var dragValue by remember(song.id) { mutableStateOf<Float?>(null) }
    val total = if (durationMs > 0L) durationMs else parseDurationMs(song.duration)
    val progress = if (total > 0L) (positionMs.toFloat() / total).coerceIn(0f, 1f) else 0f
    val displayPosition = if (dragValue != null && total > 0L) {
        (dragValue!! * total).toLong()
    } else {
        positionMs
    }

    Panel(
        glass = glass,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp),
        corner = 20.dp
    ) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(40.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(Brush.linearGradient(listOf(song.tint, song.tint.copy(alpha = 0.3f))))
                )
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        text = song.title,
                        color = palette.textPrimary,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = song.artist,
                        color = palette.textSecondary,
                        fontSize = 11.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                IconButton(onClick = onPrevious) {
                    Icon(
                        imageVector = Icons.Filled.SkipPrevious,
                        contentDescription = "上一首",
                        tint = palette.textPrimary
                    )
                }
                IconButton(onClick = onToggle) {
                    Icon(
                        imageVector = if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        contentDescription = "播放/暂停",
                        tint = palette.textPrimary
                    )
                }
                IconButton(onClick = onNext) {
                    Icon(
                        imageVector = Icons.Filled.SkipNext,
                        contentDescription = "下一首",
                        tint = palette.textPrimary
                    )
                }
            }
            Slider(
                value = dragValue ?: progress,
                onValueChange = { dragValue = it },
                onValueChangeFinished = {
                    val target = dragValue
                    if (target != null && total > 0L) {
                        onSeek((target * total).toLong())
                    }
                    dragValue = null
                },
                modifier = Modifier.fillMaxWidth()
            )
            Row(Modifier.fillMaxWidth()) {
                Text(
                    text = formatTime(displayPosition),
                    color = palette.textTertiary,
                    fontSize = 10.sp,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    text = formatTime(total),
                    color = palette.textTertiary,
                    fontSize = 10.sp
                )
            }
        }
    }
}

@Composable
private fun BottomNav(selected: Int, onSelect: (Int) -> Unit) {
    val palette = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        navItems.forEachIndexed { index, item ->
            val active = index == selected
            Column(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(16.dp))
                    .clickable { onSelect(index) }
                    .padding(vertical = 6.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(
                    imageVector = item.icon,
                    contentDescription = item.label,
                    tint = if (active) palette.accent else palette.textSecondary,
                    modifier = Modifier.size(22.dp)
                )
                Spacer(Modifier.height(3.dp))
                Text(
                    text = item.label,
                    color = if (active) palette.accent else palette.textSecondary,
                    fontSize = 11.sp,
                    fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal
                )
            }
        }
    }
}

private fun formatTime(millis: Long): String {
    val totalSeconds = (millis.coerceAtLeast(0L)) / 1000
    return "%d:%02d".format(totalSeconds / 60, totalSeconds % 60)
}

private fun parseDurationMs(duration: String): Long {
    val parts = duration.split(":")
    if (parts.size != 2) return 0L
    val minutes = parts[0].toLongOrNull() ?: return 0L
    val seconds = parts[1].toLongOrNull() ?: return 0L
    return (minutes * 60 + seconds) * 1000
}