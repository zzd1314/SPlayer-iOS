package com.splayer.next.web

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.KeyEvent
import android.view.ViewGroup
import android.webkit.ConsoleMessage
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.webkit.WebViewAssetLoader
import com.splayer.next.web.playback.PlaybackEngine
import java.lang.ref.WeakReference

/**
 * WebView 宿主：加载 SPlayer-Next 原版渲染层（Vue 前端），
 * 通过 SPlayerBridge 提供原 Electron 主进程能力的 Android 兼容实现。
 */
class WebHostActivity : AppCompatActivity() {

    companion object {
        private const val REQ_PICK_DIR = 4001
        private const val REQ_NOTIFICATION = 4002
        private const val REQ_RECORD_AUDIO = 4003

        @Volatile
        private var current: WeakReference<WebHostActivity>? = null

        /** 频谱需要 RECORD_AUDIO：等用户真正打开频谱时再申请，避免启动即弹权限 */
        fun requestRecordAudioPermissionIfNeeded() {
            val activity = current?.get() ?: return
            if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
            ) {
                return
            }
            runCatching {
                activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQ_RECORD_AUDIO)
            }
        }
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
        current = WeakReference(this)
        requestNotificationPermissionIfNeeded()

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

        // 渲染层 console 输出同步到 logcat，便于无 adb 之外的现场排查
        webView.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(msg: ConsoleMessage): Boolean {
                Log.d("SPlayerWeb", "${msg.message()} (${msg.sourceId()}:${msg.lineNumber()})")
                return true
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

    // MARK: - 通知权限（Android 13+ 媒体通知必需）

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        runCatching {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATION)
        }
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
        if (current?.get() === this) current = null
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
                // Vite 产物带 crossorigin，WebView 内以 CORS 模式加载会退化成 "Script error."
                // 同源资源无需该属性，移除后可拿到完整错误堆栈
                val stripped = html.replace(Regex("<script[^>]*>")) { it.value.replace(" crossorigin", "") }
                val injected = stripped.replace(Regex("<head([^>]*)>")) { match ->
                    match.value + "<script src=\"/assets/bridge.js\"></script>" + BOOT_GUARD
                }
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

/**
 * 启动守护脚本：渲染层 bootstrap 失败时上游不会移除 #app-loading（只会调用 startupFailed），
 * 真机上表现就是永远停在 logo。这里兜底捕获 JS 错误，8 秒后仍未进入主界面则覆盖显示诊断面板，
 * 同时把首条错误经 bridge 上报到 logcat（标签 SPlayerBoot）。
 */
private const val BOOT_GUARD = """
<script>
(function () {
  var errors = [];
  var counts = {};
  function report(msg) {
    try {
      var text = String(msg && msg.stack ? msg.stack : msg).slice(0, 2000);
      if (counts[text]) {
        counts[text]++;
      } else {
        counts[text] = 1;
        errors.push(text);
        if (errors.length > 20) delete counts[errors.shift()];
      }
      if (window.SPlayerNative && window.SPlayerNative.call) {
        try {
          window.SPlayerNative.call('system', 'reportBootError', 'boot-' + Date.now(), JSON.stringify([text]));
        } catch (e) {}
      }
    } catch (e) {}
  }
  function describe(e) {
    var where = e.filename ? '  @ ' + e.filename + ':' + (e.lineno || 0) + ':' + (e.colno || 0) : '';
    var detail = e.error && e.error.stack ? e.error.stack : (e.message || String(e.error));
    return detail + where;
  }
  window.__splayerBootErrors = errors;
  window.addEventListener('error', function (e) { report(describe(e)); });
  window.addEventListener('unhandledrejection', function (e) { report(e.reason); });
  var rawError = console.error;
  console.error = function () {
    report(Array.prototype.join.call(arguments, ' '));
    rawError.apply(console, arguments);
  };
  var shown = false;
  function showPanel() {
    if (shown) return;
    var splash = document.getElementById('app-loading');
    if (!splash) return;
    shown = true;
    var box = document.createElement('div');
    box.style.cssText = 'position:fixed;inset:0;z-index:100000;background:#101014;color:#e8e8ea;font:12px/1.6 monospace;padding:18px;overflow:auto;-webkit-user-select:text;user-select:text';
    var title = document.createElement('div');
    title.textContent = 'SPlayer 启动失败（诊断信息）';
    title.style.cssText = 'font-size:16px;font-weight:700;color:#fe7971;margin-bottom:10px';
    var meta = document.createElement('div');
    meta.style.cssText = 'white-space:pre-wrap;opacity:.65;margin-bottom:12px';
    meta.textContent = 'URL: ' + location.href + '\nUA: ' + navigator.userAgent;
    var list = document.createElement('div');
    list.style.cssText = 'white-space:pre-wrap;word-break:break-all';
    list.textContent = errors.length
      ? errors.map(function (t) { return (counts[t] > 1 ? '[' + counts[t] + '] ' : '') + t; }).join('\n\n')
      : '(未捕获到 JS 错误：可能是桥接调用无响应)';
    var probe = document.createElement('div');
    probe.style.cssText = 'white-space:pre-wrap;word-break:break-all;margin-top:14px;opacity:.85';
    probe.textContent = '正在检查脚本加载…';
    var button = document.createElement('button');
    button.textContent = '重新加载';
    button.style.cssText = 'margin-top:16px;padding:8px 16px;border-radius:8px;border:0;background:#fe7971;color:#101014;font-weight:700';
    button.onclick = function () { location.reload(); };
    box.appendChild(title);
    box.appendChild(meta);
    box.appendChild(list);
    box.appendChild(probe);
    box.appendChild(button);
    document.body.appendChild(box);
    var targets = ['/assets/bridge.js', '/assets/netease-api.js', '/assets/streaming-api.js'];
    var nodes = document.querySelectorAll('script[src]');
    for (var i = 0; i < nodes.length; i++) targets.push(nodes[i].getAttribute('src'));
    var seenUrl = {};
    var lines = [];
    var tasks = [];
    for (var j = 0; j < targets.length; j++) {
      var url = targets[j];
      if (!url || seenUrl[url]) continue;
      seenUrl[url] = true;
      tasks.push((function (u) {
        return fetch(u, { cache: 'no-store' }).then(function (r) {
          return r.text().then(function (body) {
            lines.push(u + ' → ' + r.status + ' ' + (r.headers.get('content-type') || '?') + ' ' + body.length + 'B');
          });
        }).catch(function (err) {
          lines.push(u + ' → 请求失败: ' + (err && err.message));
        });
      })(url));
    }
    Promise.all(tasks).then(function () {
      probe.textContent = '脚本加载检查:\n' + (lines.length ? lines.join('\n') : '(无可检查脚本)');
    });
  }
  setTimeout(showPanel, 8000);
})();
</script>
"""
