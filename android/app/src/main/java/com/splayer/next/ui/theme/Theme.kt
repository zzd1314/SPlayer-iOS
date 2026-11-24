package com.splayer.next.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

val Accent = Color(0xFFFF6A3D)
val AccentBlue = Color(0xFF3D7BFF)
val AccentPink = Color(0xFFFF4FA3)
val AccentTeal = Color(0xFF24D3C0)

data class AccentOption(val label: String, val color: Color)

val accentOptions = listOf(
    AccentOption("落日橙", Accent),
    AccentOption("电光蓝", AccentBlue),
    AccentOption("霓虹粉", AccentPink),
    AccentOption("薄荷绿", AccentTeal)
)

/** 界面语义色板：深浅色主题共用一套字段，避免各页面散落硬编码颜色 */
data class PlayerPalette(
    val dark: Boolean,
    val accent: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val panelSolid: Color,
    val backgroundTop: Color,
    val backgroundBottom: Color
)

private val DarkPalette = PlayerPalette(
    dark = true,
    accent = Accent,
    textPrimary = Color(0xFFF5F4F8),
    textSecondary = Color(0xFF9E9AAD),
    textTertiary = Color(0xFF77738A),
    panelSolid = Color(0xFF16131F),
    backgroundTop = Color(0xFF05060C),
    backgroundBottom = Color(0xFF0C0A1A)
)

private val LightPalette = PlayerPalette(
    dark = false,
    accent = Accent,
    textPrimary = Color(0xFF191722),
    textSecondary = Color(0xFF5C5770),
    textTertiary = Color(0xFF8A8699),
    panelSolid = Color(0xFFFDFCFF),
    backgroundTop = Color(0xFFF7F5FC),
    backgroundBottom = Color(0xFFE7E3F3)
)

val LocalPalette = staticCompositionLocalOf { DarkPalette }

@Composable
fun SPlayerTheme(
    dark: Boolean = true,
    accent: Color = Accent,
    content: @Composable () -> Unit
) {
    val palette = (if (dark) DarkPalette else LightPalette).copy(accent = accent)
    val colorScheme = if (dark) {
        darkColorScheme(
            primary = accent,
            onPrimary = Color.White,
            secondary = AccentBlue,
            onSecondary = Color.White,
            background = DarkPalette.backgroundTop,
            onBackground = DarkPalette.textPrimary,
            surface = DarkPalette.backgroundBottom,
            onSurface = DarkPalette.textPrimary,
            surfaceVariant = DarkPalette.panelSolid,
            onSurfaceVariant = DarkPalette.textSecondary,
            outline = Color(0x33FFFFFF)
        )
    } else {
        lightColorScheme(
            primary = accent,
            onPrimary = Color.White,
            secondary = AccentBlue,
            onSecondary = Color.White,
            background = LightPalette.backgroundTop,
            onBackground = LightPalette.textPrimary,
            surface = LightPalette.panelSolid,
            onSurface = LightPalette.textPrimary,
            surfaceVariant = Color(0xFFEFECF7),
            onSurfaceVariant = LightPalette.textSecondary,
            outline = Color(0x1F000000)
        )
    }
    CompositionLocalProvider(LocalPalette provides palette) {
        MaterialTheme(colorScheme = colorScheme, content = content)
    }
}