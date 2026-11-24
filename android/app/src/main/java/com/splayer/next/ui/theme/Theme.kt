package com.splayer.next.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val Accent = Color(0xFFFF6A3D)
val AccentBlue = Color(0xFF3D7BFF)
val AccentPink = Color(0xFFFF4FA3)
val AccentTeal = Color(0xFF24D3C0)

private val SPlayerColors = darkColorScheme(
    primary = Accent,
    onPrimary = Color.White,
    secondary = AccentBlue,
    onSecondary = Color.White,
    background = Color(0xFF05060C),
    onBackground = Color(0xFFF2F2F5),
    surface = Color(0xFF0C0A1A),
    onSurface = Color(0xFFF2F2F5),
    surfaceVariant = Color(0xFF16131F),
    onSurfaceVariant = Color(0xFFB9B6C6),
    outline = Color(0x33FFFFFF)
)

@Composable
fun SPlayerTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = SPlayerColors, content = content)
}
