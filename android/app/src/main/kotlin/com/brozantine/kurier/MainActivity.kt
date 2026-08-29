package com.brozantine.kurier

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val nativeChannel = "com.brozantine.kurier/native"
    private val audioChannel = "com.brozantine.kurier/audio"
    private var pipWhenLeaving = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureMessageChannel()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, nativeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "notify" -> {
                        val title = call.argument<String>("title") ?: "Kurier"
                        val body = call.argument<String>("body") ?: ""
                        showLocalNotification(title, body)
                        result.success(null)
                    }
                    "enterPip" -> {
                        result.success(enterPip())
                    }
                    "setPipAuto" -> {
                        pipWhenLeaving = call.argument<Boolean>("enabled") == true
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

    private fun ensureMessageChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            "kurier_messages",
            "Messages",
            NotificationManager.IMPORTANCE_HIGH,
        )
        manager.createNotificationChannel(channel)
    }

    private fun showLocalNotification(title: String, body: String) {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, "kurier_messages")
            .setSmallIcon(R.drawable.ic_stat_kurier)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), notification)
    }
}
