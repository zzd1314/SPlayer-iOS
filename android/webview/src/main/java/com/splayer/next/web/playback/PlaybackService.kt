package com.splayer.next.web.playback

import android.app.PendingIntent
import android.content.Intent
import android.os.IBinder
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * 前台播放服务：提供锁屏 / 通知栏 / 蓝牙媒体控制。
 * 播放器实例复用 PlaybackEngine 的 ExoPlayer；
 * 上下曲由渲染层队列管理，通过事件转发实现。
 */
class PlaybackService : MediaSessionService() {

    private var mediaSession: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        val base = PlaybackEngine.attachPlayer(this)
        // 通知栏下一首/上一首在 ExoPlayer 无队列时也可用，转发给渲染层
        val forwarded = object : ForwardingPlayer(base) {
            override fun getAvailableCommands(): Player.Commands =
                super.getAvailableCommands().buildUpon()
                    .add(Player.COMMAND_SEEK_TO_NEXT)
                    .add(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
                    .add(Player.COMMAND_SEEK_TO_PREVIOUS)
                    .add(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
                    .build()

            override fun isCommandAvailable(command: Int): Boolean = when (command) {
                Player.COMMAND_SEEK_TO_NEXT,
                Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
                Player.COMMAND_SEEK_TO_PREVIOUS,
                Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
                -> true

                else -> super.isCommandAvailable(command)
            }

            override fun seekToNext() = PlaybackEngine.onSkipToNext()
            override fun seekToNextMediaItem() = PlaybackEngine.onSkipToNext()
            override fun seekToPrevious() = PlaybackEngine.onSkipToPrevious()
            override fun seekToPreviousMediaItem() = PlaybackEngine.onSkipToPrevious()
        }
        // 点击通知/锁屏封面回到应用主界面
        val sessionActivity = PendingIntent.getActivity(
            this,
            0,
            Intent(this, com.splayer.next.web.WebHostActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        mediaSession = MediaSession.Builder(this, forwarded)
            .setSessionActivity(sessionActivity)
            .build()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return super.onStartCommand(intent, flags, startId)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = mediaSession

    override fun onDestroy() {
        mediaSession?.run {
            player.release()
            release()
            mediaSession = null
        }
        PlaybackEngine.releasePlayer()
        super.onDestroy()
    }
}
