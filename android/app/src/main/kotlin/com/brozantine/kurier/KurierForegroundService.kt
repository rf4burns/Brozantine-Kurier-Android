package com.brozantine.kurier

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

class KurierForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_MUTE -> {
                dispatchAction("mute")
                return START_STICKY
            }
            ACTION_DEAFEN -> {
                dispatchAction("deafen")
                return START_STICKY
            }
            ACTION_LEAVE -> {
                dispatchAction("leave")
                return START_STICKY
            }
            ACTION_DISCONNECT -> {
                dispatchAction("disconnect")
                return START_STICKY
            }
        }
        val server = intent?.getStringExtra(EXTRA_SERVER).orEmpty().ifBlank { "Kurier" }
        val voice = intent?.getStringExtra(EXTRA_VOICE)
        if (voice.isNullOrBlank()) {
            stopSelf()
            return START_NOT_STICKY
        }
        startInForeground(server, voice)
        return START_STICKY
    }

    override fun onDestroy() {
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
        }
        releaseLock()
        super.onDestroy()
    }

    private fun startInForeground(server: String, voiceChannel: String) {
        val types =
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        acquireLock()
        val notification = buildNotification(server, voiceChannel)
        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, types)
    }

    private fun buildNotification(server: String, voiceChannel: String): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val content = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val text = "In voice · #$voiceChannel"
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_kurier)
            .setContentTitle(server)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(content)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(notifAction("Mute", ACTION_MUTE, 1))
            .addAction(notifAction("Deafen", ACTION_DEAFEN, 2))
            .addAction(notifAction("Disconnect", ACTION_DISCONNECT, 4))
        return builder.build()
    }

    private fun dispatchAction(action: String) {
        val listener = actionListener
        if (listener != null) {
            listener.invoke(action)
            return
        }
        Handler(Looper.getMainLooper()).post {
            val channel = MainActivity.nativeMethodChannel
            if (channel != null) {
                channel.invokeMethod("voiceAction", action)
            } else if (action == "leave" || action == "disconnect") {
                stopSelf()
            }
        }
    }

    private fun notifAction(
        label: String,
        action: String,
        requestCode: Int,
    ): NotificationCompat.Action {
        return NotificationCompat.Action.Builder(0, label, broadcastAction(action, requestCode))
            .setShowsUserInterface(false)
            .build()
    }

    private fun broadcastAction(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, KurierNotificationActionReceiver::class.java).setAction(action)
        return PendingIntent.getBroadcast(
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
            "Voice",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.setShowBadge(false)
        channel.setSound(null, null)
        manager.createNotificationChannel(channel)
    }

    private fun acquireLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "kurier:voice").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
    }

    companion object {
        const val ACTION_START = "com.brozantine.kurier.KEEPALIVE_START"
        const val ACTION_MUTE = "com.brozantine.kurier.MUTE"
        const val ACTION_DEAFEN = "com.brozantine.kurier.DEAFEN"
        const val ACTION_LEAVE = "com.brozantine.kurier.LEAVE"
        const val ACTION_DISCONNECT = "com.brozantine.kurier.DISCONNECT"
        const val EXTRA_SERVER = "serverName"
        const val EXTRA_VOICE = "voiceChannel"
        const val CHANNEL_ID = "kurier_keepalive"
        const val NOTIFICATION_ID = 42

        var actionListener: ((String) -> Unit)? = null

        fun start(context: Context, serverName: String, voiceChannel: String?) {
            if (voiceChannel.isNullOrBlank()) {
                stop(context)
                return
            }
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
