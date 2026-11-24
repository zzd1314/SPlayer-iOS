package com.splayer.next.web.api

import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

/** 远端字节抓取：封面取色等需要绕过 WebView CORS 的场景 */
object RemoteBytes {

    /** 对齐主进程 system:fetchRemoteBytes 的 IpcResponse<ArrayBuffer> 形状 */
    fun fetch(url: String): Any? {
        if (!url.startsWith("http")) {
            return mapOf("success" to false, "error" to "invalid url")
        }
        return try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.connectTimeout = 10_000
            conn.readTimeout = 20_000
            conn.instanceFollowRedirects = true
            try {
                val code = conn.responseCode
                if (code !in 200..299) {
                    return mapOf(
                        "success" to false,
                        "error" to "HTTP $code",
                    )
                }
                val bytes = conn.inputStream.use { input ->
                    val out = ByteArrayOutputStream()
                    input.copyTo(out, 64 * 1024)
                    out.toByteArray()
                }
                mapOf(
                    "success" to true,
                    "data" to bytes.map { it.toInt() and 0xFF },
                )
            } finally {
                conn.disconnect()
            }
        } catch (e: Exception) {
            mapOf("success" to false, "error" to (e.message ?: "network error"))
        }
    }
}