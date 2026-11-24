package com.splayer.next.ui

import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.splayer.next.data.DjProgram
import com.splayer.next.data.DjRadio
import com.splayer.next.data.DjRadioDetail
import com.splayer.next.data.MusicRepository
import com.splayer.next.data.Song
import com.splayer.next.ui.theme.LocalPalette

/**
 * 播客页：推荐节目 + 热门电台。
 * 点击节目直接进入播放队列，点击电台进入节目列表。
 */
@Composable
fun PodcastScreen(
    onBack: () -> Unit,
    onOpenRadio: (DjRadio) -> Unit,
    onPlayPrograms: (List<Song>, Int) -> Unit
) {
    val palette = LocalPalette.current
    var programs by remember { mutableStateOf<List<DjProgram>>(emptyList()) }
    var radios by remember { mutableStateOf<List<DjRadio>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        radios = MusicRepository.djRadios()
        programs = MusicRepository.djPrograms()
        loading = false
    }

    val songs = remember(programs) { programs.map { it.toSong() } }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item { PodcastBackBar("播客", onBack) }
        item {
            Text(
                text = "播客电台",
                color = palette.textPrimary,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = "电台节目、有声内容，随时收听",
                color = palette.textSecondary,
                fontSize = 13.sp
            )
        }
        if (loading) {
            item {
                Box(Modifier.fillMaxWidth().height(140.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = palette.accent, strokeWidth = 2.dp)
                }
            }
            return@LazyColumn
        }
        if (radios.isNotEmpty()) {
            item { SectionHeader("热门电台") }
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(radios) { radio ->
                        RadioCard(radio = radio, onClick = { onOpenRadio(radio) })
                    }
                }
            }
        }
        item { SectionHeader("推荐节目") }
        if (programs.isEmpty()) {
            item { EmptyHint("暂无推荐节目，请稍后重试") }
        } else {
            itemsIndexed(programs) { index, program ->
                ProgramRow(program = program) { onPlayPrograms(songs, index) }
            }
        }
        item { Spacer(Modifier.height(4.dp)) }
    }
}

/** 电台详情页：电台信息 + 节目列表 */
@Composable
fun PodcastRadioScreen(
    radio: DjRadio,
    onBack: () -> Unit,
    onPlayPrograms: (List<Song>, Int) -> Unit
) {
    val palette = LocalPalette.current
    var detail by remember(radio.id) { mutableStateOf<DjRadioDetail?>(null) }
    var loading by remember(radio.id) { mutableStateOf(true) }

    LaunchedEffect(radio.id) {
        detail = MusicRepository.djRadioDetail(radio.id) ?: DjRadioDetail(radio)
        loading = false
    }

    val info = detail?.radio ?: radio
    val programs = detail?.programs ?: emptyList()
    val songs = remember(programs) { programs.map { it.toSong() } }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item { PodcastBackBar(info.name.ifBlank { "电台详情" }, onBack) }
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CoverBox(
                    url = info.coverUrl,
                    tint = info.tint,
                    modifier = Modifier.size(92.dp),
                    corner = 20.dp
                )
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        text = info.name,
                        color = palette.textPrimary,
                        fontSize = 19.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = buildString {
                            if (info.djName.isNotBlank()) append(info.djName)
                            if (info.programCount > 0) {
                                if (isNotEmpty()) append(" · ")
                                append("${info.programCount} 集")
                            }
                        }.ifBlank { "播客电台" },
                        color = palette.textSecondary,
                        fontSize = 12.sp
                    )
                    if (info.subscriberCount > 0L) {
                        Spacer(Modifier.height(3.dp))
                        Text(
                            text = info.subscriberLabel,
                            color = palette.textTertiary,
                            fontSize = 11.sp
                        )
                    }
                }
            }
        }
        if (info.description.isNotBlank()) {
            item {
                Text(
                    text = info.description,
                    color = palette.textSecondary,
                    fontSize = 12.sp,
                    lineHeight = 18.sp,
                    maxLines = 4,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        item { SectionHeader("节目列表") }
        if (loading) {
            item {
                Box(Modifier.fillMaxWidth().height(120.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = palette.accent, strokeWidth = 2.dp)
                }
            }
        } else if (programs.isEmpty()) {
            item { EmptyHint("该电台暂无节目") }
        } else {
            itemsIndexed(programs) { index, program ->
                ProgramRow(program = program) { onPlayPrograms(songs, index) }
            }
        }
        item { Spacer(Modifier.height(4.dp)) }
    }
}

// MARK: - 组件

@Composable
private fun PodcastBackBar(title: String, onBack: () -> Unit) {
    val palette = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable { onBack() }
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = "返回",
            tint = palette.textSecondary,
            modifier = Modifier.size(20.dp)
        )
        Text(
            text = title,
            color = palette.textPrimary,
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun ProgramRow(program: DjProgram, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .pressable(onClick)
            .padding(horizontal = 6.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        CoverBox(
            url = program.coverUrl,
            tint = program.tint,
            modifier = Modifier.size(54.dp),
            corner = 14.dp
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                text = program.name,
                color = palette.textPrimary,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = buildString {
                    val owner = program.djName.ifBlank { program.radioName }
                    if (owner.isNotBlank()) append(owner)
                    if (program.durationMs > 0L) {
                        if (isNotEmpty()) append(" · ")
                        append(program.durationLabel)
                    }
                }.ifBlank { "电台节目" },
                color = palette.textTertiary,
                fontSize = 11.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Spacer(Modifier.width(8.dp))
        Box(
            Modifier
                .size(34.dp)
                .clip(CircleShape)
                .background(
                    Brush.linearGradient(
                        listOf(palette.accent, palette.accent.copy(alpha = 0.7f))
                    )
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.Filled.PlayArrow,
                contentDescription = "播放",
                tint = palette.onAccent,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

@Composable
private fun RadioCard(radio: DjRadio, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Column(
        Modifier
            .width(132.dp)
            .clip(RoundedCornerShape(16.dp))
            .pressable(onClick)
    ) {
        CoverBox(
            url = radio.coverUrl,
            tint = radio.tint,
            modifier = Modifier.fillMaxWidth().height(118.dp),
            corner = 16.dp
        )
        Spacer(Modifier.height(7.dp))
        Text(
            text = radio.name,
            color = palette.textPrimary,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = radio.djName.ifBlank { radio.subscriberLabel },
            color = palette.textTertiary,
            fontSize = 10.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}