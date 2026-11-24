package com.splayer.next.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.Coil
import com.splayer.next.data.AppSettings
import com.splayer.next.ui.theme.LocalPalette
import com.splayer.next.ui.theme.accentPresets
import com.splayer.next.ui.theme.parseHexColor

private const val PROJECT_URL = "https://github.com/SPlayer-Dev/SPlayer-Next"
private const val PORT_URL = "https://github.com/zzd1314/SPlayer-iOS"

private enum class SettingsCategory(
    val title: String,
    val subtitle: String,
    val icon: ImageVector
) {
    GENERAL("通用", "更新、搜索历史与语言", Icons.Filled.Tune),
    PLAYBACK("播放", "封面取色、常亮、倍速与音量", Icons.Filled.PlayArrow),
    LYRIC("歌词", "翻译、对齐与字号", Icons.Filled.GraphicEq),
    APPEARANCE("外观", "主题模式、界面风格与主题色", Icons.Filled.Palette),
    SERVICE("服务", "网易云账号与 Cookie", Icons.Filled.AccountCircle),
    CACHE("缓存", "图片与临时文件", Icons.Filled.Delete),
    ABOUT("关于", "版本、协议与开源地址", Icons.Filled.Info)
}

@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    onOpenLogin: () -> Unit
) {
    val palette = LocalPalette.current
    var category by remember { mutableStateOf<SettingsCategory?>(null) }
    val selected = category

    if (selected == null) {
        Column(
            Modifier
                .fillMaxSize()
                .background(palette.surface)
                .statusBarsPadding()
                .navigationBarsPadding()
        ) {
            SettingsHome(onBack = onBack, onSelect = { category = it })
        }
    } else {
        Column(
            Modifier
                .fillMaxSize()
                .background(palette.surface)
                .statusBarsPadding()
                .navigationBarsPadding()
        ) {
            SettingsHeader(title = selected.title, onBack = { category = null })
            CategoryContent(
                category = selected,
                onOpenLogin = onOpenLogin
            )
        }
    }
}

@Composable
private fun SettingsHeader(title: String, onBack: () -> Unit) {
    val palette = LocalPalette.current
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(50))
                .clickable { onBack() },
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = "返回",
                tint = palette.textPrimary,
                modifier = Modifier.size(20.dp)
            )
        }
        Spacer(Modifier.width(4.dp))
        Text(
            text = title,
            color = palette.textPrimary,
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
private fun SettingsHome(onBack: () -> Unit, onSelect: (SettingsCategory) -> Unit) {
    val palette = LocalPalette.current
    Column(Modifier.fillMaxSize()) {
        SettingsHeader(title = "设置", onBack = onBack)
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(start = 18.dp, end = 18.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Panel(Modifier.fillMaxWidth(), corner = 20.dp) {
                Row(
                    Modifier.fillMaxWidth().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        Modifier
                            .size(42.dp)
                            .clip(RoundedCornerShape(14.dp))
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
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            text = "SPlayer Next",
                            color = palette.textPrimary,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = "Android 移植版 v0.5.0",
                            color = palette.textTertiary,
                            fontSize = 11.sp
                        )
                    }
                }
            }

            SettingsCategory.entries.forEach { item ->
                Panel(
                    Modifier.fillMaxWidth().pressable { onSelect(item) },
                    corner = 18.dp
                ) {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            Modifier
                                .size(34.dp)
                                .clip(RoundedCornerShape(10.dp))
                                .background(palette.accentSoft),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = item.icon,
                                contentDescription = null,
                                tint = palette.accent,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(
                                text = item.title,
                                color = palette.textPrimary,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Medium
                            )
                            Text(
                                text = item.subtitle,
                                color = palette.textTertiary,
                                fontSize = 10.sp
                            )
                        }
                        Icon(
                            imageVector = Icons.Filled.KeyboardArrowRight,
                            contentDescription = null,
                            tint = palette.textTertiary,
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CategoryContent(
    category: SettingsCategory,
    onOpenLogin: () -> Unit
) {
    val context = LocalContext.current
    val palette = LocalPalette.current
    var clearedHint by remember { mutableStateOf(false) }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(start = 18.dp, end = 18.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        when (category) {
            SettingsCategory.GENERAL -> {
                SettingsGroup("通用") {
                    SettingRow(
                        title = "检查更新",
                        subtitle = "前往 GitHub 查看最新版本",
                        onClick = { openUrl(context, PROJECT_URL) }
                    )
                    DividerLine()
                    SettingRow(
                        title = "清除搜索历史",
                        subtitle = "${AppSettings.searchHistory.size} 条记录",
                        onClick = { AppSettings.clearSearchHistory() }
                    )
                    DividerLine()
                    SettingRow(
                        title = "语言",
                        subtitle = "简体中文"
                    )
                }
                SettingsGroup("说明") {
                    Text(
                        text = "当前版本为 Android 移植的首个完整播放版本，界面元素与交互对齐 SPlayer Next 桌面端。",
                        color = palette.textSecondary,
                        fontSize = 12.sp,
                        lineHeight = 18.sp,
                        modifier = Modifier.padding(14.dp)
                    )
                }
            }

            SettingsCategory.PLAYBACK -> {
                SettingsGroup("音质") {
                    PickerRow(
                        options = listOf(
                            "标准" to "standard",
                            "HQ 较高" to "higher",
                            "SQ 极高" to "exhigh"
                        ),
                        selected = AppSettings.audioQuality,
                        onSelect = { AppSettings.setAudioQuality(it) }
                    )
                    DividerLine()
                    Text(
                        text = "高音质需要登录账号且曲目版权支持；解析失败时会自动回退标准音质。",
                        color = palette.textTertiary,
                        fontSize = 11.sp,
                        lineHeight = 17.sp,
                        modifier = Modifier.padding(14.dp)
                    )
                }
                SettingsGroup("播放") {
                    SettingSwitchRow(
                        title = "封面取色",
                        subtitle = "播放页跟随封面主色",
                        checked = AppSettings.followCoverColor,
                        onCheckedChange = { AppSettings.setFollowCoverColor(it) }
                    )
                    DividerLine()
                    SettingSwitchRow(
                        title = "保持屏幕常亮",
                        subtitle = "播放时阻止屏幕自动熄灭",
                        checked = AppSettings.keepScreenAwake,
                        onCheckedChange = { AppSettings.setKeepScreenAwake(it) }
                    )
                    DividerLine()
                    SliderRow(
                        title = "播放速度",
                        valueLabel = "${trimValue(AppSettings.playbackRate)}x",
                        value = AppSettings.playbackRate,
                        range = 0.5f..2f,
                        steps = 2,
                        onValueChange = { AppSettings.setPlaybackRate(it) }
                    )
                    DividerLine()
                    SliderRow(
                        title = "应用内音量",
                        valueLabel = "${(AppSettings.volume * 100).toInt()}%",
                        value = AppSettings.volume,
                        range = 0f..1f,
                        steps = 9,
                        onValueChange = { AppSettings.setVolume(it) }
                    )
                }
            }

            SettingsCategory.LYRIC -> {
                SettingsGroup("歌词") {
                    SettingSwitchRow(
                        title = "显示翻译",
                        subtitle = "双语歌词优先展示译文",
                        checked = AppSettings.showTranslation,
                        onCheckedChange = { AppSettings.setShowTranslation(it) }
                    )
                    DividerLine()
                    SettingSwitchRow(
                        title = "居中对齐",
                        subtitle = "关闭后使用左对齐",
                        checked = AppSettings.lyricAlignCenter,
                        onCheckedChange = { AppSettings.setLyricAlignCenter(it) }
                    )
                    DividerLine()
                    SliderRow(
                        title = "歌词字号",
                        valueLabel = "${(AppSettings.lyricFontScale * 100).toInt()}%",
                        value = AppSettings.lyricFontScale,
                        range = 0.8f..1.6f,
                        steps = 7,
                        onValueChange = { AppSettings.setLyricFontScale(it) }
                    )
                }
            }

            SettingsCategory.APPEARANCE -> {
                SettingsGroup("主题模式") {
                    PickerRow(
                        options = listOf("跟随系统" to "system", "浅色" to "light", "深色" to "dark"),
                        selected = AppSettings.themeMode,
                        onSelect = { AppSettings.setThemeMode(it) }
                    )
                }
                SettingsGroup("界面风格") {
                    PickerRow(
                        options = listOf("液态玻璃" to "glass", "经典" to "classic"),
                        selected = AppSettings.uiStyle,
                        onSelect = { AppSettings.setUiStyle(it) }
                    )
                }
                SettingsGroup("主题色来源") {
                    PickerRow(
                        options = listOf("默认" to "default", "跟随封面" to "cover", "自定义" to "custom"),
                        selected = AppSettings.colorSource,
                        onSelect = { AppSettings.setColorSource(it) }
                    )
                    if (AppSettings.colorSource == "custom") {
                        Spacer(Modifier.height(12.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            accentPresets.forEach { preset ->
                                val isSelected = preset.color == parseHexColor(AppSettings.customColorHex)
                                Box(
                                    Modifier
                                        .size(30.dp)
                                        .clip(CircleShape)
                                        .background(preset.color)
                                        .then(
                                            if (isSelected) {
                                                Modifier.border(2.dp, palette.textPrimary, CircleShape)
                                            } else {
                                                Modifier
                                            }
                                        )
                                        .clickable {
                                            val argb = 0xFFFFFF and preset.color.toArgb()
                                            AppSettings.setCustomColor("#%06X".format(argb))
                                        }
                                )
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                        Text(
                            text = "当前：${AppSettings.customColorHex}",
                            color = palette.textTertiary,
                            fontSize = 10.sp
                        )
                    }
                }
                SettingsGroup("背景") {
                    Text(
                        text = "液态玻璃风格会叠加跟随主题色的柔光背景；自定义背景图将在后续版本开放。",
                        color = palette.textSecondary,
                        fontSize = 12.sp,
                        lineHeight = 18.sp,
                        modifier = Modifier.padding(14.dp)
                    )
                }
            }

            SettingsCategory.SERVICE -> {
                SettingsGroup("网易云账号") {
                    SettingRow(
                        title = if (AppSettings.isLoggedIn) {
                            AppSettings.nickname.ifBlank { "已登录" }
                        } else {
                            "未登录"
                        },
                        subtitle = if (AppSettings.isLoggedIn) {
                            "UID ${AppSettings.userId} · Cookie 已保存"
                        } else {
                            "登录后可同步收藏、歌单与每日推荐"
                        },
                        onClick = onOpenLogin
                    )
                    DividerLine()
                    SettingRow(
                        title = "Cookie 登录",
                        subtitle = "粘贴 MUSIC_U 或完整 Cookie",
                        onClick = onOpenLogin
                    )
                    if (AppSettings.isLoggedIn) {
                        DividerLine()
                        SettingRow(
                            title = "退出登录",
                            subtitle = "清除本地登录信息",
                            onClick = { AppSettings.logout() }
                        )
                    }
                }
                SettingsGroup("API") {
                    Text(
                        text = "数据来自网易云音乐公开 Web 接口，未登录时部分接口可能受限；播放地址由官方外链提供，VIP 曲目可能无法播放。",
                        color = palette.textSecondary,
                        fontSize = 12.sp,
                        lineHeight = 18.sp,
                        modifier = Modifier.padding(14.dp)
                    )
                }
            }

            SettingsCategory.CACHE -> {
                SettingsGroup("图片缓存") {
                    SettingRow(
                        title = "清除图片缓存",
                        subtitle = if (clearedHint) "已清除" else "封面与头像缓存",
                        onClick = {
                            runCatching {
                                val loader = Coil.imageLoader(context)
                                loader.memoryCache?.clear()
                                loader.diskCache?.clear()
                            }
                            clearedHint = true
                        }
                    )
                    DividerLine()
                    SettingRow(
                        title = "清除搜索历史",
                        subtitle = "${AppSettings.searchHistory.size} 条记录",
                        onClick = {
                            AppSettings.clearSearchHistory()
                            clearedHint = true
                        }
                    )
                }
            }

            SettingsCategory.ABOUT -> {
                SettingsGroup("版本信息") {
                    SettingRow(title = "版本", subtitle = "0.5.0 (versionCode 5)")
                    DividerLine()
                    SettingRow(title = "开源协议", subtitle = "AGPL-3.0")
                }
                SettingsGroup("开源地址") {
                    SettingRow(
                        title = "SPlayer Next 原项目",
                        subtitle = "SPlayer-Dev/SPlayer-Next",
                        onClick = { openUrl(context, PROJECT_URL) }
                    )
                    DividerLine()
                    SettingRow(
                        title = "Android 移植仓库",
                        subtitle = "zzd1314/SPlayer-iOS",
                        onClick = { openUrl(context, PORT_URL) }
                    )
                }
                SettingsGroup("署名") {
                    Text(
                        text = "本项目是 SPlayer Next 的 Android 移植，遵循 AGPL-3.0 协议，保留原项目署名与链接。感谢原作者与社区的开源贡献。",
                        color = palette.textSecondary,
                        fontSize = 12.sp,
                        lineHeight = 18.sp,
                        modifier = Modifier.padding(14.dp)
                    )
                }
            }
        }
        Spacer(Modifier.height(10.dp))
    }
}

// MARK: - 设置组件

@Composable
private fun SettingsGroup(title: String, content: @Composable () -> Unit) {
    Column {
        Text(
            text = title,
            color = LocalPalette.current.textSecondary,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.padding(start = 6.dp, bottom = 7.dp)
        )
        Panel(Modifier.fillMaxWidth(), corner = 18.dp) {
            Column(Modifier.fillMaxWidth()) {
                content()
            }
        }
    }
}

@Composable
private fun SettingRow(
    title: String,
    subtitle: String = "",
    onClick: (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null
) {
    val palette = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable { onClick() } else Modifier)
            .padding(horizontal = 14.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                text = title,
                color = palette.textPrimary,
                fontSize = 14.sp
            )
            if (subtitle.isNotBlank()) {
                Text(
                    text = subtitle,
                    color = palette.textTertiary,
                    fontSize = 10.sp
                )
            }
        }
        if (trailing != null) {
            trailing()
        } else if (onClick != null) {
            Icon(
                imageVector = Icons.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = palette.textTertiary,
                modifier = Modifier.size(16.dp)
            )
        }
    }
}

@Composable
private fun SettingSwitchRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    val palette = LocalPalette.current
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(text = title, color = palette.textPrimary, fontSize = 14.sp)
            if (subtitle.isNotBlank()) {
                Text(text = subtitle, color = palette.textTertiary, fontSize = 10.sp)
            }
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = palette.accent,
                uncheckedThumbColor = palette.textSecondary,
                uncheckedTrackColor = palette.field
            )
        )
    }
}

@Composable
private fun SliderRow(
    title: String,
    valueLabel: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    steps: Int,
    onValueChange: (Float) -> Unit
) {
    val palette = LocalPalette.current
    var localValue by remember(value) { mutableStateOf(value) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(text = title, color = palette.textPrimary, fontSize = 14.sp, modifier = Modifier.weight(1f))
            Text(text = valueLabel, color = palette.textTertiary, fontSize = 11.sp)
        }
        Slider(
            value = localValue,
            onValueChange = { localValue = it },
            onValueChangeFinished = { onValueChange(localValue) },
            valueRange = range,
            steps = steps,
            colors = SliderDefaults.colors(
                thumbColor = palette.accent,
                activeTrackColor = palette.accent,
                inactiveTrackColor = palette.field
            )
        )
    }
}

@Composable
private fun PickerRow(
    options: List<Pair<String, String>>,
    selected: String,
    onSelect: (String) -> Unit
) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 13.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        options.forEach { (label, value) ->
            ChoiceChip(label, selected == value) { onSelect(value) }
        }
    }
}

@Composable
private fun DividerLine() {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp)
            .height(0.6.dp)
            .background(LocalPalette.current.divider)
    )
}

private fun openUrl(context: Context, url: String) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }
}

private fun trimValue(value: Float): String {
    return if (value == value.toInt().toFloat()) value.toInt().toString() else value.toString()
}