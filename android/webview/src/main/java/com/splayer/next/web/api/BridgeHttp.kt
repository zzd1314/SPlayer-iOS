package com.splayer.next.web.api

import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * 通用 HTTP 代理：为 WebView 内的网易云加密层转发请求（绕过 CORS）。
 * 返回结构与 netease-api.js 的 fetch 适配器约定一致。
 */
object BridgeHttp {

    fun request(
        url: String,
        method: String,
        headers: Map<*, *>,
        body: String,
    ): Any? {
        if (!url.startsWith("http")) return null
        return try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.requestMethod = method
            conn.connectTimeout = 12_000
            conn.readTimeout = 30_000
            conn.instanceFollowRedirects = true
            headers.forEach { (k, v) -> conn.setRequestProperty(k.toString(), v?.toString()) }
            if (method != "GET" && body.isNotEmpty()) {
                conn.doOutput = true
                val bytes = body.toByteArray(Charsets.UTF_8)
                conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                conn.setFixedLengthStreamingMode(bytes.size)
                conn.outputStream.use { it.write(bytes) }
            }
            try {
                val code = conn.responseCode
                val stream = if (code in 200..299) conn.inputStream else conn.errorStream
                val out = ByteArrayOutputStream()
                stream?.use { it.copyTo(out, 64 * 1024) }
                val setCookies = conn.headerFields
                    ?.filterKeys { it != null && it.equals("set-cookie", true) }
                    ?.values
                    ?.flatten()
                    ?: emptyList()
                val headerMap = linkedMapOf<String, String>()
                conn.headerFields?.forEach { (key, values) ->
                    if (!key.isNullOrBlank() && !key.equals("set-cookie", true) && values.isNotEmpty()) {
                        headerMap[key.lowercase()] = values.first()
                    }
                }
                mapOf(
                    "status" to code,
                    "headers" to headerMap,
                    "setCookie" to setCookies,
                    "bodyBase64" to encodeBase64(out.toByteArray()),
                )
            } finally {
                conn.disconnect()
            }
        } catch (e: Exception) {
            mapOf(
                "status" to 502,
                "headers" to emptyMap<String, String>(),
                "setCookie" to emptyList<String>(),
                "bodyBase64" to "",
            )
        }
    }

    /** WebView 的 atob 可解码标准 base64 */
    private fun encodeBase64(bytes: ByteArray): String =
        android.util.Base64.encodeToString(bytes, android.util.Base64.DEFAULT)
            .replace("\n", "")
}