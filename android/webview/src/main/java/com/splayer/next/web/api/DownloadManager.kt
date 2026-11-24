package com.splayer.next.web.api

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import com.splayer.next.web.Json
import com.splayer.next.web.SPlayerBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Android 端下载管理器：实现 preload 契约 download.* 的 14 个方法。
 * 复刻 electron/main/services/download 的任务模型：
 * 任务缺 URL 时推送 download:resolve 让渲染层解析，回传后开始 HTTP 下载。
 * 下载目录默认应用专属 Music 目录（免权限），SAF 目录选择后持久化 tree uri。
 */
object DownloadManager {
    private const val CHANNEL_PROGRESS = "download:progress"
    private const val CHANNEL_STATE = "download:state"
    private const val CHANNEL_RESOLVE = "download:resolve"
    private const val DIR_PREF_KEY = "splayer:download:dir"

    private lateinit var appContext: Context
    private var bridge: SPlayerBridge? = null

    /** 下载队列执行器（最多 2 并发，避免并发写竞争与网络过载） */
    private val executor = Executors.newFixedThreadPool(2)
    private val scope = kotlinx.coroutines.CoroutineScope(Dispatchers.IO)

    /** taskId → 任务（与原版 DownloadTask 字段一致） */
    private val tasks = LinkedHashMap<String, JSONObject>()

    /** 取消标记 */
    private val canceled = ConcurrentHashMap<String, Boolean>()

    /** 正在等待渲染层解析的任务（payload 待推） */
    private val pendingResolve = ConcurrentHashMap<String, JSONObject>()

    fun init(context: Context, bridgeRef: SPlayerBridge?) {
        appContext = context.applicationContext
        bridge = bridgeRef
    }

    // MARK: - 目录

    private fun defaultDir(): File =
        File(appContext.getExternalFilesDir(Environment.DIRECTORY_MUSIC), "SPlayer")

    private fun configuredDir(): String {
        val saved = ConfigStore.shared(appContext).get(DIR_PREF_KEY) as? String
        return saved ?: defaultDir().absolutePath
    }

    /** SAF tree uri → 输出目录（DocumentFile 语义在纯 java 层用 DocumentsContract 手工实现） */
    private fun safRootUri(): Uri? {
        val saved = ConfigStore.shared(appContext).get(DIR_PREF_KEY) as? String
        if (saved != null && saved.startsWith("content://")) return Uri.parse(saved)
        return null
    }

    // MARK: - 桥接方法

    fun handle(method: String, args: List<Any?>): Any? = when (method) {
        "start", "retry" -> enqueue(asMap(args.getOrNull(0)))
        "startMany" -> (args.getOrNull(0) as? List<*>)?.map { enqueue(asMap(it)) } ?: emptyList<Any>()
        "cancel" -> cancel(args.getOrNull(0) as? String ?: "")
        "submitResolution" -> submitResolution(
            args.getOrNull(0) as? String ?: "",
            asMap(args.getOrNull(1)),
        )
        "resolveFailed" -> failResolution(args.getOrNull(0) as? String ?: "")
        "remove" -> remove(args.getOrNull(0) as? String ?: "")
        "clearFinished" -> clearFinished()
        "list" -> tasks.values.toList().map { Json.toMap(it) }
        "lookup" -> lookup(asMap(args.getOrNull(0)))
        "pickDir" -> pickDir()
        "getDir" -> configuredDir()
        "resetDir" -> {
            ConfigStore.shared(appContext).set(DIR_PREF_KEY, null)
            configuredDir()
        }
        else -> throw BridgeUnsupportedException("download.$method 暂未在 Android 端实现")
    }

    private fun asMap(value: Any?): Map<*, *> = value as? Map<*, *> ?: emptyMap<Any?, Any?>()

    // MARK: - 入队

    /** 复刻 enqueue：去重（queued / downloaded）→ 缺 URL 走解析流程 → 就绪后启动下载 */
    @Synchronized
    private fun enqueue(req: Map<*, *>): Map<String, Any?> {
        if (req.isEmpty()) return mapOf("ok" to false)
        val taskId = req["taskId"] as? String ?: return mapOf("ok" to false)
        val track = asMap(req["track"])
        val qualityLevel = req["qualityLevel"]

        // 同曲同音质去重
        val key = dedupeKey(track, qualityLevel)
        for (task in tasks.values) {
            if (task.optString("qualityLevel") == qualityLevel.toString() &&
                task.optString("dedupeKey") == key &&
                task.optString("status") in setOf("queued", "downloading")
            ) {
                return mapOf("ok" to false, "reason" to "queued")
            }
        }

        val existing = lookup(track)
        if (existing != null) return mapOf("ok" to false, "reason" to "downloaded")

        val tagOptions = asMap(req["tagOptions"])
        val task = JSONObject().apply {
            put("taskId", taskId)
            put("status", "queued")
            put("track", Json.write(track))
            put("qualityLevel", qualityLevel?.toString() ?: "")
            put("received", 0L)
            put("total", (req["declaredSize"] as? Number)?.toLong() ?: 0L)
            put("createdAt", System.currentTimeMillis())
            put("dedupeKey", key)
            put("declaredFormat", req["declaredFormat"]?.toString() ?: "")
            put("coverUrl", req["coverUrl"]?.toString() ?: "")
            put("lyricText", req["lyricText"]?.toString() ?: "")
            put("lyricFileFormat", req["lyricFileFormat"]?.toString() ?: "lrc")
            put("writeLrc", tagOptions["writeLrc"] == true)
            put("url", req["url"]?.toString() ?: "")
        }
        tasks[taskId] = task
        pushState(task)
        if (task.optString("url").isNotEmpty()) {
            startDownload(taskId)
        } else {
            // 通知渲染层解析 URL（复刻 download:resolve 推送）
            pendingResolve[taskId] = task
            bridge?.pushEvent(
                CHANNEL_RESOLVE,
                JSONObject().apply {
                    put("taskId", taskId)
                    put("track", task.optJSONObject("track") ?: JSONObject())
                    put("qualityLevel", task.optString("qualityLevel"))
                }.toString(),
            )
        }
        return mapOf("ok" to true)
    }

    private fun dedupeKey(track: Map<*, *>, quality: Any?): String {
        val raw = listOf(
            track["source"]?.toString() ?: "",
            track["id"]?.toString() ?: "",
            track["serverId"]?.toString() ?: "",
            track["originalId"]?.toString() ?: "",
            quality?.toString() ?: "",
        ).joinToString("|")
        val md = MessageDigest.getInstance("MD5")
        return md.digest(raw.toByteArray()).joinToString("") { "%02x".format(it) }
    }

    // MARK: - 渲染层回传

    @Synchronized
    private fun submitResolution(taskId: String, res: Map<*, *>): Any? {
        val task = tasks[taskId] ?: return null
        val url = res["url"] as? String
        if (url.isNullOrEmpty()) {
            failResolution(taskId)
            return null
        }
        task.put("url", url)
        res["declaredFormat"]?.let { task.put("declaredFormat", it.toString()) }
        res["declaredSize"]?.let { if (it is Number) task.put("total", it.toLong()) }
        res["lyricText"]?.let { task.put("lyricText", it.toString()) }
        startDownload(taskId)
        return null
    }

    @Synchronized
    private fun failResolution(taskId: String): Any? {
        tasks[taskId]?.let { task ->
            task.put("status", "failed")
            task.put("errorCode", "RESOLVE_FAILED")
            task.put("finishedAt", System.currentTimeMillis())
            pushState(task)
        }
        pendingResolve.remove(taskId)
        return null
    }

    // MARK: - 下载执行

    private fun startDownload(taskId: String) {
        scope.launch(Dispatchers.IO) {
            val task = tasks[taskId] ?: return@launch
            task.put("status", "downloading")
            pushState(task)
            try {
                val file = downloadFile(task)
                task.put("filePath", file)
                task.put("status", "done")
                task.put("finishedAt", System.currentTimeMillis())
            } catch (e: Exception) {
                if (canceled.remove(taskId) == true) {
                    task.put("status", "canceled")
                } else {
                    task.put("status", "failed")
                    task.put("errorCode", e.message?.take(120) ?: "DOWNLOAD_ERROR")
                }
                task.put("finishedAt", System.currentTimeMillis())
            }
            pushState(task)
        }
    }

    private fun downloadFile(task: JSONObject): String {
        val taskId = task.optString("taskId")
        val url = task.optString("url")
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 15000
        conn.readTimeout = 30000
        conn.instanceFollowRedirects = true
        val respCode = conn.responseCode
        if (respCode !in 200..299) throw RuntimeException("HTTP $respCode")
        val total = conn.contentLengthLong.takeIf { it > 0 } ?: task.optLong("total")

        val fileName = buildFileName(task)
        val safRoot = safRootUri()
        val received = java.util.concurrent.atomic.AtomicLong(0)
        conn.inputStream.use { input ->
            if (safRoot != null) {
                writeSaf(safRoot, fileName, input, taskId, received, total)
            } else {
                val dir = configuredDir()
                File(dir).mkdirs()
                val out = File(dir, fileName)
                FileOutputStream(out).use { fos ->
                    val buf = ByteArray(32 * 1024)
                    while (true) {
                        if (canceled[taskId] == true) throw RuntimeException("canceled")
                        val n = input.read(buf)
                        if (n < 0) break
                        fos.write(buf, 0, n)
                        val now = received.addAndGet(n.toLong())
                        pushProgress(taskId, now, total)
                    }
                }
            }
        }
        conn.disconnect()

        // 歌词文件（writeLrc 选项）
        if (task.optBoolean("writeLrc")) {
            val lyric = task.optString("lyricText")
            if (lyric.isNotEmpty()) {
                try {
                    val lrcName = fileName.substringBeforeLast('.') + ".lrc"
                    if (safRoot != null) writeSafText(safRoot, lrcName, lyric)
                    else File(configuredDir(), lrcName).writeText(lyric)
                } catch (_: Exception) {
                    // 歌词写失败不影响音频任务
                }
            }
        }
        return fileName
    }

    /** 生成文件名：歌手 - 标题.ext（复刻原版命名主体逻辑） */
    private fun buildFileName(task: JSONObject): String {
        val track = Json.toMap(task.optJSONObject("track") ?: JSONObject())
        val artist = (track["artists"] as? List<*>)?.firstOrNull()?.let { (it as? Map<*, *>)?.get("name") } ?: ""
        val title = track["title"]?.toString() ?: "unknown"
        val format = task.optString("declaredFormat")
        val ext = if (format.isNotEmpty()) format.removePrefix(".") else "mp3"
        val base = listOf(artist.toString(), "$title").filter { it.isNotBlank() }.joinToString(" - ")
            .replace(Regex("[\\\\/:*?\"<>|]"), "_")
        return "$base.$ext"
    }

    private fun writeSaf(
        treeRoot: Uri,
        fileName: String,
        input: java.io.InputStream,
        taskId: String,
        received: java.util.concurrent.atomic.AtomicLong,
        total: Long,
    ) {
        val docUri = DocumentsContract.buildDocumentUriUsingTree(
            treeRoot,
            DocumentsContract.getTreeDocumentId(treeRoot),
        )
        val ext = fileName.substringAfterLast('.', "")
        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "audio/mpeg"
        val created = DocumentsContract.createDocument(
            appContext.contentResolver,
            docUri,
            mime,
            fileName,
        ) ?: throw RuntimeException("SAF create failed")
        appContext.contentResolver.openOutputStream(created)?.use { os ->
            val buf = ByteArray(32 * 1024)
            while (true) {
                if (canceled[taskId] == true) throw RuntimeException("canceled")
                val n = input.read(buf)
                if (n < 0) break
                os.write(buf, 0, n)
                pushProgress(taskId, received.addAndGet(n.toLong()), total)
            }
        } ?: throw RuntimeException("SAF open stream failed")
    }

    private fun writeSafText(treeRoot: Uri, fileName: String, text: String) {
        val docUri = DocumentsContract.buildDocumentUriUsingTree(
            treeRoot,
            DocumentsContract.getTreeDocumentId(treeRoot),
        )
        val created = DocumentsContract.createDocument(
            appContext.contentResolver,
            docUri,
            "text/plain",
            fileName,
        ) ?: return
        appContext.contentResolver.openOutputStream(created)?.use { os ->
            os.write(text.toByteArray(Charsets.UTF_8))
        }
    }

    private var lastProgressAt = 0L

    @Synchronized
    private fun pushProgress(taskId: String, received: Long, total: Long) {
        val now = System.currentTimeMillis()
        if (now - lastProgressAt < 300) return
        lastProgressAt = now
        tasks[taskId]?.put("received", received)
        if (total > 0) tasks[taskId]?.put("total", total)
        bridge?.pushEvent(
            CHANNEL_PROGRESS,
            JSONObject().apply {
                put("taskId", taskId)
                put("received", received)
                put("total", total)
            }.toString(),
        )
    }

    private fun pushState(task: JSONObject) {
        bridge?.pushEvent(CHANNEL_STATE, task.toString())
    }

    // MARK: - 任务操作

    @Synchronized
    private fun cancel(taskId: String): Any? {
        canceled[taskId] = true
        pendingResolve.remove(taskId)
        tasks[taskId]?.let { task ->
            if (task.optString("status") in setOf("queued", "downloading")) {
                task.put("status", "canceled")
                task.put("finishedAt", System.currentTimeMillis())
                pushState(task)
            }
        }
        return null
    }

    @Synchronized
    private fun remove(taskId: String): Any? {
        tasks.remove(taskId)
        canceled.remove(taskId)
        pendingResolve.remove(taskId)
        return null
    }

    @Synchronized
    private fun clearFinished(): Any? {
        val iter = tasks.entries.iterator()
        while (iter.hasNext()) {
            val st = iter.next().value.optString("status")
            if (st in setOf("done", "failed", "canceled", "interrupted")) iter.remove()
        }
        return null
    }

    /** 按歌曲身份查找已完成任务的文件路径（返回 filePath 或 null） */
    private fun lookup(track: Map<*, *>): String? {
        val key = dedupeKey(
            track,
            null,
        )
        for (task in tasks.values) {
            if (task.optString("dedupeKey").substringBefore("|done") == key ||
                task.optString("status") == "done"
            ) {
                val t = Json.toMap(task.optJSONObject("track") ?: JSONObject())
                if (t["source"] == track["source"] && t["id"] == track["id"] &&
                    (t["serverId"] ?: "") == (track["serverId"] ?: "")
                ) {
                    return task.optString("filePath").ifEmpty { null }
                }
            }
        }
        return null
    }

    /** SAF 目录选择：经 WebHostActivity 转发 ACTION_OPEN_DOCUMENT_TREE */
    private fun pickDir(): Any? {
        val result = bridge?.requestPickDir()
        return if (result.isNullOrEmpty()) {
            mapOf("ok" to false, "dir" to "", "reason" to "canceled")
        } else {
            ConfigStore.shared(appContext).set(DIR_PREF_KEY, result)
            mapOf("ok" to true, "dir" to result)
        }
    }
}