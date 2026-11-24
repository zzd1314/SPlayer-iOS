package com.splayer.next.web.api

import android.content.Context
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

    fun dispatch(ns: String, method: String, args: List<Any?>): Any? = when (ns) {
        "player" -> PlaybackEngine.handle(method, args)
        "config" -> dispatchConfig(method, args)
        "system" -> dispatchSystem(method, args)
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

    // MARK: - 系统能力

    private fun dispatchSystem(method: String, args: List<Any?>): Any? = when (method) {
        "fetchRemoteBytes" -> RemoteBytes.fetch(args.getOrNull(0) as? String ?: "")
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
}