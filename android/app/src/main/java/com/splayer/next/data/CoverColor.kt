package com.splayer.next.data

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.sqrt
import android.graphics.Color as AndroidColor

/**
 * 封面取色：与桌面端 extractColorFromImage 的思路一致。
 * 中心加权采样 + 4bit 量化 + 彩度/明度过滤 + 综合评分，得到适合做主题的封面代表色。
 */
object CoverColorExtractor {

    private const val SAMPLE_SIZE = 64
    private const val EDGE_MARGIN = 3
    private const val MIN_SATURATION = 0.12f
    private const val MIN_COLORFUL_RATIO = 0.12f
    private const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36"

    private val cache = HashMap<String, Color?>()

    private data class Bucket(
        val red: Int,
        val green: Int,
        val blue: Int,
        val count: Int,
        val hsv: FloatArray
    )

    suspend fun extract(url: String?): Color? = withContext(Dispatchers.IO) {
        if (url.isNullOrBlank() || !url.startsWith("http")) return@withContext null
        synchronized(cache) { if (cache.containsKey(url)) return@withContext cache[url] }

        val bytes = runCatching { download(url) }.getOrNull()
        val color = bytes?.let { runCatching { sample(it) }.getOrNull() }
        synchronized(cache) {
            if (cache.size > 64) cache.clear()
            cache[url] = color
        }
        color
    }

    private fun download(url: String): ByteArray? {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 8_000
        connection.readTimeout = 8_000
        connection.setRequestProperty("User-Agent", USER_AGENT)
        connection.setRequestProperty("Referer", "https://music.163.com/")
        return try {
            if (connection.responseCode !in 200..299) null
            else connection.inputStream.use { it.readBytes() }
        } finally {
            connection.disconnect()
        }
    }

    private fun sample(bytes: ByteArray): Color? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var inSampleSize = 1
        while (bounds.outWidth / (inSampleSize * 2) >= SAMPLE_SIZE &&
            bounds.outHeight / (inSampleSize * 2) >= SAMPLE_SIZE
        ) {
            inSampleSize *= 2
        }
        val options = BitmapFactory.Options().apply { this.inSampleSize = inSampleSize }
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: return null
        val scaled = Bitmap.createScaledBitmap(decoded, SAMPLE_SIZE, SAMPLE_SIZE, false)
        if (scaled !== decoded) decoded.recycle()

        val pixels = IntArray(SAMPLE_SIZE * SAMPLE_SIZE)
        scaled.getPixels(pixels, 0, SAMPLE_SIZE, 0, 0, SAMPLE_SIZE, SAMPLE_SIZE)
        scaled.recycle()

        val buckets = HashMap<Int, Int>()
        val center = (SAMPLE_SIZE - 1) / 2f
        for (y in EDGE_MARGIN until SAMPLE_SIZE - EDGE_MARGIN) {
            for (x in EDGE_MARGIN until SAMPLE_SIZE - EDGE_MARGIN) {
                val pixel = pixels[y * SAMPLE_SIZE + x]
                if (AndroidColor.alpha(pixel) < 16) continue
                val dx = (x - center) / center
                val dy = (y - center) / center
                val distance = sqrt(dx * dx + dy * dy)
                val weight = when {
                    distance < 0.34f -> 3
                    distance < 0.58f -> 2
                    else -> 1
                }
                val r = AndroidColor.red(pixel) shr 4
                val g = AndroidColor.green(pixel) shr 4
                val b = AndroidColor.blue(pixel) shr 4
                val key = (r shl 8) or (g shl 4) or b
                buckets[key] = (buckets[key] ?: 0) + weight
            }
        }
        if (buckets.isEmpty()) return null

        val totalCount = buckets.values.sum()
        val colorful = ArrayList<Bucket>(buckets.size)
        val hsv = FloatArray(3)
        for ((key, count) in buckets) {
            val red = ((key shr 8) and 0xF) * 16 + 8
            val green = ((key shr 4) and 0xF) * 16 + 8
            val blue = (key and 0xF) * 16 + 8
            AndroidColor.colorToHSV(AndroidColor.rgb(red, green, blue), hsv)
            if (hsv[1] >= MIN_SATURATION && hsv[2] in 0.10f..0.94f) {
                colorful += Bucket(red, green, blue, count, hsv.copyOf())
            }
        }
        if (colorful.isEmpty()) return null
        if (colorful.sumOf { it.count }.toFloat() / totalCount < MIN_COLORFUL_RATIO) return null

        val maxCount = colorful.maxOf { it.count }
        var best: Bucket? = null
        var bestScore = 0f
        for (bucket in colorful) {
            val populationScore = (bucket.count.toFloat() / maxCount)
                .toDouble()
                .pow(0.72)
                .toFloat()
            val chromaScore = (bucket.hsv[1] / 0.55f).coerceIn(0f, 1f)
            val toneScore = (1f - abs(bucket.hsv[2] * 100f - 58f) / 58f).coerceIn(0f, 1f)
            val score = populationScore * 0.58f + chromaScore * 0.28f + toneScore * 0.14f
            if (score > bestScore) {
                bestScore = score
                best = bucket
            }
        }
        val picked = best?.hsv?.copyOf() ?: return null
        picked[1] = picked[1].coerceIn(0.30f, 0.72f)
        picked[2] = picked[2].coerceIn(0.30f, 0.72f)
        return Color(AndroidColor.HSVToColor(picked))
    }
}
