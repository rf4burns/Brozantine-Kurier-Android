package com.brozantine.kurier

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper

class KurierNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            KurierForegroundService.ACTION_MUTE -> dispatchVoiceAction(context, "mute")
            KurierForegroundService.ACTION_DEAFEN -> dispatchVoiceAction(context, "deafen")
            KurierForegroundService.ACTION_LEAVE -> dispatchVoiceAction(context, "leave")
            KurierForegroundService.ACTION_DISCONNECT -> dispatchVoiceAction(context, "disconnect")
            ACTION_MARK_READ -> handleMarkRead(context, intent)
        }
    }

    private fun handleMarkRead(context: Context, intent: Intent) {
        val kind = intent.getStringExtra(EXTRA_KIND) ?: return
        val channelIds = intent.getIntArrayExtra(EXTRA_CHANNELS) ?: intArrayOf()
        context.getSystemService(NotificationManager::class.java)
            ?.cancel(notificationIdForKind(kind))
        val payload = mapOf(
            "kind" to kind,
            "channelIds" to channelIds.filter { it != 0 }.toList(),
        )
        Handler(Looper.getMainLooper()).post {
            MainActivity.nativeMethodChannel?.invokeMethod("markRead", payload)
        }
    }

    private fun dispatchVoiceAction(context: Context, action: String) {
        Handler(Looper.getMainLooper()).post {
            val listener = KurierForegroundService.actionListener
            if (listener != null) {
                listener.invoke(action)
                return@post
            }
            val channel = MainActivity.nativeMethodChannel
            if (channel != null) {
                channel.invokeMethod("voiceAction", action)
            } else if (action == "leave" || action == "disconnect") {
                KurierForegroundService.stop(context.applicationContext)
            }
        }
    }

    companion object {
        const val ACTION_MARK_READ = "com.brozantine.kurier.MARK_READ"
        const val EXTRA_KIND = "kurier.kind"
        const val EXTRA_CHANNELS = "kurier.channelIds"

        fun notificationIdForKind(kind: String): Int = when (kind) {
            "mention" -> 1002
            "dm" -> 1003
            "reply" -> 1004
            else -> 1001
        }
    }
}
