package com.splayer.next.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.splayer.next.data.AppSettings
import com.splayer.next.data.MusicRepository
import com.splayer.next.data.QrCodeLogin
import com.splayer.next.ui.theme.LocalPalette
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 登录页：支持扫码登录（网易云音乐 App）与 Cookie 登录（MUSIC_U）。
 * 登录信息仅保存在本机。
 */
@Composable
fun LoginScreen(onBack: () -> Unit) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()
    var mode by remember { mutableStateOf("qr") }
    var input by remember { mutableStateOf(AppSettings.cookie) }
    var loading by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }

    var qr by remember { mutableStateOf<QrCodeLogin?>(null) }
    var qrImage by remember { mutableStateOf<ImageBitmap?>(null) }
    var qrStatus by remember { mutableStateOf("生成二维码后，用网易云音乐 App 扫码登录") }
    var qrLoading by remember { mutableStateOf(false) }

    fun refreshQr() {
        if (qrLoading) return
        qrLoading = true
        qrStatus = "正在生成二维码…"
        scope.launch {
            val token = MusicRepository.createQrLogin()
            if (token == null) {
                qrLoading = false
                qrStatus = "二维码生成失败，请检查网络后重试"
                return@launch
            }
            qr = token
            qrImage = withContext(Dispatchers.Default) { buildQrBitmap(token.url) }
            qrStatus = "打开网易云音乐 App 扫码登录"
            qrLoading = false
        }
    }

    // 轮询扫码状态
    LaunchedEffect(qr?.key) {
        val key = qr?.key ?: return@LaunchedEffect
        while (isActive) {
            delay(2_000)
            val result = MusicRepository.checkQrLogin(key)
            qrStatus = result.message
            if (result.code == 803) {
                val cookie = result.cookie
                if (cookie.isNullOrBlank()) {
                    qrStatus = "登录成功但未获取到凭证，请重新生成二维码"
                    break
                }
                AppSettings.saveLogin(cookie, null)
                val profile = MusicRepository.account()
                if (profile != null) {
                    AppSettings.saveLogin(cookie, profile)
                    onBack()
                } else {
                    qrStatus = "登录成功，但获取账号资料失败"
                }
                break
            }
            if (result.code == 800) break
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(palette.surface)
            .statusBarsPadding()
            .navigationBarsPadding()
            .imePadding()
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(top = 8.dp, bottom = 32.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) {
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "返回",
                        tint = palette.textSecondary
                    )
                }
                Text(
                    text = "登录网易云音乐",
                    color = palette.textPrimary,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Spacer(Modifier.height(22.dp))

            Box(
                Modifier
                    .size(64.dp)
                    .background(palette.accentSoft, RoundedCornerShape(20.dp)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Filled.AccountCircle,
                    contentDescription = null,
                    tint = palette.accent,
                    modifier = Modifier.size(36.dp)
                )
            }

            Spacer(Modifier.height(16.dp))

            Text(
                text = "登录后同步收藏与歌单",
                color = palette.textPrimary,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = "支持网易云音乐 App 扫码登录，也可以手动粘贴浏览器 Cookie。",
                color = palette.textSecondary,
                fontSize = 13.sp,
                lineHeight = 20.sp
            )

            Spacer(Modifier.height(18.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ChoiceChip("扫码登录", mode == "qr") {
                    mode = "qr"
                    message = null
                }
                ChoiceChip("Cookie 登录", mode == "cookie") {
                    mode = "cookie"
                    message = null
                }
            }

            Spacer(Modifier.height(18.dp))

            if (mode == "qr") {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .background(palette.field, RoundedCornerShape(20.dp))
                        .padding(vertical = 20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    val image = qrImage
                    if (image != null) {
                        Image(
                            bitmap = image,
                            contentDescription = "登录二维码",
                            modifier = Modifier.size(196.dp)
                        )
                    } else {
                        Box(
                            Modifier
                                .size(196.dp)
                                .background(palette.panel, RoundedCornerShape(16.dp)),
                            contentAlignment = Alignment.Center
                        ) {
                            if (qrLoading) {
                                CircularProgressIndicator(
                                    color = palette.accent,
                                    strokeWidth = 2.dp,
                                    modifier = Modifier.size(24.dp)
                                )
                            } else {
                                Text(
                                    text = "二维码",
                                    color = palette.textTertiary,
                                    fontSize = 13.sp
                                )
                            }
                        }
                    }
                    Spacer(Modifier.height(14.dp))
                    Text(
                        text = qrStatus,
                        color = palette.textSecondary,
                        fontSize = 12.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 18.dp)
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(
                        text = if (qr == null) "生成二维码" else "刷新二维码",
                        color = palette.accent,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier
                            .pressable { refreshQr() }
                            .padding(horizontal = 14.dp, vertical = 6.dp)
                    )
                }
            } else {
                OutlinedTextField(
                    value = input,
                    onValueChange = {
                        input = it
                        message = null
                    },
                    label = { Text("Cookie", fontSize = 13.sp) },
                    placeholder = {
                        Text(
                            "MUSIC_U=xxxx 或直接粘贴整段 Cookie",
                            fontSize = 13.sp,
                            color = palette.textTertiary
                        )
                    },
                    minLines = 4,
                    maxLines = 8,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(16.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = palette.textPrimary,
                        unfocusedTextColor = palette.textPrimary,
                        focusedBorderColor = palette.accent,
                        unfocusedBorderColor = palette.panelBorder,
                        focusedLabelColor = palette.accent,
                        unfocusedLabelColor = palette.textSecondary,
                        cursorColor = palette.accent,
                        focusedPlaceholderColor = palette.textTertiary,
                        unfocusedPlaceholderColor = palette.textTertiary
                    )
                )

                message?.let {
                    Spacer(Modifier.height(12.dp))
                    Text(
                        text = it,
                        color = palette.accent,
                        fontSize = 12.sp,
                        lineHeight = 18.sp
                    )
                }

                Spacer(Modifier.height(18.dp))

                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(52.dp)
                        .background(palette.accent, RoundedCornerShape(18.dp))
                        .pressable {
                            if (loading || input.isBlank()) return@pressable
                            loading = true
                            message = null
                            scope.launch {
                                val cookie = normalizeCookie(input)
                                AppSettings.saveLogin(cookie, null)
                                val profile = MusicRepository.account()
                                if (profile != null) {
                                    AppSettings.saveLogin(cookie, profile)
                                    loading = false
                                    onBack()
                                } else {
                                    AppSettings.logout()
                                    loading = false
                                    message = "Cookie 无效或已过期，请重新获取"
                                }
                            }
                        },
                    contentAlignment = Alignment.Center
                ) {
                    if (loading) {
                        CircularProgressIndicator(
                            color = palette.onAccent,
                            strokeWidth = 2.dp,
                            modifier = Modifier.size(22.dp)
                        )
                    } else {
                        Text(
                            text = "登录",
                            color = palette.onAccent,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            Text(
                text = "暂不登录，继续体验",
                color = palette.textSecondary,
                fontSize = 13.sp,
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .pressable(onBack)
                    .padding(8.dp)
            )

            Spacer(Modifier.height(14.dp))

            Text(
                text = "登录仅保存在本机，不会上传到任何服务器。凭证仅用于请求网易云公开接口。",
                color = palette.textTertiary,
                fontSize = 11.sp,
                lineHeight = 17.sp
            )
        }
    }
}

private fun normalizeCookie(raw: String): String {
    val trimmed = raw.trim()
    if (trimmed.isBlank()) return ""
    if (!trimmed.contains("=")) return "MUSIC_U=$trimmed"
    return trimmed
}

/** 生成二维码位图（使用 zxing，无网络依赖） */
private fun buildQrBitmap(content: String, size: Int = 512): ImageBitmap? = runCatching {
    val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, size, size)
    val pixels = IntArray(size * size)
    for (y in 0 until size) {
        val offset = y * size
        for (x in 0 until size) {
            pixels[offset + x] = if (matrix.get(x, y)) {
                android.graphics.Color.BLACK
            } else {
                android.graphics.Color.WHITE
            }
        }
    }
    val bitmap = android.graphics.Bitmap.createBitmap(
        size,
        size,
        android.graphics.Bitmap.Config.ARGB_8888
    )
    bitmap.setPixels(pixels, 0, size, 0, 0, size, size)
    bitmap.asImageBitmap()
}.getOrNull()