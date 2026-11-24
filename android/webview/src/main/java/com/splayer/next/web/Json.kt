package com.splayer.next.web

import org.json.JSONArray
import org.json.JSONObject

/**
 * 轻量 JSON 序列化工具：把 Kotlin 基本容器转成 JSON 字符串，
 * 供桥接层回传给 WebView。
 */
object Json {

    fun write(value: Any?): String = when (value) {
        null -> "null"
        is String -> JSONObject.quote(value)
        is Boolean, is Int, is Long, is Float -> value.toString()
        is Double -> if (value.isFinite()) value.toString() else "null"
        is JSONObject -> value.toString()
        is JSONArray -> value.toString()
        is Map<*, *> -> JSONObject().apply {
            value.forEach { (k, v) -> put(k.toString(), rawValue(v)) }
        }.toString()

        is List<*> -> JSONArray().apply {
            value.forEach { put(rawValue(it)) }
        }.toString()

        else -> JSONObject.quote(value.toString())
    }

    /** 递归转换容器为 org.json 节点；标量原样交给 put 处理 */
    private fun rawValue(v: Any?): Any? = when (v) {
        is Map<*, *> -> JSONObject(write(v))
        is List<*> -> JSONArray(write(v))
        else -> v
    }

    /** 解析桥接参数数组（深转换：JSONObject/JSONArray → Map/List） */
    fun parseArgs(raw: String?): List<Any?> {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { unwrap(arr.opt(it)) }
        }.getOrDefault(emptyList())
    }

    private fun unwrap(node: Any?): Any? = when (node) {
        is JSONObject -> {
            val map = linkedMapOf<String, Any?>()
            node.keys().forEach { key -> map[key] = unwrap(node.opt(key)) }
            map
        }

        is JSONArray -> (0 until node.length()).map { unwrap(node.opt(it)) }
        else -> node
    }

    /** 桥内部使用：JSONObject/JSONArray → 深层 Map/List */
    fun toMap(node: JSONObject): Map<String, Any?> {
        val map = linkedMapOf<String, Any?>()
        node.keys().forEach { key -> map[key] = unwrap(node.opt(key)) }
        return map
    }

    fun toList(node: JSONArray): List<Any?> =
        (0 until node.length()).map { unwrap(node.opt(it)) }
}