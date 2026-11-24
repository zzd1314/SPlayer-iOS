package com.splayer.next.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.QueueMusic
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.RepeatOne
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.splayer.next.data.AppSettings
import com.splayer.next.data.Song
import com.splayer.next.data.formatDuration
import com.splayer.next.playback.PlayerController
import com.splayer.next.ui.theme.LocalPalette
import kotlinx.coroutines.launch

/**
 * 全屏播放页：经典 / 全封面 / 全歌词三种布局，左右滑动切换。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FullPlayerScreen(onClose: () -> Unit) {
    val song = PlayerController.currentSong
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()
    val pagerState = rememberPagerState(pageCount = { 3 })
    var showQueue by remember { mutableStateOf(false) }
    var showOptions by remember { mutableStateOf(false) }

    if (song == null) {
        Box(
            Modifier
                .fillMaxSize()
                .background(Color(0xFF0B0B0D)),
            contentAlignment = Alignment.Center
        ) {
            Text("暂无播放", color = Color.White.copy(alpha = 0.6f))
        }
        return
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color(0xFF0B0B0D))
    ) {
        PlayerBackdrop(song)

        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
        ) {
            // 顶部栏
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onClose) {
                    Icon(
                        imageVector = Icons.Filled.KeyboardArrowDown,
                        contentDescription = "收起",
                        tint = Color.White,
                        modifier = Modifier.size(26.dp)
                    )
                }
                Column(
                    Modifier.weight(1f),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = "正在播放",
                        color = Color.White,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = listOf(song.album, song.artist)
                            .filter { it.isNotBlank() }
                            .joinToString(" · ")
                            .ifBlank { "SPlayer Next" },
                        color = Color.White.copy(alpha = 0.58f),
                        fontSize = 10.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                IconButton(onClick = { showOptions = true }) {
                    Icon(
                        imageVector = Icons.Filled.MoreHoriz,
                        contentDescription = "更多",
                        tint = Color.White
                    )
                }
            }

            HorizontalPager(
                state = pagerState,
                modifier = Modifier.weight(1f)
            ) { page ->
                when (page) {
                    0 -> ClassicPlayerPage(song)
                    1 -> FullCoverPlayerPage(song)
                    else -> LyricPlayerPage(song)
                }
            }

            // 页码指示
            Row(
                Modifier.fillMaxWidth().padding(top = 2.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                repeat(3) { index ->
                    val active = pagerState.currentPage == index
                    Box(
                        Modifier
                            .padding(horizontal = 3.dp)
                            .size(if (active) 7.dp else 5.dp)
                            .clip(CircleShape)
                            .background(
                                if (active) Color.White else Color.White.copy(alpha = 0.30f)
                            )
                            .clickable {
                                scope.launch { pagerState.animateScrollToPage(index) }
                            }
                    )
                }
            }

            PlayerToolsRow(
                onQueue = { showQueue = true },
                onOptions = { showOptions = true },
                onLyrics = {
                    scope.launch { pagerState.animateScrollToPage(2) }
                }
            )
            Spacer(Modifier.height(10.dp))
        }
    }

    if (showQueue) {
        QueueSheet(onDismiss = { showQueue = false })
    }
    if (showOptions) {
        OptionsSheet(onDismiss = { showOptions = false })
    }
}

// MARK: - 背景

@Composable
private fun PlayerBackdrop(song: Song) {
    Box(Modifier.fillMaxSize()) {
        if (!song.coverUrl.isNullOrBlank()) {
            AsyncImage(
                model = song.coverUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        scaleX = 1.3f
                        scaleY = 1.3f
                    }
                    .blur(46.dp)
            )
        }
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.46f)))
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(
                            song.tint.copy(alpha = 0.42f),
                            Color.Transparent,
                            Color.Black.copy(alpha = 0.72f)
                        )
                    )
                )
        )
    }
}

// MARK: - 经典布局

@Composable
private fun ClassicPlayerPage(song: Song) {
    Column(
        Modifier.fillMaxSize().padding(horizontal = 26.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(Modifier.weight(0.12f))
        CoverBox(
            url = song.coverUrl,
            tint = song.tint,
            modifier = Modifier.fillMaxWidth(0.88f).aspectRatio(1f),
            corner = 26.dp
        )
        Spacer(Modifier.weight(0.10f))

        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    text = song.title,
                    color = Color.White,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.height(3.dp))
                Text(
                    text = listOf(song.artist, song.album)
                        .filter { it.isNotBlank() }
                        .joinToString(" · "),
                    color = Color.White.copy(alpha = 0.60f),
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            IconButton(onClick = { AppSettings.toggleLike(song) }) {
                val liked = AppSettings.isLiked(song.id)
                Icon(
                    imageVector = if (liked) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                    contentDescription = if (liked) "取消喜欢" else "喜欢",
                    tint = if (liked) LocalPalette.current.accent else Color.White.copy(alpha = 0.86f),
                    modifier = Modifier.size(22.dp)
                )
            }
        }

        Spacer(Modifier.height(6.dp))
        PlayerErrorBar()
        PlayerProgressBar(song)
        Spacer(Modifier.height(2.dp))
        PlayerControlsRow()
        Spacer(Modifier.weight(0.10f))
    }
}

// MARK: - 全封面布局

@Composable
private fun FullCoverPlayerPage(song: Song) {
    Box(Modifier.fillMaxSize()) {
        CoverBox(
            url = song.coverUrl,
            tint = song.tint,
            modifier = Modifier
                .fillMaxWidth(0.94f)
                .align(Alignment.Center)
                .aspectRatio(1f),
            corner = 30.dp
        )
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, Color.Black.copy(alpha = 0.72f))
                    )
                )
                .padding(horizontal = 26.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = song.title,
                color = Color.White,
                fontSize = 21.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = song.artist,
                color = Color.White.copy(alpha = 0.62f),
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(12.dp))
            PlayerControlsRow(compact = true)
        }
    }
}

// MARK: - 全歌词布局

@Composable
private fun LyricPlayerPage(song: Song) {
    Column(Modifier.fillMaxSize().padding(horizontal = 26.dp)) {
        Text(
            text = song.title,
            color = Color.White,
            fontSize = 19.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth(),
            textAlign = TextAlign.Center
        )
        Text(
            text = song.artist,
            color = Color.White.copy(alpha = 0.60f),
            fontSize = 12.sp,
            modifier = Modifier.fillMaxWidth(),
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(8.dp))
        LyricsView(Modifier.weight(1f))
        PlayerErrorBar()
        PlayerProgressBar(song, compact = true)
        PlayerControlsRow()
        Spacer(Modifier.height(2.dp))
    }
}

// MARK: - 歌词

@Composable
fun LyricsView(modifier: Modifier = Modifier) {
    val palette = LocalPalette.current
    val lines = PlayerController.lyric.lines
    if (lines.isEmpty()) {
        Box(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Text(
                text = if (PlayerController.isLoadingLyric) "歌词加载中…" else "暂无歌词",
                color = Color.White.copy(alpha = 0.45f),
                fontSize = 13.sp
            )
        }
        return
    }

    val listState = rememberLazyListState()
    val currentIndex = PlayerController.currentLyricIndex
    LaunchedEffect(currentIndex) {
        if (currentIndex >= 0) {
            listState.animateScrollToItem((currentIndex - 2).coerceAtLeast(0))
        }
    }

    val center = AppSettings.lyricAlignCenter
    val scale = AppSettings.lyricFontScale

    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        state = listState,
        contentPadding = PaddingValues(vertical = 40.dp)
    ) {
        items(lines.size) { index ->
            val line = lines[index]
            val active = index == currentIndex
            Column(
                Modifier
                    .fillMaxWidth()
                    .clickable { PlayerController.seekTo(line.timeMs) }
                    .padding(vertical = 7.dp),
                horizontalAlignment = if (center) Alignment.CenterHorizontally else Alignment.Start
            ) {
                Text(
                    text = line.text,
                    color = if (active) palette.accent else Color.White.copy(alpha = 0.46f),
                    fontSize = ((if (active) 19f else 15f) * scale).sp,
                    fontWeight = if (active) FontWeight.Bold else FontWeight.Normal,
                    textAlign = if (center) TextAlign.Center else TextAlign.Start,
                    modifier = Modifier.fillMaxWidth()
                )
                if (AppSettings.showTranslation && !line.translation.isNullOrBlank()) {
                    Text(
                        text = line.translation.orEmpty(),
                        color = if (active) {
                            palette.accent.copy(alpha = 0.78f)
                        } else {
                            Color.White.copy(alpha = 0.34f)
                        },
                        fontSize = ((if (active) 13f else 11f) * scale).sp,
                        textAlign = if (center) TextAlign.Center else TextAlign.Start,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
        }
    }
}

// MARK: - 进度 / 控制

@Composable
private fun PlayerProgressBar(song: Song, compact: Boolean = false) {
    val duration = if (PlayerController.durationMs > 0L) {
        PlayerController.durationMs
    } else {
        song.durationMs
    }
    var dragValue by remember { mutableStateOf<Float?>(null) }
    val position = dragValue?.toLong() ?: PlayerController.positionMs
    val fraction = if (duration > 0L) (position.toFloat() / duration).coerceIn(0f, 1f) else 0f

    Column(Modifier.fillMaxWidth()) {
        Slider(
            value = fraction,
            onValueChange = { value ->
                if (duration > 0L) dragValue = value * duration
            },
            onValueChangeFinished = {
                dragValue?.let { PlayerController.seekTo(it) }
                dragValue = null
            },
            colors = SliderDefaults.colors(
                thumbColor = Color.White,
                activeTrackColor = Color.White,
                inactiveTrackColor = Color.White.copy(alpha = 0.26f)
            ),
            enabled = duration > 0L,
            modifier = Modifier.fillMaxWidth()
        )
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp)) {
            Text(
                text = formatDuration(position),
                color = Color.White.copy(alpha = 0.58f),
                fontSize = if (compact) 9.sp else 10.sp
            )
            Spacer(Modifier.weight(1f))
            Text(
                text = formatDuration(duration),
                color = Color.White.copy(alpha = 0.58f),
                fontSize = if (compact) 9.sp else 10.sp
            )
        }
    }
}

@Composable
private fun PlayerControlsRow(compact: Boolean = false) {
    val palette = LocalPalette.current
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically
    ) {
        IconButton(onClick = { PlayerController.toggleShuffle() }) {
            Icon(
                imageVector = Icons.Filled.Shuffle,
                contentDescription = "随机播放",
                tint = if (PlayerController.shuffle) palette.accent else Color.White.copy(alpha = 0.72f),
                modifier = Modifier.size(20.dp)
            )
        }
        IconButton(onClick = { PlayerController.previous() }) {
            Icon(
                imageVector = Icons.Filled.SkipPrevious,
                contentDescription = "上一首",
                tint = Color.White,
                modifier = Modifier.size(if (compact) 30.dp else 32.dp)
            )
        }
        Box(
            Modifier
                .size(if (compact) 54.dp else 64.dp)
                .clip(CircleShape)
                .background(Color.White)
                .clickable { PlayerController.toggle() },
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = if (PlayerController.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                contentDescription = if (PlayerController.isPlaying) "暂停" else "播放",
                tint = Color(0xFF18181B),
                modifier = Modifier.size(if (compact) 28.dp else 34.dp)
            )
        }
        IconButton(onClick = { PlayerController.next() }) {
            Icon(
                imageVector = Icons.Filled.SkipNext,
                contentDescription = "下一首",
                tint = Color.White,
                modifier = Modifier.size(if (compact) 30.dp else 32.dp)
            )
        }
        IconButton(onClick = { PlayerController.cycleRepeatMode() }) {
            Icon(
                imageVector = when (PlayerController.repeatMode) {
                    2 -> Icons.Filled.RepeatOne
                    1 -> Icons.Filled.Repeat
                    else -> Icons.Filled.Repeat
                },
                contentDescription = "播放模式",
                tint = if (PlayerController.repeatMode != 0) {
                    palette.accent
                } else {
                    Color.White.copy(alpha = 0.72f)
                },
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

@Composable
private fun PlayerToolsRow(
    onQueue: () -> Unit,
    onOptions: () -> Unit,
    onLyrics: () -> Unit
) {
    val palette = LocalPalette.current
    val speed = PlayerController.playbackRate
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 20.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically
    ) {
        ToolItem(Icons.Filled.QueueMusic, "队列", onQueue)
        ToolItem(Icons.Filled.Speed, if (speed == 1f) "倍速" else "${trimRate(speed)}x", onOptions)
        ToolItem(Icons.Filled.Bedtime, PlayerController.sleepLabel ?: "定时", onOptions)
        ToolItem(
            Icons.Filled.GraphicEq,
            if (PlayerController.lyric.lines.isEmpty()) "歌词" else "歌词 ${PlayerController.currentLyricIndex + 1}",
            onLyrics,
            tint = palette.accent
        )
    }
}

@Composable
private fun ToolItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit,
    tint: Color = Color.White.copy(alpha = 0.72f)
) {
    Column(
        Modifier
            .clip(RoundedCornerShape(14.dp))
            .clickable { onClick() }
            .padding(horizontal = 12.dp, vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = icon,
            contentDescription = label,
            tint = tint,
            modifier = Modifier.size(19.dp)
        )
        Spacer(Modifier.height(3.dp))
        Text(text = label, color = tint, fontSize = 9.sp, maxLines = 1)
    }
}

@Composable
private fun PlayerErrorBar() {
    val error = PlayerController.errorText ?: return
    Text(
        text = error,
        color = Color(0xFFFFB4AB),
        fontSize = 10.sp,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(50))
            .background(Color(0x33FF6B6B))
            .clickable { PlayerController.clearError() }
            .padding(horizontal = 10.dp, vertical = 4.dp),
        textAlign = TextAlign.Center
    )
}

private fun trimRate(rate: Float): String {
    return if (rate == rate.toInt().toFloat()) rate.toInt().toString() else rate.toString()
}

// MARK: - 队列面板

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun QueueSheet(onDismiss: () -> Unit) {
    val palette = LocalPalette.current
    val queue = PlayerController.queue
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = palette.panel,
        contentColor = palette.textPrimary
    ) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.72f).padding(horizontal = 18.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "播放队列",
                    color = palette.textPrimary,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    text = "${queue.size} 首",
                    color = palette.textSecondary,
                    fontSize = 11.sp
                )
            }
            Spacer(Modifier.height(10.dp))
            if (queue.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("队列为空", color = palette.textTertiary, fontSize = 13.sp)
                }
            } else {
                LazyColumn(Modifier.weight(1f)) {
                    items(queue.size) { index ->
                        val song = queue[index]
                        val active = index == PlayerController.currentIndex
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(14.dp))
                                .clickable { PlayerController.playAt(index) }
                                .padding(horizontal = 4.dp, vertical = 7.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            SongCover(song.coverUrl, song.tint, 40.dp, 9.dp)
                            Spacer(Modifier.width(10.dp))
                            Column(Modifier.weight(1f)) {
                                Text(
                                    text = song.title,
                                    color = if (active) palette.accent else palette.textPrimary,
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = song.artist,
                                    color = palette.textTertiary,
                                    fontSize = 10.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                            IconButton(
                                onClick = { PlayerController.removeFromQueue(index) },
                                modifier = Modifier.size(32.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Filled.Close,
                                    contentDescription = "移出队列",
                                    tint = palette.textTertiary,
                                    modifier = Modifier.size(15.dp)
                                )
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

// MARK: - 播放选项面板

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OptionsSheet(onDismiss: () -> Unit) {
    val palette = LocalPalette.current
    var volume by remember { mutableStateOf(PlayerController.volume) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = palette.panel,
        contentColor = palette.textPrimary
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(start = 18.dp, end = 18.dp, bottom = 30.dp)
        ) {
            Text(
                text = "播放选项",
                color = palette.textPrimary,
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(16.dp))

            SheetLabel("播放模式")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ChoiceChip("顺序", PlayerController.repeatMode == 0) {
                    PlayerController.setRepeatMode(0)
                }
                ChoiceChip("列表循环", PlayerController.repeatMode == 1) {
                    PlayerController.setRepeatMode(1)
                }
                ChoiceChip("单曲循环", PlayerController.repeatMode == 2) {
                    PlayerController.setRepeatMode(2)
                }
            }

            Spacer(Modifier.height(16.dp))
            SheetLabel("播放速度")
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val rates = listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f)
                items(rates.size) { index ->
                    val rate = rates[index]
                    ChoiceChip(
                        label = if (rate == 1f) "1.0x" else "${trimRate(rate)}x",
                        selected = PlayerController.playbackRate == rate
                    ) {
                        PlayerController.setPlaybackRate(rate)
                    }
                }
            }

            Spacer(Modifier.height(16.dp))
            SheetLabel("睡眠定时")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(15, 30, 60, 90).forEach { minutes ->
                    ChoiceChip("$minutes 分钟", false) {
                        PlayerController.startSleepTimer(minutes)
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ChoiceChip("曲末暂停", PlayerController.sleepAtTrackEnd) {
                    PlayerController.startSleepAtTrackEnd()
                }
                if (PlayerController.sleepTimerActive) {
                    ChoiceChip(
                        "关闭（${PlayerController.sleepLabel ?: ""}）",
                        true
                    ) {
                        PlayerController.cancelSleepTimer()
                    }
                }
            }

            Spacer(Modifier.height(16.dp))
            Text(
                text = "音量 ${(volume * 100).toInt()}%",
                color = palette.textSecondary,
                fontSize = 12.sp
            )
            Slider(
                value = volume,
                onValueChange = { volume = it },
                onValueChangeFinished = { PlayerController.setVolume(volume) },
                colors = SliderDefaults.colors(
                    thumbColor = palette.accent,
                    activeTrackColor = palette.accent,
                    inactiveTrackColor = palette.field
                )
            )

            Spacer(Modifier.height(8.dp))
            TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
                Text("完成", color = palette.accent)
            }
        }
    }
}

@Composable
private fun SheetLabel(text: String) {
    Text(
        text = text,
        color = LocalPalette.current.textSecondary,
        fontSize = 11.sp,
        modifier = Modifier.padding(bottom = 8.dp)
    )
}
