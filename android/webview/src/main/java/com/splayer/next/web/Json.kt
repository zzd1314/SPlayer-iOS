package com.splayer.next.web

import org.json.JSONArray
import org.json.JSONObject

/**
 * 轻量 JSON 序列化工具：把 Kotlin 基本容器转成 JSON 字符串，
 * 供桥接层回传给 WebView。
 */
object Json {

    fun write(value: Any?): String {
        if (value == null) return "null"
        return when (value) {
            is String -> JSONObject.quote(value)
            is Boolean, is Int, is Long, is Double, is Float -> value.toString()
            is Map<*, *> -> {
                val obj = JSONObject()
                value.forEach { (k, v) -> obj.put(k.toString(), JSONObject(write(v))) }
                obj.toString()
            }

            is List<*> -> {
                val arr = JSONArray()
                value.forEach { arr.put(JSONObject(write(it))) }
                arr.toString()
            }

            else -> JSONObject.quote(value.toString())
        }
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
}