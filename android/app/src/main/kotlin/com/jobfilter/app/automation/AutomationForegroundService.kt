package com.jobfilter.app.automation

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import androidx.core.app.NotificationCompat
import com.jobfilter.app.R

/**
 * Spec section 25 — keeps job monitoring alive while the driver's screen is
 * off or another app is briefly in front, with the persistent, honest
 * notification Android requires for a foreground service. Does no automation
 * work itself: [JobAccessibilityService] keeps running independently, this
 * service only represents "monitoring is active" to the OS and the driver.
 */
class AutomationForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "jobfilter_automation"
        private const val NOTIFICATION_ID = 1001

        // Separate, higher-importance channel from the silent/ongoing one
        // above — a real driver need identified this session: Bolt fully
        // auto-accepts jobs (unlike Uber, which only ever shows a badge for
        // the driver to tap themselves), and Bolt can be genuinely
        // backgrounded when that happens, so without an audible alert the
        // driver has no way to know a job was just accepted on their behalf
        // until they happen to check the app. IMPORTANCE_HIGH is what
        // actually enables heads-up + sound on Android 8+; the ongoing
        // monitoring notification above is deliberately LOW so it never
        // makes noise, which is why this needs its own channel rather than
        // reusing it.
        private const val JOB_ACCEPTED_CHANNEL_ID = "jobfilter_job_accepted"
        private const val JOB_ACCEPTED_NOTIFICATION_ID = 1002

        const val ACTION_STOP = "com.jobfilter.app.ACTION_STOP_AUTOMATION"

        /**
         * Called from [AutomationMethodChannelHandler] the moment Dart
         * confirms a Bolt job was actually accepted (the tap/swipe action
         * succeeded, not just decided) — never for Uber, which never
         * auto-accepts anything, so the driver already knows since they
         * tapped it themselves.
         */
        fun showJobAcceptedNotification(context: Context, contentText: String) {
            createJobAcceptedChannel(context)
            val notification = NotificationCompat.Builder(context, JOB_ACCEPTED_CHANNEL_ID)
                .setContentTitle("Job accepted")
                .setContentText(contentText)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setAutoCancel(true)
                .build()
            val manager = context.getSystemService(NotificationManager::class.java)
            manager?.notify(JOB_ACCEPTED_NOTIFICATION_ID, notification)
        }

        private fun createJobAcceptedChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            val channel = NotificationChannel(
                JOB_ACCEPTED_CHANNEL_ID,
                "Job accepted",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts when JobFilter automatically accepts a Bolt job"
                enableVibration(true)
                setSound(
                    Settings.System.DEFAULT_NOTIFICATION_URI,
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            }
            manager.createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // Spec section 19/25: the notification's STOP must be as
            // effective as the in-app emergency stop. This only *signals*
            // Dart (via AutomationBridge); Dart's AutomationController.stop()
            // is what actually cancels the detected-text subscription and
            // stops the accessibility-driven action path.
            AutomationBridge.emitStopRequested()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        val stopIntent = Intent(this, AutomationForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            0,
            stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText("Automation is active — monitoring supported driver apps")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(0, "STOP", stopPendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "JobFilter automation",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when JobFilter is actively monitoring supported driver apps"
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }
}
