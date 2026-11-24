package com.splayer.next.web

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebView
import com.splayer.next.web.api.BridgeRouter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONArray

/**
 * window.api 桥：把原 Electron preload 的 IPC 契约映射到 Android 原生实现。
 *
 * JS 侧调用约定（见 assets/web/bridge.js）：
 *   SPlayerNative.call(namespace, method, callId, argsJson)
 * 结果通过 evaluateJavascript 回调：
 *   window.__splayerResolve(callId, ok, payloadJson)
 */
class SPlayerBridge(private val host: WebHostActivity, private val context: Context) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val router = BridgeRouter(context, this)

    /** 暴露给 WebView 的原生接口 */
    inner class Native {
        @JavascriptInterface
        fun call(ns: String, method: String, callId: String, argsJson: String?): Boolean {
            val args = Json.parseArgs(argsJson)
            scope.launch {
                val result = runCatching { router.dispatch(ns, method, args) }
                val payload = result.getOrNull()
                val json = when {
                    result.isSuccess -> Json.write(payload)
                    else -> null
                }
                resolve(callId, result.isSuccess, json, result.exceptionOrNull())
            }
            return true
        }
    }

    val native = Native()

    /** 返回调用结果给渲染层 */
    private fun resolve(callId: String, ok: Boolean, json: String?, error: Throwable?) {
        // 必须用 JSONObject.quote 转成带引号的 JS 字面量：
        // 直接 toString 会生成 __splayerResolve(c1, ...)，注入脚本抛 ReferenceError
        // （WebView 中表现为无文件名的 "Script error."），Promise 永不 resolve，启动层卡死
        val callIdJs = org.json.JSONObject.quote(callId)
        mainHandler.post {
            val errJson = error?.let { Json.write(mapOf("message" to (it.message ?: "bridge error"))) }
            runCatching {
                webView().evaluateJavascript(
                    "window.__splayerResolve($callIdJs, $ok, ${json ?: "null"}, ${errJson ?: "null"});",
                    null
                )
            }
        }
    }

    /** 向渲染层推送事件（channel 与 preload subscribe 命名一致） */
    fun pushEvent(channel: String, payloadJson: String) {
        val channelJs = org.json.JSONObject.quote(channel)
        mainHandler.post {
            runCatching {
                webView().evaluateJavascript(
                    "window.__splayerDispatch($channelJs, $payloadJson);",
                    null
                )
            }
        }
    }

    /** 处理系统返回键：优先回退 WebView 历史，否则通知前端 */
    fun consumeBack(): Boolean {
        val view = webView()
        return if (view.canGoBack()) {
            view.goBack()
            true
        } else {
            false
        }
    }

    fun onHistoryChanged() = Unit

    private fun webView(): WebView = host.webView

    companion object {
        /** 供 LibraryStore 等无桥引用模块推送事件使用 */
        @Volatile
        var active: SPlayerBridge? = null
            private set

        /** BridgeRouter 初始化时注入当前桥实例 */
        internal fun activate(bridge: SPlayerBridge?) {
            active = bridge
        }
    }

    /**
     * SAF 目录选择（download.pickDir）：发起系统目录选择器并阻塞等待结果，
     * 结果由 Activity 的 onDirectoryPicked 回填，超时 120s 视为取消。
     */
    fun requestPickDir(): String? {
        val deferred = awaitPick()
        host.launchDirectoryPicker()
        return runCatching {
            kotlinx.coroutines.runBlocking {
                kotlinx.coroutines.withTimeoutOrNull(120_000) { deferred.await() }
            }
        }.getOrNull()
    }

    /** Activity 拿到 SAF 结果后回填 */
    fun onDirectoryPicked(uri: String?) {
        pendingPick?.complete(uri)
        pendingPick = null
    }

    private var pendingPick: kotlinx.coroutines.CompletableDeferred<String?>? = null

    internal fun awaitPick(): kotlinx.coroutines.CompletableDeferred<String?> =
        kotlinx.coroutines.CompletableDeferred<String?>().also { pendingPick = it }
}
