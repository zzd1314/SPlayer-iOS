package com.splayer.next.web.api

import android.content.Context
import org.json.JSONObject

/**
 * 配置存储：对应主进程 electron-store 的 config:get / config:set / config:getAll。
 * 使用 SharedPreferences + JSON 树持久化。
 */
class ConfigStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences("splayer_config", Context.MODE_PRIVATE)

    @Volatile
    private var cache: JSONObject? = null

    /** 支持点号路径，如 player.songLevel */
    fun get(keyPath: String): Any? {
        val root = current()
        var node: Any? = root
        for (part in keyPath.split('.')) {
            node = (node as? JSONObject)?.opt(part) ?: return null
        }
        return unwrap(node)
    }

    fun set(keyPath: String, value: Any?) {
        val parts = keyPath.split('.')
        val root = JSONObject(current().toString())
        var node = root
        for (i in 0 until parts.size - 1) {
            val next = node.optJSONObject(parts[i]) ?: JSONObject()
            node.put(parts[i], next)
            node = next
        }
        when (value) {
            null -> node.putOpt(parts.last(), null)
            is Map<*, *> -> node.put(parts.last(), JSONObject(JsonWrite.write(value)))
            is List<*> -> node.put(parts.last(), org.json.JSONArray(JsonWrite.write(value)))
            else -> node.put(parts.last(), value)
        }
        save(root)
    }

    fun all(): Map<String, Any?> = JsonRead.toMap(current())

    fun reset() {
        cache = JSONObject()
        prefs.edit().clear().apply()
    }

    fun replaceAll(replacement: Map<*, *>?) {
        save(JSONObject(JsonWrite.write(replacement ?: emptyMap<Any, Any>())))
    }

    private fun current(): JSONObject {
        cache?.let { return it }
        val raw = prefs.getString("config", null)
        val obj = runCatching { JSONObject(raw ?: "{}") }.getOrDefault(JSONObject())
        cache = obj
        return obj
    }

    private fun save(obj: JSONObject) {
        cache = obj
        prefs.edit().putString("config", obj.toString()).apply()
    }

    private fun unwrap(node: Any?): Any? = when (node) {
        is JSONObject -> JsonRead.toMap(node)
        is org.json.JSONArray -> JsonRead.toList(node)
        org.json.JSONObject.NULL -> null
        else -> node
    }
}

/** JSON 输出工具（复用 web 包的 Json.write） */
private object JsonWrite {
    fun write(value: Any?): String = com.splayer.next.web.Json.write(value)
}

/** JSON 读取工具 */
internal object JsonRead {
    fun toMap(obj: JSONObject): Map<String, Any?> {
        val map = linkedMapOf<String, Any?>()
        obj.keys().forEach { key ->
            map[key] = unwrap(obj.opt(key))
        }
        return map
    }

    fun toList(arr: org.json.JSONArray): List<Any?> =
        (0 until arr.length()).map { unwrap(arr.opt(it)) }

    fun unwrap(node: Any?): Any? = when (node) {
        is JSONObject -> toMap(node)
        is org.json.JSONArray -> toList(node)
        org.json.JSONObject.NULL -> null
        else -> node
    }
}