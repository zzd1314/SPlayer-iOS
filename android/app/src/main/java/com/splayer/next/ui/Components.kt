package com.splayer.next.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.splayer.next.data.AppSettings
import com.splayer.next.data.Playlist
import com.splayer.next.data.Song
import com.splayer.next.data.formatDuration
import com.splayer.next.ui.theme.LocalPalette

/** 封面块（占位渐变 + 网络封面） */
@Composable
fun CoverBox(
    url: String?,
    tint: Color,
    modifier: Modifier = Modifier,
    corner: Dp = 16.dp,
    circle: Boolean = false
) {
    val shape = if (circle) CircleShape else RoundedCornerShape(corner)
    Box(
        modifier
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(tint.copy(alpha = 0.95f), tint.copy(alpha = 0.42f))
                )
            )
    ) {
        if (!url.isNullOrBlank()) {
            androidx.compose.foundation.layout.Box(Modifier.fillMaxSize()) {
                coil.compose.AsyncImage(
                    model = url,
                    contentDescription = null,
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
            }
        }
    }
}

/** 区块标题 + 右侧动作 */
@Composable
fun SectionHeader(
    title: String,
    action: String? = null,
    onAction: (() -> Unit)? = null
) {
    val palette = LocalPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            color = palette.textPrimary,
            fontSize = 19.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.weight(1f)
        )
        if (action != null && onAction != null) {
            Text(
                text = action,
                color = palette.textSecondary,
                fontSize = 13.sp,
                modifier = Modifier.pressable(onAction)
            )
        }
    }
}

/** 胶囊选择器 */
@Composable
fun ChoiceChip(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val palette = LocalPalette.current
    Box(
        modifier = modifier
            .clip(CircleShape)
            .background(if (selected) palette.accent else palette.panel)
            .border(
                width = 1.dp,
                color = if (selected) Color.Transparent else palette.panelBorder,
                shape = CircleShape
            )
            .pressable(onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        Text(
            text = text,
            color = if (selected) palette.onAccent else palette.textSecondary,
            fontSize = 13.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal
        )
    }
}

/** 数据块（资料库 / 我的页） */
@Composable
fun StatBlock(
    value: String,
    label: String,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null
) {
    val palette = LocalPalette.current
    var boxModifier = modifier
    if (onClick != null) boxModifier = boxModifier.pressable(onClick)
    Column(
        modifier = boxModifier
            .clip(RoundedCornerShape(16.dp))
            .background(palette.field)
            .padding(vertical = 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = value,
            color = palette.textPrimary,
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(Modifier.height(3.dp))
        Text(text = label, color = palette.textTertiary, fontSize = 11.sp)
    }
}

/** 歌曲行 */
@Composable
fun SongRow(
    song: Song,
    index: Int,
    active: Boolean,
    playing: Boolean,
    showIndex: Boolean = true,
    onClick: () -> Unit
) {
    val palette = LocalPalette.current
    val liked = AppSettings.isLiked(song.id)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .pressable(onClick)
            .padding(horizontal = 8.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (showIndex) {
            Box(
                Modifier.width(24.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = if (active) "\u266a" else "${index + 1}".padStart(2, '0'),
                    color = if (active) palette.accent else palette.textTertiary,
                    fontSize = 12.sp
                )
            }
            Spacer(Modifier.width(8.dp))
        }
        CoverBox(
            url = song.coverUrl,
            tint = song.tint,
            modifier = Modifier.size(46.dp),
            corner = 12.dp
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                text = song.title,
                color = if (active) palette.accent else palette.textPrimary,
                fontSize = 14.sp,
                fontWeight = if (active) FontWeight.SemiBold else FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(3.dp))
            Text(
                text = buildString {
                    append(song.artist)
                    if (song.album.isNotBlank()) append(" \u00b7 ").append(song.album)
                },
                color = palette.textTertiary,
                fontSize = 11.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Spacer(Modifier.width(8.dp))
        Text(
            text = song.durationLabel,
            color = palette.textTertiary,
            fontSize = 11.sp
        )
        Icon(
            imageVector = if (liked) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
            contentDescription = "收藏",
            tint = if (liked) palette.accent else palette.textTertiary,
            modifier = Modifier
                .padding(start = 10.dp)
                .size(18.dp)
                .pressable { AppSettings.toggleLike(song) }
        )
    }
}

/** 歌单卡片 */
@Composable
fun PlaylistCard(
    playlist: Playlist,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    width: Dp? = 148.dp
) {
    val palette = LocalPalette.current
    Column(
        modifier = modifier
            .then(if (width != null) Modifier.width(width) else Modifier.fillMaxWidth())
            .pressable(onClick)
    ) {
        CoverBox(
            url = playlist.coverUrl,
            tint = playlist.tint,
            modifier = if (width != null) {
                Modifier
                    .fillMaxWidth()
                    .height(width)
            } else {
                Modifier
                    .fillMaxWidth()
                    .aspectRatio(1f)
            },
            corner = 18.dp
        )
        Spacer(Modifier.height(8.dp))
        Text(
            text = playlist.title,
            color = palette.textPrimary,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
        Spacer(Modifier.height(2.dp))
        Text(
            text = playlist.subtitleLabel,
            color = palette.textTertiary,
            fontSize = 11.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

/** 主播放按钮 */
@Composable
fun PlayButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 54.dp,
    text: String = "播放全部"
) {
    val palette = LocalPalette.current
    Box(
        modifier = modifier
            .height(size)
            .clip(CircleShape)
            .background(palette.accent)
            .pressable(onClick)
            .padding(horizontal = 22.dp),
        contentAlignment = Alignment.Center
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = Icons.Filled.PlayArrow,
                contentDescription = null,
                tint = palette.onAccent,
                modifier = Modifier.size(20.dp)
            )
            Spacer(Modifier.width(6.dp))
            Text(
                text = text,
                color = palette.onAccent,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}

/** 空状态提示 */
@Composable
fun EmptyHint(text: String, modifier: Modifier = Modifier) {
    val palette = LocalPalette.current
    Box(
        modifier = modifier.fillMaxWidth(),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = text,
            color = palette.textTertiary,
            fontSize = 13.sp,
            textAlign = TextAlign.Center
        )
    }
}
