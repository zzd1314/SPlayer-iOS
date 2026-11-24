package com.splayer.next.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import android.graphics.Color as AndroidColor

/** 品牌主色：与桌面端 / iOS 端一致的 #FE7971 */
val BrandAccent = Color(0xFFFE7971)

/** 主题色候选（设置页自选色） */
data class AccentPreset(val label: String, val color: Color)

val accentPresets = listOf(
    AccentPreset("落日粉", Color(0xFFFE7971)),
    AccentPreset("电光蓝", Color(0xFF3D7BFF)),
    AccentPreset("薄荷绿", Color(0xFF24D3C0)),
    AccentPreset("霓虹粉", Color(0xFFFF4FA3)),
    AccentPreset("暮光紫", Color(0xFF8C7BFF)),
    AccentPreset("琥珀金", Color(0xFFF5B942))
)

/**
 * 语义色板：色值对齐桌面端 SOLID_PALETTE_DARK / SOLID_PALETTE_LIGHT（Zinc 色系）。
 * accent 为当前主题色（默认品牌色 / 封面取色 / 自定义色）。
 */
data class AppPalette(
    val dark: Boolean,
    val accent: Color,
    val onAccent: Color,
    val surface: Color,
    val surfaceAlt: Color,
    val panel: Color,
    val panelBright: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val outline: Color,
    val divider: Color
) {
    val accentSoft: Color get() = accent.copy(alpha = if (dark) 0.18f else 0.14f)
    val field: Color get() = textPrimary.copy(alpha = if (dark) 0.07f else 0.05f)
    val panelBorder: Color get() = textPrimary.copy(alpha = if (dark) 0.08f else 0.06f)
}

fun appPalette(dark: Boolean, accent: Color): AppPalette {
    return if (dark) {
        AppPalette(
            dark = true,
            accent = accent,
            onAccent = if (accent.luminance() > 0.55f) Color(0xFF141416) else Color.White,
            surface = Color(0xFF101014),
            surfaceAlt = Color(0xFF16161A),
            panel = Color(0xFF18181C),
            panelBright = Color(0xFF27272A),
            textPrimary = Color(0xFFE4E4E7),
            textSecondary = Color(0xFFA1A1AA),
            textTertiary = Color(0xFF71717A),
            outline = Color(0xFF52525B),
            divider = Color(0xFF2E2E33)
        )
    } else {
        AppPalette(
            dark = false,
            accent = accent,
            onAccent = if (accent.luminance() > 0.55f) Color(0xFF18181B) else Color.White,
            surface = Color(0xFFF6F6F6),
            surfaceAlt = Color(0xFFFAFAFB),
            panel = Color(0xFFFFFFFF),
            panelBright = Color(0xFFFFFFFF),
            textPrimary = Color(0xFF18181B),
            textSecondary = Color(0xFF71717A),
            textTertiary = Color(0xFFA1A1AA),
            outline = Color(0xFFD4D4D8),
            divider = Color(0xFFE4E4E7)
        )
    }
}

val LocalPalette = staticCompositionLocalOf { appPalette(true, BrandAccent) }

@Composable
fun SPlayerTheme(
    dark: Boolean = true,
    accent: Color = BrandAccent,
    content: @Composable () -> Unit
) {
    val palette = appPalette(dark, accent)
    val colorScheme = if (dark) {
        darkColorScheme(
            primary = accent,
            onPrimary = palette.onAccent,
            background = palette.surface,
            onBackground = palette.textPrimary,
            surface = palette.panel,
            onSurface = palette.textPrimary,
            surfaceVariant = palette.surfaceAlt,
            onSurfaceVariant = palette.textSecondary,
            outline = palette.outline,
            outlineVariant = palette.divider
        )
    } else {
        lightColorScheme(
            primary = accent,
            onPrimary = palette.onAccent,
            background = palette.surface,
            onBackground = palette.textPrimary,
            surface = palette.panel,
            onSurface = palette.textPrimary,
            surfaceVariant = palette.surfaceAlt,
            onSurfaceVariant = palette.textSecondary,
            outline = palette.outline,
            outlineVariant = palette.divider
        )
    }
    CompositionLocalProvider(LocalPalette provides palette) {
        MaterialTheme(colorScheme = colorScheme, content = content)
    }
}

/** 解析 "#RRGGBB" / "RRGGBB" / "AARRGGBB" */
fun parseHexColor(hex: String): Color? {
    var value = hex.trim().removePrefix("#")
    if (value.length == 6) value += "FF"
    if (value.length != 8) return null
    val number = value.toLongOrNull(16) ?: return null
    return Color(number.toInt())
}

/** 色相旋转（用于背景光斑与渐变装饰） */
fun Color.shiftHue(degrees: Float, saturationScale: Float = 1f, valueScale: Float = 1f): Color {
    val hsv = FloatArray(3)
    AndroidColor.colorToHSV(this.toArgb(), hsv)
    hsv[0] = (hsv[0] + degrees + 360f) % 360f
    hsv[1] = (hsv[1] * saturationScale).coerceIn(0f, 1f)
    hsv[2] = (hsv[2] * valueScale).coerceIn(0f, 1f)
    return Color(AndroidColor.HSVToColor(hsv))
}
