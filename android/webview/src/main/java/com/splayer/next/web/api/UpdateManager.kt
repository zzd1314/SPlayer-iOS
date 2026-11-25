package com.splayer.next.web.api

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.splayer.next.web.BuildConfig
import com.splayer.next.web.Json
import com.splayer.next.web.SPlayerBridge
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Android 端更新通道：实现 preload 契约 update.*（getState / check / download / install / openDownloadPage）。
 *
 * 更新源与发布流程一致：仓库 GitHub Releases 中 tag 形如 `android-v<version>`、
 * 资产为 `*.apk`（见 .github/workflows/android.yml）。检查时取其中版本号最高且带 APK 的发布。
 * 状态通过 `update:event` 推送，结构与上游 UpdateEvent 对齐：{ state, notification?, manual? }。
 */
object UpdateManager {

    private const val CHANNEL = "update:event"
    private const val REPO = "zzd1314/SPlayer-iOS"
    private const val RELEASES_API = "https://api.github.com/repos/$REPO/releases?per_page=30"
    private const val RELEASES_PAGE = "https://github.com/$REPO/releases"
    private const val TAG_PREFIX = "android-v"
    private const val APK_SUFFIX = ".apk"
    private const val APK_FILE = "update.apk"

    private lateinit var appContext: Context
    private var bridge: SPlayerBridge? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Any()

    private var revision = 0
    private var phase = "idle"
    private var percent = 0
    private var meta: Map<String, Any?>? = null
    private var error: Map<String, Any?>? = null
    private var busy = false
    private var apkUrl: String? = null
    private var apkName = APK_FILE

    private val localVersion: String get() = BuildConfig.VERSION_NAME

    fun init(context: Context, bridgeRef: SPlayerBridge?) {
        appContext = context.applicationContext
        bridge = bridgeRef
    }

    // MARK: - 桥接入口

    fun handle(method: String, args: List<Any?>): Any? = when (method) {
        "getState" -> snapshot()
        "check" -> {
            val manual = (args.getOrNull(0) as? Boolean) ?: false
            if (manual || autoCheckEnabled()) check(manual)
            snapshot()
        }

        "download" -> {
            download()
            snapshot()
        }

        "install" -> {
            install()
            snapshot()
        }

        "openDownloadPage" -> {
            openDownloadPage()
            null
        }

        else -> throw BridgeUnsupportedException("update.$method 暂未在 Android 端实现")
    }

    private fun autoCheckEnabled(): Boolean =
        ConfigStore.shared(appContext).get("update.autoCheck") as? Boolean ?: true

    // MARK: - 快照与事件

    private fun snapshot(): Map<String, Any?> = synchronized(lock) { snapshotLocked() }

    private fun snapshotLocked(): Map<String, Any?> = linkedMapOf(
        "revision" to revision,
        "channel" to "stable",
        // Android 端始终可自行下载并调起安装器
        "mode" to "inApp",
        "phase" to phase,
        "meta" to meta,
        "percent" to percent,
        "error" to error,
    )

    /**
     * 提交一次状态变更并推送事件；revision 单调递增，渲染层据此丢弃迟到的事件。
     */
    private fun publish(
        patch: Map<String, Any?>,
        notification: String? = null,
        manual: Boolean = false,
    ) {
        val state = synchronized(lock) {
            (patch["phase"] as? String)?.let { phase = it }
            (patch["percent"] as? Number)?.let { percent = it.toInt() }
            if (patch.containsKey("meta")) meta = patch["meta"] as? Map<String, Any?>
            if (patch.containsKey("error")) error = patch["error"] as? Map<String, Any?>
            revision += 1
            snapshotLocked()
        }
        val event = linkedMapOf<String, Any?>("state" to state)
        if (notification != null) event["notification"] = notification
        event["manual"] = manual
        bridge?.pushEvent(CHANNEL, Json.write(event))
    }

    /** 仅进度变化：不携带 notification，渲染层只更新进度 */
    private fun publishPercent(value: Int) {
        val clamped = value.coerceIn(0, 100)
        val state = synchronized(lock) {
            if (percent == clamped) return
            percent = clamped
            revision += 1
            snapshotLocked()
        }
        bridge?.pushEvent(CHANNEL, Json.write(mapOf("state" to state)))
    }

    // MARK: - 检查更新

    private fun check(manual: Boolean) {
        synchronized(lock) {
            if (busy || phase == "installing") return
            busy = true
        }
        publish(mapOf("phase" to "checking", "meta" to null, "percent" to 0, "error" to null))
        scope.launch {
            try {
                val release = fetchLatest()
                if (release == null) {
                    publish(mapOf("phase" to "upToDate", "meta" to null), "upToDate", manual)
                    return@launch
                }
                if (compareVersion(release.version, localVersion) > 0) {
                    synchronized(lock) {
                        apkUrl = release.downloadUrl
                        apkName = release.assetName
                    }
                    publish(mapOf("phase" to "available", "meta" to release.meta), "available", manual)
                } else {
                    publish(mapOf("phase" to "upToDate", "meta" to null), "upToDate", manual)
                }
            } catch (e: Exception) {
                publish(
                    mapOf(
                        "phase" to "error",
                        "error" to mapOf("source" to "check", "message" to (e.message ?: "检查更新失败")),
                    ),
                    "error",
                    manual,
                )
            } finally {
                synchronized(lock) { busy = false }
            }
        }
    }

    private class Release(
        val version: String,
        val downloadUrl: String,
        val assetName: String,
        val meta: Map<String, Any?>,
    )

    /** 拉取 Releases，挑选 tag 为 android-v*、含 .apk 资产且版本最高的一条 */
    private fun fetchLatest(): Release? {
        val arr = JSONArray(httpGet(RELEASES_API))
        var best: Release? = null
        for (i in 0 until arr.length()) {
            val rel = arr.optJSONObject(i) ?: continue
            val tag = rel.optString("tag_name")
            if (!tag.startsWith(TAG_PREFIX)) continue
            val version = tag.removePrefix(TAG_PREFIX).trim()
            if (version.isEmpty()) continue
            val apk = firstApkAsset(rel.optJSONArray("assets")) ?: continue
            val meta = linkedMapOf<String, Any?>(
                "version" to version,
                "releaseNotes" to rel.optString("body"),
                "releaseDate" to rel.optString("published_at"),
                "size" to apk.optLong("size"),
                "releaseUrl" to rel.optString("html_url"),
            )
            val candidate = Release(
                version = version,
                downloadUrl = apk.optString("browser_download_url"),
                assetName = apk.optString("name", APK_FILE),
                meta = meta,
            )
            if (best == null || compareVersion(version, best.version) > 0) best = candidate
        }
        return best
    }

    private fun firstApkAsset(assets: JSONArray?): JSONObject? {
        if (assets == null) return null
        for (j in 0 until assets.length()) {
            val asset = assets.optJSONObject(j) ?: continue
            if (asset.optString("name").endsWith(APK_SUFFIX, ignoreCase = true)) return asset
        }
        return null
    }

    private fun httpGet(url: String): String {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 15_000
        conn.readTimeout = 20_000
        conn.instanceFollowRedirects = true
        conn.setRequestProperty("User-Agent", "SPlayer-Android/$localVersion")
        conn.setRequestProperty("Accept", "application/vnd.github+json")
        try {
            val code = conn.responseCode
            if (code !in 200..299) throw RuntimeException("HTTP $code")
            return conn.inputStream.bufferedReader().use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }

    // MARK: - 下载

    private fun download() {
        var srcUrl: String? = null
        synchronized(lock) {
            val retry = phase == "error" && error?.get("source") == "download"
            if (busy || meta == null || !(phase == "available" || retry)) return
            val url = apkUrl ?: return
            busy = true
            srcUrl = url
        }
        val url = srcUrl ?: return
        publish(mapOf("phase" to "downloading", "percent" to 0, "error" to null))
        scope.launch {
            val target = File(updateDir(), APK_FILE)
            try {
                downloadFile(url, target)
                publish(mapOf("phase" to "downloaded", "percent" to 100), "downloaded", true)
            } catch (e: Exception) {
                runCatching { target.delete() }
                publish(
                    mapOf(
                        "phase" to "error",
                        "error" to mapOf("source" to "download", "message" to (e.message ?: "下载失败")),
                    ),
                    "error",
                    true,
                )
            } finally {
                synchronized(lock) { busy = false }
            }
        }
    }

    private fun updateDir(): File = File(appContext.cacheDir, "updates").apply { mkdirs() }

    private fun downloadFile(url: String, target: File) {
        val part = File(target.parentFile, target.name + ".part")
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 20_000
        conn.readTimeout = 30_000
        conn.instanceFollowRedirects = true
        conn.setRequestProperty("User-Agent", "SPlayer-Android/$localVersion")
        try {
            val code = conn.responseCode
            if (code !in 200..299) throw RuntimeException("HTTP $code")
            val total = conn.contentLengthLong
            FileOutputStream(part).use { fos ->
                conn.inputStream.use { input ->
                    val buf = ByteArray(64 * 1024)
                    var received = 0L
                    var last = 0L
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        fos.write(buf, 0, n)
                        received += n
                        val now = System.currentTimeMillis()
                        if (total > 0 && now - last >= 250) {
                            last = now
                            publishPercent((received * 100 / total).toInt())
                        }
                    }
                }
            }
            if (!part.renameTo(target)) {
                part.copyTo(target, overwrite = true)
                part.delete()
            }
        } finally {
            conn.disconnect()
            if (part.exists()) part.delete()
        }
    }

    // MARK: - 安装

    private fun install() {
        val state = synchronized(lock) {
            if (busy || meta == null || phase == "installing") return
            val retry = phase == "error" && error?.get("source") == "install"
            if (phase != "downloaded" && !retry) return
            phase = "installing"
            revision += 1
            snapshotLocked()
        }
        bridge?.pushEvent(CHANNEL, Json.write(mapOf("state" to state)))

        val apk = File(updateDir(), APK_FILE)
        if (!apk.exists()) {
            installError("安装包不存在，请重新下载")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !appContext.packageManager.canRequestPackageInstalls()
        ) {
            runCatching {
                appContext.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${appContext.packageName}"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            }
            installError("请在系统设置中允许安装未知来源应用后重试")
            return
        }
        runCatching {
            val uri = FileProvider.getUriForFile(
                appContext,
                "${appContext.packageName}.fileprovider",
                apk,
            )
            appContext.startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
            )
        }.onFailure { e ->
            installError("无法启动安装器：${e.message}")
        }
    }

    private fun installError(message: String) {
        publish(
            mapOf("phase" to "error", "error" to mapOf("source" to "install", "message" to message)),
            "error",
            true,
        )
    }

    // MARK: - 打开发布页

    private fun openDownloadPage() {
        val url = synchronized(lock) { meta?.get("releaseUrl") as? String } ?: RELEASES_PAGE
        runCatching {
            appContext.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    // MARK: - 版本比较

    /** 逐段比较语义版本（如 1.1.10 > 1.1.9），非数字段视为 0 */
    private fun compareVersion(a: String, b: String): Int {
        fun parts(v: String): List<Int> =
            v.split('.', '-', '+').map { it.toIntOrNull() ?: 0 }

        val pa = parts(a)
        val pb = parts(b)
        val n = maxOf(pa.size, pb.size)
        for (i in 0 until n) {
            val diff = (pa.getOrNull(i) ?: 0) - (pb.getOrNull(i) ?: 0)
            if (diff != 0) return diff
        }
        return 0
    }
}
