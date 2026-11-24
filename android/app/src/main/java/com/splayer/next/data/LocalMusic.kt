package com.splayer.next.data

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** 读取系统媒体库中的本地音乐 */
object LocalMusic {

    private val ALBUM_ART_BASE: Uri = Uri.parse("content://media/external/audio/albumart")

    suspend fun scan(context: Context): List<Song> = withContext(Dispatchers.IO) {
        runCatching {
            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            } else {
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            }
            val projection = arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.TITLE,
                MediaStore.Audio.Media.ARTIST,
                MediaStore.Audio.Media.ALBUM,
                MediaStore.Audio.Media.ALBUM_ID,
                MediaStore.Audio.Media.DURATION,
                MediaStore.Audio.Media.DATA
            )
            val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
            val sort = "${MediaStore.Audio.Media.DATE_ADDED} DESC"

            val songs = ArrayList<Song>()
            context.contentResolver.query(collection, projection, selection, null, sort)?.use { cursor ->
                val idIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val titleIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val artistIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val albumIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                val albumIdIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
                val durationIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val dataIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)

                while (cursor.moveToNext()) {
                    val mediaId = cursor.getLong(idIndex)
                    val albumId = cursor.getLong(albumIdIndex)
                    val path = cursor.getString(dataIndex).orEmpty()
                    if (path.isBlank()) continue
                    songs += Song(
                        id = "local-$mediaId",
                        title = cursor.getString(titleIndex).orEmpty().ifBlank { "未知歌曲" },
                        artist = cursor.getString(artistIndex).orEmpty().ifBlank { "未知艺人" },
                        album = cursor.getString(albumIndex).orEmpty(),
                        durationMs = cursor.getLong(durationIndex),
                        coverUrl = ContentUris.withAppendedId(ALBUM_ART_BASE, albumId).toString(),
                        streamUrl = path,
                        tint = tintForId(mediaId)
                    )
                }
            }
            songs
        }.getOrDefault(emptyList())
    }
}
