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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.splayer.next.ui.theme.Accent
import com.splayer.next.ui.theme.AccentBlue
import com.splayer.next.ui.theme.AccentPink
import com.splayer.next.ui.theme.AccentTeal
import com.splayer.next.ui.theme.LocalPalette

/** 液态玻璃面板：半透明白色渐变 + 渐变高光描边 */
@Composable
fun GlassSurface(
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 20.dp,
    content: @Composable BoxScope.() -> Unit
) {
    val palette = LocalPalette.current
    val shape = RoundedCornerShape(cornerRadius)
    val topAlpha = if (palette.dark) 0.20f else 0.74f
    val bottomAlpha = if (palette.dark) 0.08f else 0.44f
    val borderColors = if (palette.dark) {
        listOf(
            Color.White.copy(alpha = 0.55f),
            Color.White.copy(alpha = 0.06f),
            Color.White.copy(alpha = 0.30f)
        )
    } else {
        listOf(
            Color.White.copy(alpha = 0.95f),
            Color.Black.copy(alpha = 0.05f),
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

/** 根据风格开关在玻璃面板与经典面板之间切换 */
@Composable
fun Panel(
    glass: Boolean,
    modifier: Modifier = Modifier,
    corner: Dp = 20.dp,
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
                .background(palette.panelSolid)
                .border(
                    width = 0.8.dp,
                    color = if (palette.dark) Color(0x1AFFFFFF) else Color(0x14000000),
                    shape = shape
                ),
            content = content
        )
    }
}

/** 按压时轻微缩放，给玻璃面板补充触觉式反馈 */
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

/** 柔光背景，深浅色主题分别使用不同底色与光斑强度 */
@Composable
fun GlassBackground(modifier: Modifier = Modifier) {
    val palette = LocalPalette.current
    val blobAlpha = if (palette.dark) 0.55f else 0.22f
    Box(
        modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(palette.backgroundTop, palette.backgroundBottom)
                )
            )
    ) {
        Canvas(Modifier.fillMaxSize()) {
            drawBlob(size.width * 0.10f, size.height * 0.06f, size.minDimension * 0.55f, Accent, blobAlpha)
            drawBlob(size.width * 0.96f, size.height * 0.20f, size.minDimension * 0.48f, AccentBlue, blobAlpha)
            drawBlob(size.width * 0.88f, size.height * 0.74f, size.minDimension * 0.52f, AccentPink, blobAlpha)
            drawBlob(size.width * 0.12f, size.height * 0.94f, size.minDimension * 0.46f, AccentTeal, blobAlpha)
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