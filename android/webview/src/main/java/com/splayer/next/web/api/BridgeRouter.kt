package com.splayer.next.web.api

import android.content.Context
import com.splayer.next.web.lyric.DesktopLyricController
import com.splayer.next.web.nowplaying.NowPlayingState
import com.splayer.next.web.playback.PlaybackEngine

/** 桥接未实现时抛出，渲染层按功能降级处理 */
class BridgeUnsupportedException(message: String) : Exception(message)

/**
 * window.api 调用路由：按命名空间分发到对应 Android 实现。
 * 返回值结构与原 Electron 主进程 IPC handler 对齐。
 *
 * 音源 API（netease 等）由 assets/web/netease-api.js 在 WebView 内完成，
 * 仅网络请求经 system.bridgeHttp 转发到 Kotlin。
 */
class BridgeRouter(private val context: Context, private val bridge: Any?) {

    private val configStore = ConfigStore(context)
    private val libraryStore by lazy { LibraryStore(context) }
    private val playlistStore by lazy { PlaylistStore(context) }

    init {
        val b = bridge as? com.splayer.next.web.SPlayerBridge
        DownloadManager.init(context, b)
        com.splayer.next.web.SPlayerBridge.activate(b)
        LibraryStore.shared(context)
        NowPlayingState.init(context)
        CacheManager.init(context)
    }

    fun dispatch(ns: String, method: String, args: List<Any?>): Any? = when (ns) {
        "player" -> PlaybackEngine.handle(method, args)
        "config" -> dispatchConfig(method, args)
        "window" -> dispatchWindow(method, args)
        "system" -> dispatchSystem(method, args)
        // initPlayer() 会 await plugins.list()，缺该命名空间会令启动层无法退出
        "plugins" -> dispatchPlugins(method)
        // 听歌识曲 Android 端未接入：明确返回不支持，避免未捕获的 Promise 拒绝
        "recognition" -> dispatchRecognition(method)
        "library" -> libraryStore.handle(method, args)
        "playlist" -> playlistStore.handle(method, args)
        "download" -> DownloadManager.handle(method, args)
        "nowPlaying" -> NowPlayingState.handle(method, args)
        "cache" -> CacheManager.handle(method, args)
        "desktopLyric" -> dispatchDesktopLyric(method)
        "rust" -> RustBridge.probe()
        else -> throw BridgeUnsupportedException("$ns.$method 暂未在 Android 端实现")
    }

    // MARK: - 配置存储（对应 electron-store）

    private fun dispatchConfig(method: String, args: List<Any?>): Any? = when (method) {
        "get" -> configStore.get(args.getOrNull(0) as? String ?: "")
        "set" -> {
            configStore.set(args.getOrNull(0) as? String ?: "", args.getOrNull(1))
            null
        }

        "getAll" -> configStore.all()
        "reset" -> {
            configStore.reset()
            null
        }

        "replaceAll" -> {
            configStore.replaceAll(args.getOrNull(0) as? Map<*, *>)
            null
        }

        else -> throw BridgeUnsupportedException("config.$method 暂未实现")
    }

    // MARK: - 窗口控制（对应 preload window.*）

    /**
     * 渲染层启动流程第一句是 window.ready()，Electron 下等主进程首帧信号；
     * Android 端 Activity 已在前台，直接返回就绪，否则启动层永远不会移除。
     * 桌面歌词改由系统悬浮窗实现；灵动岛 / 任务栏歌词无对应物，返回空值保持无副作用。
     */
    private fun dispatchWindow(method: String, args: List<Any?>): Any? = when (method) {
        "ready", "startupComplete" -> true
        "startupFailed" -> {
            val message = args.getOrNull(0)?.toString().orEmpty()
            lastStartupError = message
            android.util.Log.e("SPlayerBoot", "渲染层启动失败：$message")
            true
        }

        "isDesktopLyricOpen" -> DesktopLyricController.isShowing()
        "isMaximized", "isFullscreen", "isDynamicIslandOpen", "isTaskbarLyricOpen" -> false

        "toggleDesktopLyric" -> DesktopLyricController.toggle(context)
        "closeDesktopLyric" -> {
            DesktopLyricController.close(context)
            null
        }

        "minimize", "toggleMaximize", "toggleFullscreen", "hide", "quit",
        "toggleDynamicIsland", "closeDynamicIsland", "toggleTaskbarLyric", "closeTaskbarLyric",
        "setPlayerExpanded" -> null

        else -> throw BridgeUnsupportedException("window.$method 暂未在 Android 端实现")
    }

    /** 桌面歌词窗口自带 API（高度/位置持久化）：Android 悬浮窗由原生自理 */
    private fun dispatchDesktopLyric(method: String): Any? = when (method) {
        "setHeight", "move", "saveState", "setUnlockButtonBounds" -> null
        "getConfig" -> configStore.get("desktopLyric") ?: emptyMap<String, Any>()
        else -> throw BridgeUnsupportedException("desktopLyric.$method 暂未在 Android 端实现")
    }

    // MARK: - 插件（Electron 主进程插件宿主在 Android 端不可用）

    /** 启动期只要求 plugins.list 可返回；插件市场等桌面能力如实标记为未支持 */
    private fun dispatchPlugins(method: String): Any? = when (method) {
        "list" -> emptyList<Any>()
        "market" -> mapOf(
            "ok" to false,
            "error" to "Android 端暂未支持插件市场",
            "plugins" to emptyList<Any>(),
        )

        else -> throw BridgeUnsupportedException("plugins.$method 暂未在 Android 端支持")
    }

    // MARK: - 听歌识曲（Android 端未接入）

    private fun dispatchRecognition(method: String): Any? = when (method) {
        "isSupported" -> false
        "start", "stop", "cancel" -> null
        else -> throw BridgeUnsupportedException("recognition.$method 暂未在 Android 端支持")
    }

    // MARK: - 系统能力

    private fun dispatchSystem(method: String, args: List<Any?>): Any? = when (method) {
        "reportBootError" -> {
            val message = args.getOrNull(0)?.toString().orEmpty()
            lastStartupError = message
            android.util.Log.e("SPlayerBoot", message)
            null
        }

        "fetchRemoteBytes" -> RemoteBytes.fetch(args.getOrNull(0) as? String ?: "")
        "secureEncrypt" -> mapOf("value" to SecureStore.encrypt(args.getOrNull(0)?.toString().orEmpty()))
        "secureDecrypt" -> mapOf("value" to SecureStore.decrypt(args.getOrNull(0)?.toString().orEmpty()))
        "bridgeHttp" -> BridgeHttp.request(
            url = args.getOrNull(0) as? String ?: "",
            method = args.getOrNull(1) as? String ?: "GET",
            headers = args.getOrNull(2) as? Map<*, *> ?: emptyMap<Any, Any>(),
            body = args.getOrNull(3)?.toString() ?: "",
        )

        "consumePendingProtocolUrl" -> null
        "consumePendingAudioFiles" -> emptyList<Any>()
        "setLocale", "relaunch", "toggleDevTools", "focusMainWindow", "openSettings",
        "openLogsDir", "showInExplorer", "saveFile", "testNetworkProxy", "copyTrackFile",
        "minimize", "hide", "toggleFullscreen", "openDevTools" -> null

        "listFonts" -> emptyList<Any>()
        else -> throw BridgeUnsupportedException("system.$method 暂未实现")
    }

    companion object {
        /** 最近一次渲染层启动错误：便于真机现场排查（同时写 logcat 标签 SPlayerBoot） */
        @Volatile
        var lastStartupError: String? = null
            private set
    }
}
