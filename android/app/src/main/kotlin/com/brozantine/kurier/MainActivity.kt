package com.brozantine.kurier

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.provider.Settings
import android.util.Rational
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val nativeChannel = "com.brozantine.kurier/native"
    private val audioChannel = "com.brozantine.kurier/audio"
    private var pipWhenLeaving = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureNotificationChannels()
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, nativeChannel)
        nativeMethodChannel = channel
        KurierForegroundService.actionListener = { action ->
            runOnUiThread { channel.invokeMethod("voiceAction", action) }
        }
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "notify" -> {
                        val title = call.argument<String>("title") ?: "Kurier"
                        val body = call.argument<String>("body") ?: ""
                        val kind = call.argument<String>("kind") ?: "message"
                        val lines = (call.argument<List<*>>("lines") ?: emptyList<Any>())
                            .mapNotNull { it?.toString()?.trim() }
                            .filter { it.isNotEmpty() }
                        val chatChannelId = intArg(call, "chatChannelId")
                        val messageId = intArg(call, "messageId")
                        val chatChannelIds = intArrayArg(call, "chatChannelIds")
                        val silent = call.argument<Boolean>("silent") == true
                        showLocalNotification(
                            title,
                            body,
                            channelIdForKind(kind),
                            kind,
                            lines,
                            chatChannelId,
                            messageId,
                            chatChannelIds,
                            silent,
                        )
                        result.success(null)
                    }
                    "cancelNotify" -> {
                        val kind = call.argument<String>("kind") ?: "message"
                        cancelChatNotification(kind)
                        result.success(null)
                    }
                    "openNotificationSettings" -> {
                        openNotificationSettings()
                        result.success(null)
                    }
                    "enterPip" -> {
                        result.success(enterPip())
                    }
                    "setPipAuto" -> {
                        pipWhenLeaving = call.argument<Boolean>("enabled") == true
                        result.success(null)
                    }
                    "startKeepAlive" -> {
                        val server = call.argument<String>("serverName") ?: "Kurier"
                        val voice = call.argument<String>("voiceChannelName")
                        KurierForegroundService.start(this, server, voice)
                        result.success(null)
                    }
                    "stopKeepAlive" -> {
                        KurierForegroundService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listOutputs" -> result.success(listOutputs())
                    "setOutput" -> {
                        val id = call.argument<String>("deviceId") ?: ""
                        result.success(setOutput(id))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipWhenLeaving) enterPip()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverNotificationTap(intent)
    }

    override fun onResume() {
        super.onResume()
        deliverNotificationTap(intent)
    }

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
        } catch (_: Exception) {
            false
        }
    }

    private fun audioManager(): AudioManager =
        getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private fun listOutputs(): List<Map<String, String>> {
        val am = audioManager()
        val out = mutableListOf<Map<String, String>>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            for (device in am.availableCommunicationDevices) {
                out.add(
                    mapOf(
                        "id" to device.id.toString(),
                        "label" to labelFor(device),
                        "type" to device.type.toString(),
                    )
                )
            }
        }
        if (out.isEmpty()) {
            out.add(mapOf("id" to "speaker", "label" to "Speaker", "type" to "speaker"))
            out.add(mapOf("id" to "earpiece", "label" to "Earpiece", "type" to "earpiece"))
            out.add(mapOf("id" to "bluetooth", "label" to "Bluetooth", "type" to "bluetooth"))
        }
        return out
    }

    private fun labelFor(device: AudioDeviceInfo): String {
        val name = device.productName?.toString()?.trim().orEmpty()
        if (name.isNotEmpty()) return name
        return when (device.type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Speaker"
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Earpiece"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth"
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired headphones"
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE -> "USB"
            else -> "Audio output"
        }
    }

    private fun setOutput(deviceId: String): Boolean {
        val am = audioManager()
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val id = deviceId.toIntOrNull()
            val match = am.availableCommunicationDevices.firstOrNull { device ->
                device.id.toString() == deviceId || (id != null && device.id == id)
            }
            if (match != null) {
                return am.setCommunicationDevice(match)
            }
        }
        when {
            deviceId.contains("speaker", ignoreCase = true) -> {
                am.isSpeakerphoneOn = true
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    am.clearCommunicationDevice()
                }
            }
            deviceId.contains("bluetooth", ignoreCase = true) -> {
                am.isSpeakerphoneOn = false
                @Suppress("DEPRECATION")
                am.startBluetoothSco()
                @Suppress("DEPRECATION")
                am.isBluetoothScoOn = true
            }
            else -> {
                am.isSpeakerphoneOn = false
            }
        }
        return true
    }

    private fun channelIdForKind(kind: String): String = when (kind) {
        "mention" -> "kurier_mentions"
        "dm" -> "kurier_dms"
        "reply" -> "kurier_replies"
        else -> "kurier_messages"
    }

    private fun ensureNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channels = listOf(
            "kurier_messages" to "Messages",
            "kurier_mentions" to "Mentions",
            "kurier_dms" to "Direct messages",
            "kurier_replies" to "Replies",
        )
        for ((id, name) in channels) {
            manager.createNotificationChannel(
                NotificationChannel(id, name, NotificationManager.IMPORTANCE_HIGH).apply {
                    enableVibration(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                },
            )
        }
    }

    private fun openNotificationSettings() {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        }
        startActivity(intent)
    }

    private fun intArrayArg(call: MethodCall, key: String): IntArray {
        val raw = call.argument<List<*>>(key) ?: return intArrayOf()
        return raw.mapNotNull { value ->
            when (value) {
                is Int -> value
                is Long -> value.toInt()
                is Number -> value.toInt()
                else -> value?.toString()?.toIntOrNull()
            }
        }.filter { it != 0 }.toIntArray()
    }

    private fun intArg(call: MethodCall, key: String): Int? {
        val value = call.argument<Any>(key) ?: return null
        return when (value) {
            is Int -> value
            is Long -> value.toInt()
            is Double -> value.toInt()
            is Number -> value.toInt()
            else -> value.toString().toIntOrNull()
        }
    }

    private fun notificationIdForKind(kind: String): Int = when (kind) {
        "mention" -> 1002
        "dm" -> 1003
        "reply" -> 1004
        else -> 1001
    }

    private fun cancelChatNotification(kind: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.cancel(notificationIdForKind(kind))
    }

    private fun deliverNotificationTap(intent: Intent?) {
        val kind = intent?.getStringExtra(EXTRA_KIND) ?: return
        val channelId = intent.getIntExtra(EXTRA_CHANNEL, 0)
        val messageId = intent.getIntExtra(EXTRA_MESSAGE, 0)
        intent.removeExtra(EXTRA_KIND)
        nativeMethodChannel?.invokeMethod(
            "notificationOpened",
            mapOf(
                "kind" to kind,
                "channelId" to channelId,
                "chatChannelId" to channelId,
                "messageId" to messageId,
            ),
        )
    }

    private fun showLocalNotification(
        title: String,
        body: String,
        channelId: String,
        kind: String,
        lines: List<String>,
        chatChannelId: Int?,
        messageId: Int?,
        chatChannelIds: IntArray,
        silent: Boolean,
    ) {
        ensureNotificationChannels()
        val launch = (packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_KIND, kind)
            putExtra(EXTRA_CHANNEL, chatChannelId ?: 0)
            putExtra(EXTRA_MESSAGE, messageId ?: 0)
        }
        val id = notificationIdForKind(kind)
        val pending = PendingIntent.getActivity(
            this,
            id,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val displayLines = if (lines.isNotEmpty()) lines else listOfNotNull(body.takeIf { it.isNotBlank() })
        val inbox = NotificationCompat.InboxStyle().setBigContentTitle(title)
        for (line in displayLines) {
            inbox.addLine(line)
        }
        val channelIds = if (chatChannelIds.isNotEmpty()) {
            chatChannelIds
        } else if (chatChannelId != null && chatChannelId != 0) {
            intArrayOf(chatChannelId)
        } else {
            intArrayOf()
        }
        val markReadIntent = Intent(this, KurierNotificationActionReceiver::class.java).apply {
            action = KurierNotificationActionReceiver.ACTION_MARK_READ
            putExtra(KurierNotificationActionReceiver.EXTRA_KIND, kind)
            putExtra(KurierNotificationActionReceiver.EXTRA_CHANNELS, channelIds)
        }
        val markReadPending = PendingIntent.getBroadcast(
            this,
            id,
            markReadIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val markRead = NotificationCompat.Action.Builder(
            0,
            "Mark as read",
            markReadPending,
        )
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_MARK_AS_READ)
            .setShowsUserInterface(false)
            .build()
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_stat_kurier)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(inbox)
            .setContentIntent(pending)
            .setAutoCancel(true)
            .addAction(markRead)
            .setNumber(displayLines.size.coerceAtLeast(1))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        if (silent) {
            builder.setSilent(true).setOnlyAlertOnce(true)
        } else {
            builder.setDefaults(NotificationCompat.DEFAULT_ALL)
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(id, builder.build())
    }

    companion object {
        var nativeMethodChannel: MethodChannel? = null
            internal set
        private const val EXTRA_KIND = "kurier.kind"
        private const val EXTRA_CHANNEL = "kurier.channelId"
        private const val EXTRA_MESSAGE = "kurier.messageId"
    }
}
