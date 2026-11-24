package com.splayer.next.ui

import androidx.annotation.OptIn
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.PlayArrow
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.splayer.next.data.AlbumDetail
import com.splayer.next.data.ArtistDetail
import com.splayer.next.data.ArtistItem
import com.splayer.next.data.Comment
import com.splayer.next.data.MusicRepository
import com.splayer.next.data.MvItem
import com.splayer.next.data.Playlist
import com.splayer.next.data.Song
import com.splayer.next.data.formatPlayCount
import com.splayer.next.playback.PlayerController
import com.splayer.next.ui.theme.LocalPalette
import com.splayer.next.ui.theme.BrandAccent

// MARK: - 通用返回栏

@Composable
private fun DetailBackBar(title: String, onBack: () -> Unit) {
    val palette = LocalPalette.current
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        IconButton(onClick = onBack) {
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = "返回",
                tint = palette.textSecondary,
                modifier = Modifier.size(20.dp)
            )
        }
        Text(
            text = title,
            color = palette.textPrimary,
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
private fun DetailLoading(height: Int = 120) {
    val palette = LocalPalette.current
    Box(
        Modifier
            .fillMaxWidth()
            .height(height.dp),
        contentAlignment = Alignment.Center
    ) {
        CircularProgressIndicator(color = palette.accent, strokeWidth = 2.dp)
    }
}

// MARK: - 评论页

@Composable
fun CommentScreen(song: Song, onBack: () -> Unit) {
    val palette = LocalPalette.current
    var comments by remember(song.id) { mutableStateOf<List<Comment>>(emptyList()) }
    var loading by remember(song.id) { mutableStateOf(true) }

    LaunchedEffect(song.id) {
        comments = MusicRepository.songComments(song.id)
        loading = false
    }

    val hotComments = comments.filter { it.hot }
    val normalComments = comments.filterNot { it.hot }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 28.dp)
    ) {
        item { DetailBackBar("评论", onBack) }
        item {
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(18.dp))
                    .background(palette.field)
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                CoverBox(
                    url = song.coverUrl,
                    tint = song.tint,
                    modifier = Modifier.size(54.dp),
                    corner = 14.dp
                )
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        text = song.title,
                        color = palette.textPrimary,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Spacer(Modifier.height(3.dp))
                    Text(
                        text = song.artist,
                        color = palette.textTertiary,
                        fontSize = 11.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Text(
                    text = if (loading) "加载中" else "共 ${comments.size} 条",
                    color = palette.textTertiary,
                    fontSize = 11.sp
                )
            }
        }
        item { Spacer(Modifier.height(10.dp)) }

        if (loading) {
            item { DetailLoading() }
        } else if (comments.isEmpty()) {
            item { EmptyHint("暂无评论，快来抢沙发", Modifier.height(140.dp)) }
        } else {
            if (hotComments.isNotEmpty()) {
                item { SectionHeader("精彩评论") }
                items(hotComments.size) { index ->
                    CommentItem(hotComments[index])
                }
            }
            if (normalComments.isNotEmpty()) {
                item { SectionHeader("最新评论") }
                items(normalComments.size) { index ->
                    CommentItem(normalComments[index])
                }
            }
        }
        item { Spacer(Modifier.height(4.dp)) }
    }
}

@Composable
private fun CommentItem(comment: Comment) {
    val palette = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 9.dp)
    ) {
        CoverBox(
            url = comment.avatarUrl,
            tint = BrandAccent,
            modifier = Modifier.size(36.dp),
            corner = 18.dp,
            circle = true
        )
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = comment.user,
                    color = palette.textSecondary,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (comment.timeLabel.isNotBlank()) {
                    Text(
                        text = comment.timeLabel,
                        color = palette.textTertiary,
                        fontSize = 10.sp
                    )
                }
            }
            Spacer(Modifier.height(4.dp))
            Text(
                text = comment.content,
                color = palette.textPrimary,
                fontSize = 13.sp,
                lineHeight = 19.sp
            )
            if (comment.likedCount > 0) {
                Spacer(Modifier.height(4.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Filled.FavoriteBorder,
                        contentDescription = null,
                        tint = palette.textTertiary,
                        modifier = Modifier.size(12.dp)
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = formatPlayCount(comment.likedCount.toLong()),
                        color = palette.textTertiary,
                        fontSize = 10.sp
                    )
                }
            }
        }
    }
}

// MARK: - 歌手详情

@Composable
fun ArtistDetailScreen(
    artist: ArtistItem,
    onBack: () -> Unit,
    onPlaySong: (List<Song>, Int) -> Unit,
    onOpenAlbum: (Playlist) -> Unit
) {
    val palette = LocalPalette.current
    var detail by remember(artist.id) { mutableStateOf<ArtistDetail?>(null) }
    var loading by remember(artist.id) { mutableStateOf(true) }

    LaunchedEffect(artist.id) {
        detail = MusicRepository.artistDetail(artist.id)
        loading = false
    }

    val info = detail?.artist ?: artist
    val songs = detail?.songs ?: emptyList()
    val albums = detail?.albums ?: emptyList()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 28.dp)
    ) {
        item { DetailBackBar("歌手", onBack) }
        item {
            Column(
                Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CoverBox(
                    url = info.coverUrl,
                    tint = info.tint,
                    modifier = Modifier.size(112.dp),
                    corner = 56.dp,
                    circle = true
                )
                Spacer(Modifier.height(10.dp))
                Text(
                    text = info.name,
                    color = palette.textPrimary,
                    fontSize = 21.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    text = info.subtitle,
                    color = palette.textTertiary,
                    fontSize = 11.sp
                )
                val description = detail?.description.orEmpty()
                if (description.isNotBlank()) {
                    Spacer(Modifier.height(8.dp))
                    Text(
                        text = description,
                        color = palette.textSecondary,
                        fontSize = 12.sp,
                        lineHeight = 18.sp,
                        maxLines = 4,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Spacer(Modifier.height(12.dp))
                PlayButton(
                    onClick = { if (songs.isNotEmpty()) onPlaySong(songs, 0) },
                    text = "播放热门"
                )
                Spacer(Modifier.height(14.dp))
            }
        }
        if (albums.isNotEmpty()) {
            item { SectionHeader("专辑") }
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(albums.size) { index ->
                        val album = albums[index]
                        PlaylistCard(
                            playlist = album,
                            onClick = { onOpenAlbum(album) },
                            width = 132.dp
                        )
                    }
                }
            }
            item { Spacer(Modifier.height(10.dp)) }
        }
        item { SectionHeader("热门歌曲") }
        if (loading) {
            item { DetailLoading() }
        } else if (songs.isEmpty()) {
            item { EmptyHint("暂无歌曲", Modifier.height(120.dp)) }
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
        item { Spacer(Modifier.height(4.dp)) }
    }
}

// MARK: - 专辑详情

@Composable
fun AlbumDetailScreen(
    album: Playlist,
    onBack: () -> Unit,
    onPlaySong: (List<Song>, Int) -> Unit,
    onOpenArtist: (ArtistItem) -> Unit
) {
    val palette = LocalPalette.current
    var detail by remember(album.id) { mutableStateOf<AlbumDetail?>(null) }
    var loading by remember(album.id) { mutableStateOf(true) }
    var expanded by remember(album.id) { mutableStateOf(false) }

    LaunchedEffect(album.id) {
        detail = MusicRepository.albumDetail(album.id)
        loading = false
    }

    val info = detail?.album ?: album
    val songs = detail?.songs ?: emptyList()
    val artistName = detail?.artistName.orEmpty().ifBlank { info.subtitle }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 28.dp)
    ) {
        item { DetailBackBar("专辑", onBack) }
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CoverBox(
                    url = info.coverUrl,
                    tint = info.tint,
                    modifier = Modifier.size(132.dp),
                    corner = 20.dp
                )
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        text = info.title,
                        color = palette.textPrimary,
                        fontSize = 19.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis
                    )
                    Spacer(Modifier.height(6.dp))
                    if (artistName.isNotBlank()) {
                        Text(
                            text = artistName,
                            color = palette.accent,
                            fontSize = 12.sp,
                            modifier = Modifier.pressable {
                                val artistId = detail?.artistId
                                if (artistId != null) {
                                    onOpenArtist(
                                        ArtistItem(
                                            id = artistId,
                                            name = artistName,
                                            coverUrl = info.coverUrl,
                                            subtitle = "歌手",
                                            tint = info.tint
                                        )
                                    )
                                }
                            }
                        )
                        Spacer(Modifier.height(4.dp))
                    }
                    Text(
                        text = "${songs.size} 首",
                        color = palette.textTertiary,
                        fontSize = 11.sp
                    )
                }
            }
        }
        item {
            Spacer(Modifier.height(12.dp))
            PlayButton(onClick = { if (songs.isNotEmpty()) onPlaySong(songs, 0) })
        }
        val description = detail?.description.orEmpty()
        if (description.isNotBlank()) {
            item {
                Spacer(Modifier.height(12.dp))
                Text(
                    text = description,
                    color = palette.textSecondary,
                    fontSize = 12.sp,
                    lineHeight = 18.sp,
                    maxLines = if (expanded) Int.MAX_VALUE else 3,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.pressable { expanded = !expanded }
                )
            }
        }
        item { Spacer(Modifier.height(6.dp)) }
        if (loading) {
            item { DetailLoading() }
        } else if (songs.isEmpty()) {
            item { EmptyHint("专辑暂无可播放歌曲", Modifier.height(120.dp)) }
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
        item { Spacer(Modifier.height(4.dp)) }
    }
}

// MARK: - MV 列表

@Composable
fun MvListScreen(
    onBack: () -> Unit,
    onOpenMv: (MvItem) -> Unit
) {
    val palette = LocalPalette.current
    var mvs by remember { mutableStateOf<List<MvItem>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        mvs = MusicRepository.topMvs()
        loading = false
    }

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal = 20.dp)) {
            Spacer(Modifier.height(8.dp))
            DetailBackBar("MV 精选", onBack)
        }
        when {
            loading -> DetailLoading(200)
            mvs.isEmpty() -> EmptyHint("暂无 MV 内容", Modifier.height(200.dp))
            else -> LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                items(mvs.size) { index ->
                    MvCard(mvs[index], onClick = { onOpenMv(mvs[index]) })
                }
            }
        }
    }
}

@Composable
fun MvCard(mv: MvItem, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val palette = LocalPalette.current
    Column(modifier.pressable(onClick)) {
        Box {
            CoverBox(
                url = mv.coverUrl,
                tint = mv.tint,
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(16f / 10f),
                corner = 16.dp
            )
            Box(
                Modifier
                    .align(Alignment.BottomEnd)
                    .padding(8.dp)
                    .size(28.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.42f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Filled.PlayArrow,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(18.dp)
                )
            }
            if (mv.durationMs > 0L) {
                Text(
                    text = mv.durationLabel,
                    color = Color.White,
                    fontSize = 10.sp,
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(8.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color.Black.copy(alpha = 0.42f))
                        .padding(horizontal = 5.dp, vertical = 2.dp)
                )
            }
        }
        Spacer(Modifier.height(7.dp))
        Text(
            text = mv.name,
            color = palette.textPrimary,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Spacer(Modifier.height(2.dp))
        Text(
            text = buildString {
                append(mv.artist)
                if (mv.playCount > 0L) {
                    if (isNotEmpty()) append(" · ")
                    append(mv.playCountLabel).append("播放")
                }
            },
            color = palette.textTertiary,
            fontSize = 10.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

// MARK: - MV 播放

@OptIn(UnstableApi::class)
@Composable
fun MvPlayerScreen(mv: MvItem, onBack: () -> Unit) {
    val context = LocalContext.current
    var playUrl by remember(mv.id) { mutableStateOf<String?>(null) }
    var loading by remember(mv.id) { mutableStateOf(true) }
    var error by remember(mv.id) { mutableStateOf<String?>(null) }
    val exoPlayer = remember(mv.id) { ExoPlayer.Builder(context).build() }

    LaunchedEffect(mv.id) {
        playUrl = MusicRepository.mvUrl(mv.id)
        if (playUrl == null) error = "该 MV 暂无可用播放地址（可能受版权限制）"
        loading = false
    }

    LaunchedEffect(playUrl) {
        val url = playUrl ?: return@LaunchedEffect
        exoPlayer.setMediaItem(MediaItem.fromUri(url))
        exoPlayer.prepare()
        exoPlayer.playWhenReady = true
    }

    DisposableEffect(exoPlayer) {
        val listener = object : Player.Listener {
            override fun onPlayerError(playbackError: PlaybackException) {
                error = "播放失败：${playbackError.errorCodeName}"
            }
        }
        exoPlayer.addListener(listener)
        onDispose {
            exoPlayer.removeListener(listener)
            exoPlayer.release()
        }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    player = exoPlayer
                    useController = true
                }
            },
            modifier = Modifier.fillMaxSize()
        )
        Row(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .background(Color.Black.copy(alpha = 0.35f))
                .padding(horizontal = 6.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = "返回",
                    tint = Color.White,
                    modifier = Modifier.size(22.dp)
                )
            }
            Column(Modifier.weight(1f)) {
                Text(
                    text = mv.name,
                    color = Color.White,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = mv.artist,
                    color = Color.White.copy(alpha = 0.65f),
                    fontSize = 10.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        if (loading) {
            CircularProgressIndicator(
                color = Color.White,
                strokeWidth = 2.dp,
                modifier = Modifier.align(Alignment.Center)
            )
        }
        val message = error
        if (message != null) {
            Text(
                text = message,
                color = Color.White.copy(alpha = 0.8f),
                fontSize = 12.sp,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 90.dp)
                    .clip(RoundedCornerShape(50))
                    .background(Color.White.copy(alpha = 0.12f))
                    .padding(horizontal = 14.dp, vertical = 8.dp)
            )
        }
    }
}