package com.splayer.next.data

import kotlin.math.abs

/**
 * LRC 歌词解析：支持一行多时间标签、[mm:ss.xx] 格式与翻译合并。
 */
object LrcParser {

    private val timeTag = Regex("\\[(\\d{1,2}):(\\d{1,2})(?:[.:](\\d{1,3}))?]")

    fun parse(lrc: String?, translation: String?): Lyric {
        val main = extract(lrc)
        val trans = extract(translation)
        if (main.isEmpty()) return Lyric()

        val lines = ArrayList<LyricLine>(main.size)
        var transIndex = 0
        for ((timeMs, text) in main) {
            while (
                transIndex + 1 < trans.size &&
                abs(trans[transIndex + 1].first - timeMs) <= abs(trans[transIndex].first - timeMs)
            ) {
                transIndex++
            }
            val candidate = trans.getOrNull(transIndex)
            val translated = candidate
                ?.takeIf { abs(it.first - timeMs) <= 120L }
                ?.second
                ?.takeIf { it.isNotBlank() && it != text }
            lines += LyricLine(timeMs, text, translated)
        }
        return Lyric(lines = lines, hasTranslation = lines.any { !it.translation.isNullOrBlank() })
    }

    /** 提取所有 (时间, 文本) 并去重排序 */
    private fun extract(raw: String?): List<Pair<Long, String>> {
        if (raw.isNullOrBlank()) return emptyList()
        val result = ArrayList<Pair<Long, String>>()
        raw.lineSequence().forEach { line ->
            val matches = timeTag.findAll(line).toList()
            if (matches.isEmpty()) return@forEach
            val text = line.substring(matches.last().range.last + 1).trim()
            matches.forEach { match ->
                val minutes = match.groupValues[1].toLongOrNull() ?: return@forEach
                val seconds = match.groupValues[2].toLongOrNull() ?: return@forEach
                val fractionRaw = match.groupValues[3]
                val fraction = when (fractionRaw.length) {
                    1 -> fractionRaw.toLong() * 100
                    2 -> fractionRaw.toLong() * 10
                    3 -> fractionRaw.toLong()
                    else -> 0L
                }
                result += (minutes * 60_000L + seconds * 1_000L + fraction) to text
            }
        }
        return result
            .filter { it.second.isNotBlank() }
            .distinctBy { it.first }
            .sortedBy { it.first }
    }
}
