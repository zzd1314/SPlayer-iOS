package com.splayer.next.ui

import android.content.Context
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
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import com.splayer.next.data.Song

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
    var glassMode by remember { mutableStateOf(prefs.getBoolean("glass_mode", true)) }
    var selectedTab by remember { mutableStateOf(0) }
    var query by remember { mutableStateOf("") }
    var currentSong by remember { mutableStateOf<Song?>(null) }
    var playing by remember { mutableStateOf(false) }

    Box(Modifier.fillMaxSize()) {
        GlassBackground()
        Column(Modifier.fillMaxSize().statusBarsPadding()) {
            TopBar(
                title = tabTitles[selectedTab],
                query = query,
                onQueryChange = { query = it },
                glassMode = glassMode,
                onToggleGlass = {
                    glassMode = !glassMode
                    prefs.edit().putBoolean("glass_mode", glassMode).apply()
                }
            )
            Box(Modifier.weight(1f).fillMaxWidth()) {
                when (selectedTab) {
                    0 -> HomeScreen(glass = glassMode, onPlay = {
                        currentSong = it
                        playing = true
                    })
                    1 -> LibraryScreen(glass = glassMode, onPlay = {
                        currentSong = it
                        playing = true
                    })
                    2 -> DiscoverScreen(glass = glassMode)
                    else -> ProfileScreen(
                        glass = glassMode,
                        glassMode = glassMode,
                        onToggleGlass = {
                            glassMode = !glassMode
                            prefs.edit().putBoolean("glass_mode", glassMode).apply()
                        }
                    )
                }
            }
            currentSong?.let { song ->
                PlayerBar(
                    song = song,
                    playing = playing,
                    glass = glassMode,
                    onToggle = { playing = !playing }
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
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    text = "SPLAYER NEXT",
                    color = Color(0xFF8A8699),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = title,
                    color = Color.White,
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Bold
                )
            }
            Box(
                Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(Color.White.copy(alpha = 0.10f))
                    .clickable { onToggleGlass() },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = if (glassMode) Icons.Filled.BlurOn else Icons.Filled.Contrast,
                    contentDescription = "切换界面风格",
                    tint = Color.White,
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
                    tint = Color(0xFF9E9AAD),
                    modifier = Modifier.size(18.dp)
                )
                Spacer(Modifier.width(8.dp))
                Box(Modifier.weight(1f)) {
                    if (query.isEmpty()) {
                        Text("搜索歌曲、歌手、专辑", color = Color(0xFF77738A), fontSize = 13.sp)
                    }
                    BasicTextField(
                        value = query,
                        onValueChange = onQueryChange,
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyMedium.copy(color = Color.White),
                        cursorBrush = SolidColor(Color(0xFFFF6A3D)),
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
    glass: Boolean,
    onToggle: () -> Unit
) {
    Panel(
        glass = glass,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp),
        corner = 20.dp
    ) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
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
                    color = Color.White,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = song.artist,
                    color = Color(0xFF9E9AAD),
                    fontSize = 11.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            IconButton(onClick = onToggle) {
                Icon(
                    imageVector = if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    contentDescription = "播放/暂停",
                    tint = Color.White
                )
            }
            IconButton(onClick = { }) {
                Icon(
                    imageVector = Icons.Filled.SkipNext,
                    contentDescription = "下一首",
                    tint = Color.White
                )
            }
        }
    }
}

@Composable
private fun BottomNav(selected: Int, onSelect: (Int) -> Unit) {
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
                    tint = if (active) Color(0xFFFF6A3D) else Color(0xFF8A8699),
                    modifier = Modifier.size(22.dp)
                )
                Spacer(Modifier.height(3.dp))
                Text(
                    text = item.label,
                    color = if (active) Color(0xFFFF6A3D) else Color(0xFF8A8699),
                    fontSize = 11.sp,
                    fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal
                )
            }
        }
    }
}
