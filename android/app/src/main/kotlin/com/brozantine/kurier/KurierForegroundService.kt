package com.brozantine.kurier

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

class KurierForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        acquireLocks()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_MUTE -> {
                actionListener?.invoke("mute")
                return START_STICKY
            }
            ACTION_DEAFEN -> {
                actionListener?.invoke("deafen")
                return START_STICKY
            }
            ACTION_LEAVE -> {
                actionListener?.invoke("leave")
                return START_STICKY
            }
        }
        val server = intent?.getStringExtra(EXTRA_SERVER).orEmpty().ifBlank { "Kurier" }
        val voice = intent?.getStringExtra(EXTRA_VOICE)
        startInForeground(server, voice)
        return START_STICKY
    }

    override fun onDestroy() {
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
        }
        releaseLocks()
        super.onDestroy()
    }

    private fun startInForeground(server: String, voiceChannel: String?) {
        val inVoice = !voiceChannel.isNullOrBlank()
        val types = if (inVoice) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        } else {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }
        val notification = buildNotification(server, voiceChannel)
        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, types)
    }

    private fun buildNotification(server: String, voiceChannel: String?): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val content = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val inVoice = !voiceChannel.isNullOrBlank()
        val text = if (inVoice) {
            "In voice · #$voiceChannel"
        } else {
            "Connected to $server"
        }
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_kurier)
            .setContentTitle("Kurier")
            .setContentText(text)
            .setContentIntent(content)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        if (inVoice) {
            builder
                .addAction(0, "Mute", serviceAction(ACTION_MUTE, 1))
                .addAction(0, "Deafen", serviceAction(ACTION_DEAFEN, 2))
                .addAction(0, "Disconnect", serviceAction(ACTION_LEAVE, 3))
        }
        return builder.build()
    }

    private fun serviceAction(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, KurierForegroundService::class.java).setAction(action)
        return PendingIntent.getService(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Connection",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.setShowBadge(false)
        channel.setSound(null, null)
        manager.createNotificationChannel(channel)
    }

    @Suppress("DEPRECATION")
    private fun acquireLocks() {
        if (wakeLock?.isHeld != true) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "kurier:session").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        if (wifiLock?.isHeld != true) {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            wifiLock = wifi.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "kurier:wifi",
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseLocks() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
        try {
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (_: Exception) {
        }
        wifiLock = null
    }

    companion object {
        const val ACTION_START = "com.brozantine.kurier.KEEPALIVE_START"
        const val ACTION_MUTE = "com.brozantine.kurier.MUTE"
        const val ACTION_DEAFEN = "com.brozantine.kurier.DEAFEN"
        const val ACTION_LEAVE = "com.brozantine.kurier.LEAVE"
        const val EXTRA_SERVER = "serverName"
        const val EXTRA_VOICE = "voiceChannel"
        const val CHANNEL_ID = "kurier_keepalive"
        const val NOTIFICATION_ID = 42

        var actionListener: ((String) -> Unit)? = null

        fun start(context: Context, serverName: String, voiceChannel: String?) {
            val intent = Intent(context, KurierForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_SERVER, serverName)
                putExtra(EXTRA_VOICE, voiceChannel)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, KurierForegroundService::class.java))
        }
    }
}
