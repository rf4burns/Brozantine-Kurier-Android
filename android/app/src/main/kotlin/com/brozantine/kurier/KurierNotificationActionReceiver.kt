package com.brozantine.kurier

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper

class KurierNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_MARK_READ) return
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
