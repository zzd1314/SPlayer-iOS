package com.splayer.next.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.splayer.next.data.AppSettings
import com.splayer.next.ui.theme.LocalPalette
import com.splayer.next.ui.theme.shiftHue

/** 液态玻璃面板：半透明白色渐变 + 高光描边 */
@Composable
fun GlassSurface(
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 20.dp,
    content: @Composable BoxScope.() -> Unit
) {
    val palette = LocalPalette.current
    val shape = RoundedCornerShape(cornerRadius)
    val topAlpha = if (palette.dark) 0.14f else 0.72f
    val bottomAlpha = if (palette.dark) 0.05f else 0.42f
    val borderColors = if (palette.dark) {
        listOf(
            Color.White.copy(alpha = 0.30f),
            Color.White.copy(alpha = 0.04f),
            Color.White.copy(alpha = 0.16f)
        )
    } else {
        listOf(
            Color.White.copy(alpha = 0.95f),
            Color.Black.copy(alpha = 0.04f),
            Color.White.copy(alpha = 0.70f)
        )
    }
    Box(
        modifier = modifier
            .clip(shape)
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        Color.White.copy(alpha = topAlpha),
                        Color.White.copy(alpha = bottomAlpha)
                    )
                )
            )
            .border(
                width = 0.8.dp,
                brush = Brush.linearGradient(colors = borderColors),
                shape = shape
            ),
        content = content
    )
}

/** 按当前界面风格在液态玻璃与经典实色面板之间切换 */
@Composable
fun Panel(
    modifier: Modifier = Modifier,
    corner: Dp = 20.dp,
    glass: Boolean = AppSettings.uiStyle == "glass",
    content: @Composable BoxScope.() -> Unit
) {
    val palette = LocalPalette.current
    if (glass) {
        GlassSurface(modifier = modifier, cornerRadius = corner, content = content)
    } else {
        val shape = RoundedCornerShape(corner)
        Box(
            modifier = modifier
                .clip(shape)
                .background(palette.panel)
                .border(width = 0.8.dp, color = palette.panelBorder, shape = shape),
            content = content
        )
    }
}

/** 按压时轻微缩放 */
@Composable
fun Modifier.pressable(onClick: () -> Unit): Modifier {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.97f else 1f,
        animationSpec = tween(durationMillis = 120),
        label = "pressScale"
    )
    return this
        .graphicsLayer {
            scaleX = scale
            scaleY = scale
        }
        .clickable(
            interactionSource = interaction,
            indication = LocalIndication.current,
            onClick = onClick
        )
}

/** 全屏背景：经典风格为纯色，液态玻璃风格叠加主题色柔光 */
@Composable
fun AppBackground(modifier: Modifier = Modifier) {
    val palette = LocalPalette.current
    val glass = AppSettings.uiStyle == "glass"
    Box(
        modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(
                        palette.surface,
                        if (glass) palette.surfaceAlt else palette.surface
                    )
                )
            )
    ) {
        if (glass) {
            val blobAlpha = if (palette.dark) 0.30f else 0.12f
            Canvas(Modifier.fillMaxSize()) {
                drawBlob(size.width * 0.08f, size.height * 0.04f, size.minDimension * 0.62f, palette.accent, blobAlpha)
                drawBlob(size.width * 0.98f, size.height * 0.22f, size.minDimension * 0.52f, palette.accent.shiftHue(58f), blobAlpha * 0.9f)
                drawBlob(size.width * 0.86f, size.height * 0.78f, size.minDimension * 0.56f, palette.accent.shiftHue(180f), blobAlpha * 0.8f)
                drawBlob(size.width * 0.10f, size.height * 0.96f, size.minDimension * 0.50f, palette.accent.shiftHue(300f), blobAlpha * 0.9f)
            }
        }
    }
}

private fun DrawScope.drawBlob(cx: Float, cy: Float, radius: Float, color: Color, alpha: Float) {
    val center = Offset(cx, cy)
    drawCircle(
        brush = Brush.radialGradient(
            colors = listOf(color.copy(alpha = alpha), Color.Transparent),
            center = center,
            radius = radius
        ),
        radius = radius,
        center = center
    )
}

/** 歌曲封面：网络封面 + 渐变占位；加载失败时保留占位色 */
@Composable
fun SongCover(
    url: String?,
    tint: Color,
    size: Dp,
    corner: Dp = 12.dp,
    circle: Boolean = false
) {
    val shape = if (circle) CircleShape else RoundedCornerShape(corner)
    Box(
        Modifier
            .size(size)
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(tint.copy(alpha = 0.95f), tint.copy(alpha = 0.45f))
                )
            )
    ) {
        if (!url.isNullOrBlank()) {
            AsyncImage(
                model = url,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }
    }
}
