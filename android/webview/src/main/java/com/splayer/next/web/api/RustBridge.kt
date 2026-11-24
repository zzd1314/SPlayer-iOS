package com.splayer.next.web.api

/**
 * Rust 音频核心（ffmpeg_audio / FFmpeg n9）加载探针。
 *
 * 当前阶段：.so 已随 APK 打包（arm64-v8a），此处仅验证动态库可加载、
 * FFmpeg 已静态链接；完整 audio-engine（解码线程 / DSP / 输出）尚未接入，
 * 播放仍由 Media3 承担。加载失败不抛出，由 bridge 如实返回 loaded=false。
 */
object RustBridge {

    private val loadError: String?

    init {
        var err: String? = null
        try {
            System.loadLibrary("rust_android_test")
        } catch (t: Throwable) {
            err = t.message ?: t.javaClass.simpleName
        }
        loadError = err
    }

    private external fun nativeAdd(a: Int, b: Int): Int
    private external fun nativeFfmpegMajor(): Int

    /** 供 window.api.rust.probe() 查询；字段如实反映加载与 FFmpeg 链接结果 */
    fun probe(): Map<String, Any> {
        val err = loadError
        if (err != null) {
            return mapOf("loaded" to false, "error" to err)
        }
        val smoke = runCatching { nativeAdd(2, 40) }.getOrDefault(-1)
        val ffmpegMajor = runCatching { nativeFfmpegMajor() }.getOrDefault(-1)
        return mapOf(
            "loaded" to true,
            "smokeTest" to smoke,
            "ffmpegMajor" to ffmpegMajor,
            "abi" to "arm64-v8a",
        )
    }
}
