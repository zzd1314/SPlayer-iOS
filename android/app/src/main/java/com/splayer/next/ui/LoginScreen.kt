package com.splayer.next.ui

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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.splayer.next.data.AppSettings
import com.splayer.next.data.MusicRepository
import com.splayer.next.ui.theme.LocalPalette
import kotlinx.coroutines.launch

/**
 * 登录页：支持填写网易云 Cookie（MUSIC_U），登录成功后写入设置并拉取账号资料。
 * 也提供游客继续使用。
 */
@Composable
fun LoginScreen(onBack: () -> Unit) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()
    var input by remember { mutableStateOf(AppSettings.cookie) }
    var loading by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }

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

            Spacer(Modifier.height(36.dp))

            Box(
                Modifier
                    .width(72.dp)
                    .height(72.dp)
                    .background(palette.accentSoft, RoundedCornerShape(22.dp)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Filled.AccountCircle,
                    contentDescription = null,
                    tint = palette.accent,
                    modifier = Modifier.width(40.dp).height(40.dp)
                )
            }

            Spacer(Modifier.height(20.dp))

            Text(
                text = "粘贴浏览器 Cookie 即可登录",
                color = palette.textPrimary,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = "在浏览器登录 music.163.com 后，从开发者工具复制 Cookie 中的 MUSIC_U 字段（或整段 Cookie），粘贴到下方即可同步账号、歌单与收藏。",
                color = palette.textSecondary,
                fontSize = 13.sp,
                lineHeight = 20.sp
            )

            Spacer(Modifier.height(24.dp))

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

            Spacer(Modifier.height(24.dp))

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
                        modifier = Modifier.width(22.dp).height(22.dp)
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

            Spacer(Modifier.height(14.dp))

            Text(
                text = "暂不登录，继续体验",
                color = palette.textSecondary,
                fontSize = 13.sp,
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .pressable(onBack)
                    .padding(8.dp)
            )

            Spacer(Modifier.height(20.dp))

            Text(
                text = "登录仅保存在本机，不会上传到任何服务器。Cookie 仅用于请求网易云公开接口。",
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
