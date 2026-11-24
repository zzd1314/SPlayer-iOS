package com.splayer.next.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.splayer.next.ui.theme.Accent
import com.splayer.next.ui.theme.AccentBlue
import com.splayer.next.ui.theme.AccentPink
import com.splayer.next.ui.theme.AccentTeal

/** 液态玻璃面板：半透明白色渐变 + 渐变高光描边 */
@Composable
fun GlassSurface(
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 20.dp,
    content: @Composable BoxScope.() -> Unit
) {
    val shape = RoundedCornerShape(cornerRadius)
    Box(
        modifier = modifier
            .clip(shape)
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        Color.White.copy(alpha = 0.20f),
                        Color.White.copy(alpha = 0.08f)
                    )
                )
            )
            .border(
                width = 0.8.dp,
                brush = Brush.linearGradient(
                    colors = listOf(
                        Color.White.copy(alpha = 0.55f),
                        Color.White.copy(alpha = 0.06f),
                        Color.White.copy(alpha = 0.30f)
                    )
                ),
                shape = shape
            ),
        content = content
    )
}

/** 根据风格开关在玻璃面板与经典深色面板之间切换 */
@Composable
fun Panel(
    glass: Boolean,
    modifier: Modifier = Modifier,
    corner: Dp = 20.dp,
    content: @Composable BoxScope.() -> Unit
) {
    if (glass) {
        GlassSurface(modifier = modifier, cornerRadius = corner, content = content)
    } else {
        val shape = RoundedCornerShape(corner)
        Box(
            modifier = modifier
                .clip(shape)
                .background(Color(0xFF16131F))
                .border(0.8.dp, Color(0x1AFFFFFF), shape),
            content = content
        )
    }
}

/** 深色壁纸式柔光背景，对应 iOS 端液态玻璃底色 */
@Composable
fun GlassBackground(modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(Color(0xFF05060C), Color(0xFF0C0A1A))))
    ) {
        Canvas(Modifier.fillMaxSize()) {
            drawBlob(size.width * 0.10f, size.height * 0.06f, size.minDimension * 0.55f, Accent)
            drawBlob(size.width * 0.96f, size.height * 0.20f, size.minDimension * 0.48f, AccentBlue)
            drawBlob(size.width * 0.88f, size.height * 0.74f, size.minDimension * 0.52f, AccentPink)
            drawBlob(size.width * 0.12f, size.height * 0.94f, size.minDimension * 0.46f, AccentTeal)
        }
    }
}

private fun DrawScope.drawBlob(cx: Float, cy: Float, radius: Float, color: Color) {
    val center = Offset(cx, cy)
    drawCircle(
        brush = Brush.radialGradient(
            colors = listOf(color.copy(alpha = 0.55f), Color.Transparent),
            center = center,
            radius = radius
        ),
        radius = radius,
        center = center
    )
}
