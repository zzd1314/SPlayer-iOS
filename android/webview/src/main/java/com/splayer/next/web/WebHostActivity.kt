package com.splayer.next.web

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.KeyEvent
import android.view.ViewGroup
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity
import androidx.webkit.WebViewAssetLoader
import com.splayer.next.web.playback.PlaybackEngine

/**
 * WebView 宿主：加载 SPlayer-Next 原版渲染层（Vue 前端），
 * 通过 SPlayerBridge 提供原 Electron 主进程能力的 Android 兼容实现。
 */
class WebHostActivity : AppCompatActivity() {

    companion object {
        private const val REQ_PICK_DIR = 4001
    }

    lateinit var webView: WebView
        private set
    lateinit var bridge: SPlayerBridge
        private set

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val context = applicationContext
        bridge = SPlayerBridge(this, context)

        webView = WebView(this)
        webView.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            mediaPlaybackRequiresUserGesture = false
            cacheMode = WebSettings.LOAD_DEFAULT
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            allowFileAccess = false
            allowContentAccess = false
            // 原版为桌面应用，保持桌面 UA 以获得 1:1 布局与交互
            userAgentString = userAgentString.replace("; wv)", "")
        }
        webView.setBackgroundColor(android.graphics.Color.TRANSPARENT)

        val loader = WebViewAssetLoader.Builder()
            .setDomain("appassets.androidplatform.net")
            .addPathHandler("/assets/", RendererAssetHandler(this))
            .addPathHandler("/localfile/", LocalFileHandler(this))
            .build()

        webView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(
                view: WebView,
                request: WebResourceRequest
            ): WebResourceResponse? = loader.shouldInterceptRequest(request.url)

            override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) {
                bridge.onHistoryChanged()
                super.doUpdateVisitedHistory(view, url, isReload)
            }
        }

        webView.addJavascriptInterface(bridge.native, "SPlayerNative")
        setContentView(webView)

        // 播放引擎惰性初始化（首次加载音频时启动后台服务）
        PlaybackEngine.init(context, bridge)

        webView.loadUrl("https://appassets.androidplatform.net/assets/index.html")
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        // 系统返回键交给原版前端路由处理
        if (keyCode == KeyEvent.KEYCODE_BACK && bridge.consumeBack()) {
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    // MARK: - SAF 目录选择（download.pickDir）

    /** 发起系统目录选择器；结果经 onDirectoryPicked 回填桥 */
    fun launchDirectoryPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        intent.addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        runCatching { startActivityForResult(intent, REQ_PICK_DIR) }
            .onFailure { bridge.onDirectoryPicked(null) }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_PICK_DIR) {
            val uri = if (resultCode == RESULT_OK) data?.data?.toString() else null
            if (uri != null) {
                // 持久化授权，重启后仍可写入
                runCatching {
                    contentResolver.takePersistableUriPermission(
                        android.net.Uri.parse(uri),
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                }
            }
            bridge.onDirectoryPicked(uri)
        }
    }

    override fun onDestroy() {
        // 播放引擎保活（后台播放），仅销毁 WebView
        if (webView.parent != null) {
            (webView.parent as ViewGroup).removeView(webView)
        }
        webView.destroy()
        super.onDestroy()
    }
}

/**
 * 本地文件处理器：/localfile/<token> → LibraryStore 封面 token 解析，
 * 供渲染层 <img> 直接加载 MediaStore 专辑封面。
 */
class LocalFileHandler(context: Context) : WebViewAssetLoader.PathHandler {

    private val appContext = context.applicationContext

    override fun handle(path: String): WebResourceResponse? {
        val token = path.trim('/').substringBefore('.')
        val uri = com.splayer.next.web.api.LibraryStore.shared(appContext).resolveCoverToken(token)
            ?: return null
        return runCatching {
            val stream = appContext.contentResolver.openInputStream(uri) ?: return null
            WebResourceResponse("image/*", null, stream)
        }.getOrNull()
    }
}

/**
 * 渲染层静态资源处理器：assets/web/ 即 electron-vite 的 out/renderer 产物。
 * index.html 会在 head 注入 bridge.js，保证 window.api 在业务代码执行前就绪。
 */
class RendererAssetHandler(private val context: Context) : WebViewAssetLoader.PathHandler {

    override fun handle(path: String): WebResourceResponse? {
        val clean = path.trim('/').ifEmpty { "index.html" }
        return runCatching {
            if (clean == "index.html") {
                val html = context.assets.open("web/index.html")
                    .bufferedReader().use { it.readText() }
                val injected = html.replace(
                    Regex("<head([^>]*)>"),
                    "$0<script src=\"/assets/bridge.js\"></script>"
                )
                response("text/html", injected.toByteArray())
            } else {
                val stream = context.assets.open("web/$clean")
                response(guessMime(clean), null, stream)
            }
        }.getOrNull()
    }

    private fun response(
        mime: String,
        body: ByteArray?,
        stream: java.io.InputStream? = null
    ): WebResourceResponse {
        val res = WebResourceResponse(mime, "utf-8", stream ?: body?.inputStream())
        res.responseHeaders = mapOf("Access-Control-Allow-Origin" to "*")
        return res
    }

    private fun guessMime(path: String): String = when (path.substringAfterLast('.', "")) {
        "html" -> "text/html"
        "js", "mjs" -> "application/javascript"
        "css" -> "text/css"
        "json" -> "application/json"
        "svg" -> "image/svg+xml"
        "png" -> "image/png"
        "jpg", "jpeg" -> "image/jpeg"
        "gif" -> "image/gif"
        "webp" -> "image/webp"
        "ico" -> "image/x-icon"
        "woff" -> "font/woff"
        "woff2" -> "font/woff2"
        "ttf" -> "font/ttf"
        "otf" -> "font/otf"
        "txt" -> "text/plain"
        "wasm" -> "application/wasm"
        else -> "application/octet-stream"
    }
}