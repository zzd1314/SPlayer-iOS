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
        mainHandler.post {
            val errJson = error?.let { Json.write(mapOf("message" to (it.message ?: "bridge error"))) }
            webView().evaluateJavascript(
                "window.__splayerResolve(${org.json.JSONTokener(callId).nextValue()}," +
                    "$ok, ${json ?: "null"}, ${errJson ?: "null"});",
                null
            )
        }
    }

    /** 向渲染层推送事件（channel 与 preload subscribe 命名一致） */
    fun pushEvent(channel: String, payloadJson: String) {
        mainHandler.post {
            webView().evaluateJavascript(
                "window.__splayerDispatch(${org.json.JSONTokener(channel).nextValue()}, $payloadJson);",
                null
            )
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
}