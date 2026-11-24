package com.splayer.next.web.api

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.GZIPInputStream
import java.util.zip.InflaterInputStream

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
            var hasContentType = false
            headers.forEach { (k, v) ->
                val name = k.toString()
                if (name.equals("content-type", true)) hasContentType = true
                conn.setRequestProperty(name, v?.toString())
            }
            if (method != "GET" && body.isNotEmpty()) {
                conn.doOutput = true
                val bytes = body.toByteArray(Charsets.UTF_8)
                if (!hasContentType) {
                    conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                }
                conn.setFixedLengthStreamingMode(bytes.size)
                conn.outputStream.use { it.write(bytes) }
            }
            try {
                val code = conn.responseCode
                val stream = if (code in 200..299) conn.inputStream else conn.errorStream
                val out = ByteArrayOutputStream()
                stream?.use { it.copyTo(out, 64 * 1024) }
                // 网易云客户端会带 Accept-Encoding: gzip,deflate，
                // HttpURLConnection 不会自动解压，必须自行处理后才能按 JSON 解析
                val decoded = decodeBody(out.toByteArray(), conn.contentEncoding)
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
                    "bodyBase64" to encodeBase64(decoded),
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

    /** 按 Content-Encoding 解压；也兼容服务端未声明但实际是 gzip 的情况 */
    private fun decodeBody(bytes: ByteArray, contentEncoding: String?): ByteArray {
        if (bytes.isEmpty()) return bytes
        val enc = contentEncoding?.lowercase().orEmpty()
        val gzipMagic = bytes.size > 2 &&
            bytes[0] == 0x1f.toByte() && bytes[1] == 0x8b.toByte()
        return try {
            when {
                enc.contains("gzip") || (enc.isEmpty() && gzipMagic) ->
                    GZIPInputStream(ByteArrayInputStream(bytes)).use { it.readBytes() }
                enc.contains("deflate") ->
                    InflaterInputStream(ByteArrayInputStream(bytes)).use { it.readBytes() }
                else -> bytes
            }
        } catch (e: Exception) {
            bytes
        }
    }

    /** WebView 的 atob 可解码标准 base64 */
    private fun encodeBase64(bytes: ByteArray): String =
        android.util.Base64.encodeToString(bytes, android.util.Base64.DEFAULT)
            .replace("\n", "")
}
