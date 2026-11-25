package com.splayer.next.web.api

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import com.splayer.next.web.Json
import com.splayer.next.web.SPlayerBridge
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/**
 * Android 端下载管理器：实现 preload 契约 download.* 的全部方法。
 *
 * 与上游 electron/main/services/downloadManager.ts 对齐：
 *  - 单任务串行队列（一次只下一首），缺 URL 时推 download:resolve 等渲染层回传
 *  - 任务表落盘（download_tasks.json），重启后进行中任务标记 interrupted
 *  - 文件名模板 / 智能分类目录 / 重名策略（rename / overwrite / skip）
 *  - 完成后写同名 .lrc / .ttml 歌词；标签内嵌在 Android 端不支持（tagWarning 恒 false）
 */
object DownloadManager {
    private const val CHANNEL_PROGRESS = "download:progress"
    private const val CHANNEL_STATE = "download:state"
    private const val CHANNEL_RESOLVE = "download:resolve"
    private const val DIR_PREF_KEY = "splayer:download:dir"
    private const val STATE_FILE = "download_tasks.json"
    private const val RESOLVE_TIMEOUT_MS = 180_000L

    private lateinit var appContext: Context
    private var bridge: SPlayerBridge? = null

    private val scope = CoroutineScope(Dispatchers.IO)
    private val lock = Any()

    /** taskId → 任务（字段与上游 DownloadTask 一致，track 为嵌套对象） */
    private val tasks = LinkedHashMap<String, JSONObject>()

    /** 串行下载队列 */
    private val queue = ArrayDeque<String>()
    private var active: String? = null

    /** 取消标记（进行中任务中断信号） */
    private val canceled = ConcurrentHashMap<String, Boolean>()
    private val removed = ConcurrentHashMap<String, Boolean>()

    /** 等待渲染层回传解析结果 */
    private val resolveGates = ConcurrentHashMap<String, CompletableDeferred<Map<*, *>?>>()

    /** taskId → 上次进度推送时间 */
    private val lastProgressAt = ConcurrentHashMap<String, Long>()

    fun init(context: Context, bridgeRef: SPlayerBridge?) {
        appContext = context.applicationContext
        bridge = bridgeRef
        loadPersisted()
    }

    // MARK: - 目录

    private fun defaultDir(): File =
        File(appContext.getExternalFilesDir(Environment.DIRECTORY_MUSIC), "SPlayer")

    private fun configuredDir(): String {
        val saved = ConfigStore.shared(appContext).get(DIR_PREF_KEY) as? String
        return saved ?: defaultDir().absolutePath
    }

    /** SAF tree uri → 输出目录（DocumentsContract 直写） */
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
        "list" -> listTasks()
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

    // MARK: - 持久化

    private fun stateFile(): File = File(appContext.filesDir, STATE_FILE)

    private fun loadPersisted() {
        val file = stateFile()
        if (!file.exists()) return
        runCatching {
            val arr = JSONArray(file.readText())
            synchronized(lock) {
                for (i in 0 until arr.length()) {
                    val t = arr.optJSONObject(i) ?: continue
                    val id = t.optString("taskId")
                    if (id.isEmpty()) continue
                    // 重启后残留的进行中任务一律标记中断，交由渲染层「重试」
                    if (t.optString("status") in setOf("queued", "downloading")) {
                        t.put("status", "interrupted")
                        t.put("finishedAt", System.currentTimeMillis())
                    }
                    tasks[id] = t
                }
            }
        }
    }

    private fun savePersisted() {
        val snapshot = synchronized(lock) {
            JSONArray().apply { tasks.values.forEach { put(JSONObject(it.toString())) } }
        }
        runCatching { stateFile().writeText(snapshot.toString()) }
    }

    // MARK: - 入队

    /** 复刻 enqueue：去重 → 建任务 → 入串行队列 */
    @Synchronized
    private fun enqueue(req: Map<*, *>): Map<String, Any?> {
        if (req.isEmpty()) return mapOf("ok" to false)
        val taskId = req["taskId"] as? String ?: return mapOf("ok" to false)
        val track = asMap(req["track"])
        val qualityLevel = req["qualityLevel"]?.toString().orEmpty()
        val dedupeKey = dedupeKey(track, qualityLevel)

        // 同曲同音质已在队列 / 下载中
        if (active == taskId || queue.contains(taskId)) return mapOf("ok" to false, "reason" to "queued")
        tasks[taskId]?.let {
            if (it.optString("status") in setOf("queued", "downloading")) {
                return mapOf("ok" to false, "reason" to "queued")
            }
        }
        for (t in tasks.values) {
            if (t.optString("dedupeKey") == dedupeKey &&
                t.optString("status") in setOf("queued", "downloading")
            ) {
                return mapOf("ok" to false, "reason" to "queued")
            }
        }
        // 已下载过同曲同音质且文件仍在 → 拦下
        findCompleted(track, qualityLevel)?.let { return mapOf("ok" to false, "reason" to "downloaded") }

        val tagOptions = asMap(req["tagOptions"])
        val task = JSONObject().apply {
            put("taskId", taskId)
            put("status", "queued")
            put("track", JSONObject(Json.write(track)))
            put("qualityLevel", qualityLevel)
            put("received", 0L)
            put("total", (req["declaredSize"] as? Number)?.toLong() ?: 0L)
            put("createdAt", System.currentTimeMillis())
            put("dedupeKey", dedupeKey)
            put("declaredFormat", req["declaredFormat"]?.toString() ?: "")
            put("coverUrl", req["coverUrl"]?.toString() ?: "")
            put("lyricText", req["lyricText"]?.toString() ?: "")
            put("ttmlText", req["ttmlText"]?.toString() ?: "")
            put("writeLrc", tagOptions["writeLrc"] == true)
            put("saveTtml", tagOptions["saveTtml"] == true)
            put("tagWarning", false)
            put("url", req["url"]?.toString() ?: "")
        }
        tasks[taskId] = task
        canceled.remove(taskId)
        removed.remove(taskId)
        queue.addLast(taskId)
        pushState(task)
        pump()
        return mapOf("ok" to true)
    }

    private fun dedupeKey(track: Map<*, *>, quality: String): String {
        val raw = listOf(
            track["source"]?.toString() ?: "",
            track["id"]?.toString() ?: "",
            track["serverId"]?.toString() ?: "",
            track["originalId"]?.toString() ?: "",
            track["serverRevision"]?.toString() ?: "0",
            quality,
        ).joinToString("|")
        val md = MessageDigest.getInstance("MD5")
        return md.digest(raw.toByteArray()).joinToString("") { "%02x".format(it) }
    }

    /** 已完成且文件仍在的同曲同音质任务 */
    private fun findCompleted(track: Map<*, *>, quality: String): JSONObject? {
        val candidates = synchronized(lock) { tasks.values.toList() }
        return candidates.firstOrNull { t ->
            if (t.optString("status") != "done" || t.optString("qualityLevel") != quality) return@firstOrNull false
            val t1 = t.optJSONObject("track") ?: return@firstOrNull false
            if (t1.optString("source") != track["source"]?.toString()) return@firstOrNull false
            if (t1.optString("id") != track["id"]?.toString()) return@firstOrNull false
            if (track["source"]?.toString() == "streaming") {
                if (t1.optString("serverRevision", "0") != (track["serverRevision"]?.toString() ?: "0")) {
                    return@firstOrNull false
                }
            }
            fileExists(t.optString("filePath"))
        }
    }

    private fun fileExists(path: String): Boolean {
        if (path.isEmpty()) return false
        if (path.startsWith("content://")) return true
        return File(path).exists()
    }

    // MARK: - 串行队列

    @Synchronized
    private fun pump() {
        if (active != null) return
        val next = queue.removeFirstOrNull() ?: return
        active = next
        scope.launch { runTask(next) }
    }

    private fun finishTask(taskId: String) {
        synchronized(lock) {
            if (active == taskId) active = null
        }
        resolveGates.remove(taskId)
        canceled.remove(taskId)
        pump()
    }

    private fun runTask(taskId: String) {
        val task = synchronized(lock) { tasks[taskId] } ?: return finishTask(taskId)
        try {
            setStatus(task, "downloading")
            if (task.optString("url").isEmpty()) {
                val gate = CompletableDeferred<Map<*, *>?>()
                resolveGates[taskId] = gate
                bridge?.pushEvent(
                    CHANNEL_RESOLVE,
                    JSONObject().apply {
                        put("taskId", taskId)
                        put("track", task.optJSONObject("track") ?: JSONObject())
                        put("qualityLevel", task.optString("qualityLevel"))
                        put("coverUrl", task.optString("coverUrl"))
                        put("lyricFileFormat", "lrc")
                    }.toString(),
                )
                val res = runBlocking { withTimeoutOrNull(RESOLVE_TIMEOUT_MS) { gate.await() } }
                if (canceled[taskId] == true) throw RuntimeException("canceled")
                if (res == null || res["url"]?.toString().isNullOrEmpty()) {
                    throw RuntimeException("RESOLVE_FAILED")
                }
                task.put("url", res["url"].toString())
                res["declaredFormat"]?.let { task.put("declaredFormat", it.toString()) }
                res["declaredSize"]?.let { if (it is Number) task.put("total", it.toLong()) }
                res["lyricText"]?.let { task.put("lyricText", it.toString()) }
                res["ttmlText"]?.let { task.put("ttmlText", it.toString()) }
            }
            downloadTask(task)
            if (removed[taskId] == true) return
            task.put("status", "done")
            task.put("finishedAt", System.currentTimeMillis())
            pushState(task)
        } catch (e: Exception) {
            if (removed[taskId] == true) return
            runCatching { File(task.optString("partPath")).delete() }
            task.put("finishedAt", System.currentTimeMillis())
            if (canceled[taskId] == true) {
                task.put("status", "canceled")
            } else {
                task.put("status", "failed")
                task.put(
                    "errorCode",
                    when {
                        e.message?.contains("REJECTED_MIME") == true -> "PERMISSION_DENIED"
                        else -> "UNKNOWN"
                    },
                )
            }
            pushState(task)
        } finally {
            finishTask(taskId)
        }
    }

    private fun downloadTask(task: JSONObject) {
        val taskId = task.optString("taskId")
        val audioUrl = task.optString("url")
        val conn = URL(audioUrl).openConnection() as HttpURLConnection
        conn.connectTimeout = 15_000
        conn.readTimeout = 30_000
        conn.instanceFollowRedirects = true
        val respCode = conn.responseCode
        if (respCode !in 200..299) throw RuntimeException("HTTP $respCode")
        val mime = conn.contentType
        if (isRejectedMime(mime)) throw RuntimeException("REJECTED_MIME $mime")

        val ext = resolveExtension(task.optString("declaredFormat"), mime, audioUrl)
        val total = conn.contentLengthLong.takeIf { it > 0 } ?: task.optLong("total")
        val track = Json.toMap(task.optJSONObject("track") ?: JSONObject())
        val (relDir, baseName) = renderDownloadPath(track)
        val policy = overridePolicy()
        val safRoot = safRootUri()
        val received = java.util.concurrent.atomic.AtomicLong(0)

        if (safRoot != null) {
            // SAF 目录：直接创建文档写入（无法先写 part 再改名）
            val uri = conn.inputStream.use { input ->
                writeSaf(safRoot, "$baseName$ext", input, taskId, received, total)
            }
            conn.disconnect()
            task.put("filePath", uri)
            task.put("received", received.get())
            if (total > 0) task.put("total", total)
            writeSidecars(task, safRoot, "$baseName$ext", null)
            return
        }

        val dir = File(configuredDir(), relDir).apply { mkdirs() }
        var target = File(dir, "$baseName$ext")
        if (policy == "skip" && target.exists()) {
            conn.disconnect()
            task.put("filePath", target.absolutePath)
            task.put("received", target.length())
            task.put("total", target.length())
            return
        }
        if (policy == "rename") target = dedupeFile(target)

        val part = File(dir, ".${taskId}.part")
        task.put("partPath", part.absolutePath)
        conn.inputStream.use { input ->
            FileOutputStream(part).use { fos ->
                val buf = ByteArray(32 * 1024)
                while (true) {
                    if (canceled[taskId] == true) throw RuntimeException("canceled")
                    val n = input.read(buf)
                    if (n < 0) break
                    fos.write(buf, 0, n)
                    pushProgress(taskId, received.addAndGet(n.toLong()), total)
                }
            }
        }
        conn.disconnect()
        if (received.get() == 0L) {
            part.delete()
            throw RuntimeException("empty body")
        }

        if (policy == "overwrite" && target.exists()) target.delete()
        if (target.exists()) target = dedupeFile(target)
        if (!part.renameTo(target)) {
            part.copyTo(target, overwrite = true)
            part.delete()
        }
        task.put("filePath", target.absolutePath)
        task.put("received", received.get())
        task.put("total", if (total > 0) total else received.get())
        writeSidecars(task, null, target.name, dir)
    }

    /** 同名歌词文件：所选格式 .lrc + 完整 .ttml，失败不影响音频 */
    private fun writeSidecars(task: JSONObject, safRoot: Uri?, fileName: String, dir: File?) {
        if (task.optBoolean("writeLrc")) {
            val lyric = task.optString("lyricText")
            if (lyric.isNotEmpty()) {
                val name = fileName.substringBeforeLast('.') + ".lrc"
                runCatching {
                    if (safRoot != null) writeSafText(safRoot, name, lyric)
                    else File(dir, name).writeText(lyric)
                }
            }
        }
        if (task.optBoolean("saveTtml")) {
            val ttml = task.optString("ttmlText")
            if (ttml.isNotEmpty()) {
                val name = fileName.substringBeforeLast('.') + ".ttml"
                runCatching {
                    if (safRoot != null) writeSafText(safRoot, name, ttml)
                    else File(dir, name).writeText(ttml)
                }
            }
        }
    }

    // MARK: - 文件名

    private data class DownloadPath(val relDir: String, val baseName: String)

    /**
     * 复刻 renderDownloadPath：文件名模板 {artist}/{title}/{album}，
     * 智能分类 none / artist / artist-album 决定子目录，非法字符清洗。
     */
    private fun renderDownloadPath(track: Map<*, *>): DownloadPath {
        val artists = (track["artists"] as? List<*>)?.mapNotNull {
            (it as? Map<*, *>)?.get("name")?.toString()
        }.orEmpty()
        val artist = artists.joinToString("/")
        val title = track["title"]?.toString() ?: "untitled"
        val album = (track["album"] as? Map<*, *>)?.get("name")?.toString() ?: ""
        val cfg = ConfigStore.shared(appContext)
        val scheme = cfg.get("download.folderScheme") as? String ?: "none"
        val template = cfg.get("download.fileTemplate") as? String ?: "{artist} - {title}"
        val filled = template
            .replace("{artist}", artist)
            .replace("{title}", title)
            .replace("{album}", album)
        val baseName = sanitizeSegment(filled)
            .ifEmpty { sanitizeSegment(title) }
            .ifEmpty { "untitled" }
        val segments = when (scheme) {
            "artist" -> listOf(artist)
            "artist-album" -> listOf(artist, album)
            else -> emptyList()
        }.map { sanitizeSegment(it) }.filter { it.isNotEmpty() }
        return DownloadPath(segments.joinToString(File.separator), baseName)
    }

    private fun sanitizeSegment(name: String): String = name
        .replace(Regex("[\\\\/:*?\"<>|]"), " ")
        .replace(Regex("\\s+"), " ")
        .trim()
        .trimStart('.').trimEnd('.')
        .trim()

    private fun dedupeFile(target: File): File {
        if (!target.exists()) return target
        val base = target.nameWithoutExtension
        val ext = target.extension
        var seq = 2
        while (true) {
            val candidate = File(target.parentFile, "$base ($seq)" + if (ext.isEmpty()) "" else ".$ext")
            if (!candidate.exists()) return candidate
            seq++
        }
    }

    private fun overridePolicy(): String =
        ConfigStore.shared(appContext).get("download.overwritePolicy") as? String ?: "rename"

    private fun isRejectedMime(mime: String?): Boolean {
        if (mime.isNullOrEmpty()) return false
        val lower = mime.lowercase()
        return lower.startsWith("text/") || lower.contains("json") || lower.contains("html")
    }

    /** 已声明格式 → Content-Type → URL 后缀 → .mp3 */
    private fun resolveExtension(declared: String, mime: String?, url: String): String {
        val known = setOf(".flac", ".mp3", ".m4a", ".aac", ".ogg", ".opus", ".wav", ".ape", ".wv", ".aiff")
        if (declared.isNotEmpty()) {
            val ext = if (declared.startsWith(".")) declared.lowercase() else ".${declared.lowercase()}"
            if (ext in known) return ext
        }
        val mimeMap = mapOf(
            "audio/flac" to ".flac",
            "audio/x-flac" to ".flac",
            "audio/mpeg" to ".mp3",
            "audio/mp3" to ".mp3",
            "audio/mp4" to ".m4a",
            "audio/x-m4a" to ".m4a",
            "audio/aac" to ".aac",
            "audio/ogg" to ".ogg",
            "audio/opus" to ".opus",
            "audio/wav" to ".wav",
            "audio/x-wav" to ".wav",
        )
        mime?.substringBefore(';')?.trim()?.lowercase()?.let { m ->
            mimeMap[m]?.let { return it }
        }
        val tail = url.substringBefore('?').substringAfterLast('/')
        val ext = tail.substringAfterLast('.', "")
        if (ext.isNotEmpty() && ".${ext.lowercase()}" in known) return ".${ext.lowercase()}"
        return ".mp3"
    }

    // MARK: - SAF 写入

    private fun writeSaf(
        treeRoot: Uri,
        fileName: String,
        input: java.io.InputStream,
        taskId: String,
        received: java.util.concurrent.atomic.AtomicLong,
        total: Long,
    ): String {
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
        return created.toString()
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

    // MARK: - 事件

    private fun pushProgress(taskId: String, received: Long, total: Long) {
        val now = System.currentTimeMillis()
        val last = lastProgressAt[taskId] ?: 0L
        if (now - last < 300) return
        lastProgressAt[taskId] = now
        synchronized(lock) {
            tasks[taskId]?.let {
                it.put("received", received)
                if (total > 0) it.put("total", total)
            }
        }
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
        savePersisted()
        bridge?.pushEvent(CHANNEL_STATE, task.toString())
    }

    private fun setStatus(task: JSONObject, status: String) {
        task.put("status", status)
        pushState(task)
    }

    // MARK: - 渲染层回传

    private fun submitResolution(taskId: String, res: Map<*, *>): Any? {
        resolveGates[taskId]?.complete(res)
        return null
    }

    private fun failResolution(taskId: String): Any? {
        resolveGates[taskId]?.complete(null)
        return null
    }

    // MARK: - 任务操作

    private fun cancel(taskId: String): Any? {
        canceled[taskId] = true
        resolveGates[taskId]?.complete(null)
        synchronized(lock) {
            if (active == taskId) return null
            if (queue.remove(taskId)) {
                tasks[taskId]?.let {
                    it.put("status", "canceled")
                    it.put("finishedAt", System.currentTimeMillis())
                    pushState(it)
                }
            }
        }
        return null
    }

    private fun remove(taskId: String): Any? {
        removed[taskId] = true
        canceled[taskId] = true
        resolveGates[taskId]?.complete(null)
        val filePath = synchronized(lock) {
            val t = tasks[taskId]
            if (active == taskId) {
                // 进行中：交给收尾逻辑删除文件，这里只删记录
                tasks.remove(taskId)?.optString("filePath") ?: ""
            } else {
                queue.remove(taskId)
                tasks.remove(taskId)?.optString("filePath") ?: ""
            }
        }
        if (filePath.isNotEmpty()) deleteDownloadedFile(filePath)
        savePersisted()
        return null
    }

    /** 删除音频文件及同名歌词（与上游一致） */
    private fun deleteDownloadedFile(filePath: String) {
        val base = filePath.substringBeforeLast('.')
        val sidecars = listOf(".lrc", ".qrc", ".yrc", ".krc", ".ttml", ".lys")
        if (filePath.startsWith("content://")) {
            runCatching { appContext.contentResolver.delete(Uri.parse(filePath), null, null) }
            return
        }
        runCatching { File(filePath).delete() }
        sidecars.forEach { runCatching { File(base + it).delete() } }
    }

    private fun clearFinished(): Any? {
        synchronized(lock) {
            val iter = tasks.entries.iterator()
            while (iter.hasNext()) {
                val st = iter.next().value.optString("status")
                if (st !in setOf("queued", "downloading")) iter.remove()
            }
        }
        savePersisted()
        return null
    }

    private fun listTasks(): List<Any?> {
        val snapshot = synchronized(lock) {
            tasks.values.sortedByDescending { it.optLong("createdAt") }
                .map { Json.toMap(it) }
        }
        return snapshot
    }

    /** 按歌曲身份查找已完成任务的文件路径 */
    private fun lookup(track: Map<*, *>): String? {
        if (track.isEmpty()) return null
        val candidates = synchronized(lock) {
            tasks.values.filter { it.optString("status") == "done" }
        }
        for (task in candidates) {
            val t = task.optJSONObject("track") ?: continue
            if (t.optString("source") != track["source"]?.toString()) continue
            if (t.optString("id") != track["id"]?.toString()) continue
            if (track["source"]?.toString() == "streaming") {
                if (t.optString("serverId") != track["serverId"]?.toString()) continue
                if (t.optString("originalId") != track["originalId"]?.toString()) continue
                if (t.optString("serverRevision", "0") != (track["serverRevision"]?.toString() ?: "0")) continue
            }
            val path = task.optString("filePath")
            if (fileExists(path)) return path
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
