package com.splayer.next.web.api

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * 播放列表存储：对应主进程 services/playlist 的 SQLite 实现（playlists 表）。
 * Playlist 结构与渲染层 PlaylistApi 契约一致：
 * {id,name,description,cover,trackIds,createdAt,updatedAt,trackCount}
 */
class PlaylistStore(context: Context) {

    private val appContext = context.applicationContext

    private val db by lazy {
        appContext.openOrCreateDatabase("playlists.db", Context.MODE_PRIVATE, null).apply {
            execSQL(
                """
                CREATE TABLE IF NOT EXISTS playlists (
                  id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT DEFAULT '',
                  cover TEXT DEFAULT '', trackIds TEXT NOT NULL DEFAULT '[]',
                  createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL
                )""".trimIndent(),
            )
        }
    }

    fun handle(method: String, args: List<Any?>): Any? = when (method) {
        "list" -> list()
        "get" -> get(str(args, 0))
        "create" -> create(asMap(args.getOrNull(0)))
        "update" -> update(str(args, 0), asMap(args.getOrNull(1)))
        "remove" -> remove(str(args, 0))
        "addTracks" -> addTracks(str(args, 0), idList(args.getOrNull(1)))
        "removeTracks" -> removeTracks(str(args, 0), idList(args.getOrNull(1)))
        "importLegacy" -> importLegacy(asMaps(args.getOrNull(0)))
        "clear" -> clear()
        else -> throw BridgeUnsupportedException("playlist.$method 暂未在 Android 端实现")
    }

    private fun str(args: List<Any?>, i: Int): String = args.getOrNull(i)?.toString() ?: ""

    @Suppress("UNCHECKED_CAST")
    private fun asMap(value: Any?): Map<String, Any?> =
        (value as? Map<String, Any?>) ?: emptyMap()

    @Suppress("UNCHECKED_CAST")
    private fun asMaps(value: Any?): List<Map<String, Any?>> =
        (value as? List<Map<String, Any?>>) ?: emptyList()

    private fun idList(value: Any?): List<String> =
        (value as? List<*>)?.mapNotNull { it?.toString() } ?: emptyList()

    // MARK: - CRUD

    private fun list(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        db.rawQuery(
            "SELECT id,name,description,cover,trackIds,createdAt,updatedAt FROM playlists ORDER BY updatedAt DESC",
            null,
        ).use { c ->
            while (c.moveToNext()) out.add(rowToMap(c))
        }
        return out
    }

    private fun get(id: String): Map<String, Any?>? {
        db.rawQuery("SELECT id,name,description,cover,trackIds,createdAt,updatedAt FROM playlists WHERE id=?", arrayOf(id)).use { c ->
            if (c.moveToFirst()) return rowToMap(c)
        }
        return null
    }

    private fun create(input: Map<String, Any?>): Map<String, Any?> {
        val id = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        val name = input["name"]?.toString()?.ifBlank { "新建播放列表" } ?: "新建播放列表"
        db.execSQL(
            "INSERT INTO playlists(id,name,description,cover,trackIds,createdAt,updatedAt) VALUES(?,?,?,?,?,?,?)",
            arrayOf(
                id,
                name,
                input["description"]?.toString() ?: "",
                input["cover"]?.toString() ?: "",
                JSONArray(idList(input["trackIds"])).toString(),
                now,
                now,
            ),
        )
        return get(id) ?: emptyMap()
    }

    private fun update(id: String, input: Map<String, Any?>): Map<String, Any?>? {
        val existing = get(id) ?: return null
        val name = input["name"]?.toString() ?: existing["name"]?.toString() ?: ""
        val description = input["description"]?.toString() ?: existing["description"]?.toString() ?: ""
        val cover = input["cover"]?.toString() ?: existing["cover"]?.toString() ?: ""
        val trackIds = (input["trackIds"] as? List<*>)?.mapNotNull { it?.toString() }
            ?: idList(existing["trackIds"])
        db.execSQL(
            "UPDATE playlists SET name=?,description=?,cover=?,trackIds=?,updatedAt=? WHERE id=?",
            arrayOf(name, description, cover, JSONArray(trackIds).toString(), System.currentTimeMillis(), id),
        )
        return get(id)
    }

    private fun remove(id: String): Any? {
        db.execSQL("DELETE FROM playlists WHERE id=?", arrayOf(id))
        return null
    }

    private fun addTracks(id: String, trackIds: List<String>): Any? {
        val existing = get(id) ?: return null
        val current = idList(existing["trackIds"]).toMutableList()
        trackIds.forEach { if (!current.contains(it)) current.add(it) }
        db.execSQL(
            "UPDATE playlists SET trackIds=?,updatedAt=? WHERE id=?",
            arrayOf(JSONArray(current).toString(), System.currentTimeMillis(), id),
        )
        return null
    }

    private fun removeTracks(id: String, trackIds: List<String>): Any? {
        val existing = get(id) ?: return null
        val current = idList(existing["trackIds"]).filter { !trackIds.contains(it) }
        db.execSQL(
            "UPDATE playlists SET trackIds=?,updatedAt=? WHERE id=?",
            arrayOf(JSONArray(current).toString(), System.currentTimeMillis(), id),
        )
        return null
    }

    private fun importLegacy(records: List<Map<String, Any?>>): Any? {
        records.forEach { rec ->
            val id = rec["id"]?.toString() ?: return@forEach
            if (get(id) == null) {
                db.execSQL(
                    "INSERT INTO playlists(id,name,description,cover,trackIds,createdAt,updatedAt) VALUES(?,?,?,?,?,?,?)",
                    arrayOf(
                        id,
                        rec["name"]?.toString() ?: "导入列表",
                        rec["description"]?.toString() ?: "",
                        rec["cover"]?.toString() ?: "",
                        JSONArray(idList(rec["trackIds"])).toString(),
                        (rec["createdAt"] as? Number)?.toLong() ?: System.currentTimeMillis(),
                        System.currentTimeMillis(),
                    ),
                )
            }
        }
        return null
    }

    private fun clear(): Any? {
        db.execSQL("DELETE FROM playlists")
        return null
    }

    private fun rowToMap(c: android.database.Cursor): Map<String, Any?> = mapOf(
        "id" to c.getString(0),
        "name" to c.getString(1),
        "description" to c.getString(2),
        "cover" to c.getString(3),
        "trackIds" to idList(c.getString(4)),
        "createdAt" to c.getLong(5),
        "updatedAt" to c.getLong(6),
        "trackCount" to idList(c.getString(4)).size,
    )
}