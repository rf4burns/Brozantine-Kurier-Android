package com.brozantine.kurier

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject

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
        val kind = intent.getStringExtra(EXTRA_KIND)
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, 0)
        val channelIds = (intent.getIntArrayExtra(EXTRA_CHANNELS) ?: intArrayOf())
            .filter { it != 0 }
        val manager = context.applicationContext
            .getSystemService(NotificationManager::class.java)
        if (notificationId != 0) {
            manager?.cancel(notificationId)
        } else if (!kind.isNullOrEmpty()) {
            manager?.cancel(notificationIdForKind(kind))
        } else {
            for (id in CHAT_NOTIFICATION_IDS) manager?.cancel(id)
        }
        val payload = mapOf(
            "kind" to (kind ?: "message"),
            "channelIds" to channelIds,
        )
        Handler(Looper.getMainLooper()).post {
            val channel = MainActivity.nativeMethodChannel
            if (channel != null) {
                channel.invokeMethod("markRead", payload)
            } else {
                persistPendingMarkRead(context, kind ?: "message", channelIds)
            }
        }
    }

    private fun persistPendingMarkRead(
        context: Context,
        kind: String,
        channelIds: List<Int>,
    ) {
        val prefs = context.applicationContext
            .getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val existing = prefs.getString(PENDING_MARK_READ_KEY, null)
        val arr = try {
            if (existing.isNullOrEmpty()) JSONArray() else JSONArray(existing)
        } catch (_: Exception) {
            JSONArray()
        }
        val obj = JSONObject()
        obj.put("kind", kind)
        val ids = JSONArray()
        for (id in channelIds) ids.put(id)
        obj.put("channelIds", ids)
        arr.put(obj)
        prefs.edit().putString(PENDING_MARK_READ_KEY, arr.toString()).commit()
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
        const val EXTRA_NOTIFICATION_ID = "kurier.notificationId"

        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val PENDING_MARK_READ_KEY = "flutter.kurier.pendingMarkRead"
        private val CHAT_NOTIFICATION_IDS = intArrayOf(1001, 1002, 1003, 1004)

        fun notificationIdForKind(kind: String): Int = when (kind) {
            "mention" -> 1002
            "dm" -> 1003
            "reply" -> 1004
            else -> 1001
        }
    }
}
