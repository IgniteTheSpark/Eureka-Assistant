package com.eureka.chiplet_ring

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the Flutter process and the vendor BLE service eligible to receive ring
 * callbacks while the display is off. This is a connected-device foreground
 * service, not media playback. A partial wake lock is held only during capture.
 */
class RingBackgroundService : Service() {
    private var captureWakeLock: PowerManager.WakeLock? = null
    private var captureActive = false
    private var sessionEnabled = true

    override fun onCreate() {
        super.onCreate()
        runningInstance = this
        createNotificationChannel()
        promoteToForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        promoteToForeground()
        when (intent?.action) {
            ACTION_START -> sessionEnabled = true
            ACTION_SET_CAPTURE_ACTIVE -> setCaptureActive(
                intent.getBooleanExtra(EXTRA_ACTIVE, false),
            )
            ACTION_STOP -> {
                captureActive = false
                releaseCaptureWakeLock()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        captureActive = false
        releaseCaptureWakeLock()
        if (runningInstance === this) runningInstance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun setCaptureActive(active: Boolean) {
        if (!sessionEnabled) {
            captureActive = false
            releaseCaptureWakeLock()
            if (active) throw IllegalStateException("ring background session is stopping")
            return
        }
        captureActive = active
        if (active) {
            val lock = captureWakeLock ?: run {
                val power = getSystemService(POWER_SERVICE) as PowerManager
                power.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "$packageName:ring-capture",
                ).also {
                    it.setReferenceCounted(false)
                    captureWakeLock = it
                }
            }
            if (!lock.isHeld) lock.acquire(MAX_CAPTURE_DURATION_MS)
        } else {
            releaseCaptureWakeLock()
        }
        promoteToForeground()
    }

    private fun releaseCaptureWakeLock() {
        captureWakeLock?.let { if (it.isHeld) it.release() }
    }

    private fun stopSession() {
        sessionEnabled = false
        captureActive = false
        releaseCaptureWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun promoteToForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(if (captureActive) "Reka 正在接收戒指录音" else "Reka 戒指已连接")
            .setContentText(if (captureActive) "锁屏后仍会继续接收录音" else "可在锁屏状态使用戒指录音")
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "戒指连接",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "保持戒指在锁屏状态下连接并接收录音"
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "eureka_ring_connection"
        private const val NOTIFICATION_ID = 603
        private const val ACTION_START = "com.eureka.chiplet_ring.START"
        private const val ACTION_STOP = "com.eureka.chiplet_ring.STOP"
        private const val ACTION_SET_CAPTURE_ACTIVE =
            "com.eureka.chiplet_ring.SET_CAPTURE_ACTIVE"
        private const val EXTRA_ACTIVE = "active"
        private const val MAX_CAPTURE_DURATION_MS = 30L * 60L * 1000L
        @Volatile private var runningInstance: RingBackgroundService? = null

        fun start(context: Context) {
            val intent = Intent(context, RingBackgroundService::class.java)
                .setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val service = runningInstance
            if (service != null) {
                service.stopSession()
            } else {
                context.stopService(Intent(context, RingBackgroundService::class.java))
            }
        }

        fun setCaptureActive(active: Boolean) {
            val service = runningInstance
            if (service == null) {
                if (active) throw IllegalStateException("ring background session is not running")
                return
            }
            service.setCaptureActive(active)
        }
    }
}
