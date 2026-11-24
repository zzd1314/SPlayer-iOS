package com.splayer.next.data

import androidx.compose.ui.graphics.Color

data class Song(
    val id: String,
    val title: String,
    val artist: String,
    val album: String,
    val duration: String,
    val tint: Color,
    val url: String = ""
)

data class Playlist(
    val id: String,
    val title: String,
    val subtitle: String,
    val tint: Color
)

object SampleData {
    private const val DEMO_AUDIO = "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-"

    val songs = listOf(
        Song("1", "夜行列车", "陈默", "城市回声", "04:12", Color(0xFFFF6A3D), DEMO_AUDIO + "1.mp3"),
        Song("2", "液态月光", "Luna", "Glass Hours", "03:48", Color(0xFF3D7BFF), DEMO_AUDIO + "2.mp3"),
        Song("3", "海边信号", "旧电台", "未送达的信", "05:01", Color(0xFF24D3C0), DEMO_AUDIO + "3.mp3"),
        Song("4", "午夜霓虹", "Neon Kid", "Downtown", "03:22", Color(0xFFFF4FA3), DEMO_AUDIO + "4.mp3"),
        Song("5", "风经过", "林岸", "四季", "04:36", Color(0xFF8C7BFF), DEMO_AUDIO + "5.mp3"),
        Song("6", "沙漏", "白噪实验", "时间碎片", "02:58", Color(0xFF6FD08C), DEMO_AUDIO + "6.mp3"),
        Song("7", "漂浮", "Aero", "Low Gravity", "04:05", Color(0xFFF5B942), DEMO_AUDIO + "7.mp3"),
        Song("8", "静默频率", "深海电台", "FM 96.7", "06:11", Color(0xFF5AC8FA), DEMO_AUDIO + "8.mp3")
    )

    val playlists = listOf(
        Playlist("p1", "深夜通勤", "32 首 · 电子", Color(0xFF3D7BFF)),
        Playlist("p2", "雨夜钢琴", "18 首 · 轻音乐", Color(0xFF8C7BFF)),
        Playlist("p3", "清晨慢跑", "24 首 · 独立", Color(0xFF24D3C0)),
        Playlist("p4", "城市民谣", "21 首 · 民谣", Color(0xFFFF6A3D)),
        Playlist("p5", "Neon Drive", "27 首 · 合成器", Color(0xFFFF4FA3)),
        Playlist("p6", "专注工作", "40 首 · Lo-Fi", Color(0xFFF5B942))
    )
}