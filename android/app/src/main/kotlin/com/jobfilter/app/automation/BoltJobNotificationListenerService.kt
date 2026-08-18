package com.jobfilter.app.automation

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * A real device proved Bolt's "New ride request" heads-up notification
 * carries no fare/route data at all (its extras are just the generic title
 * "New ride request" / text "View details") and no inline action buttons —
 * there is nothing useful to read from the notification itself. What actually
 * gets Bolt's real job-offer screen on screen — the same screen
 * [JobAccessibilityService]'s existing detect/parse/act pipeline already
 * handles correctly once it's visible — is [JobAccessibilityService.launchBoltApp].
 * A real device proved firing the notification's own `fullScreenIntent`
 * PendingIntent directly gets blocked by Android's Background Activity
 * Launch hardening no matter what permissions JobFilter holds (confirmed via
 * the platform's own "Background activity launch blocked" log) — Android
 * specifically targets that exact pattern (a third party re-firing another
 * app's dormant PendingIntent). A plain `startActivity()` using JobFilter's
 * own identity is a different code path that its SYSTEM_ALERT_WINDOW-based
 * exemption actually applies to, so that's delegated to
 * [JobAccessibilityService] instead. This service's only job is deciding
 * *when* to do that — it does no parsing or decision-making of its own.
 */
class BoltJobNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val BOLT_PACKAGE = "ee.mtakso.driver"

        // The specific channel Bolt posts new offers on — confirmed on a
        // real device via `adb shell dumpsys notification`. Scoped to this
        // one channel (not just the package) so Bolt's other notifications
        // ("Ride cancelled", "You're online", etc.) never trigger an
        // unwanted app launch.
        private const val NEW_OFFER_CHANNEL_ID = "new_offer_notifications"
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName != BOLT_PACKAGE) return
        if (sbn.notification.channelId != NEW_OFFER_CHANNEL_ID) return

        android.util.Log.d("JobFilterNotif", "onNotificationPosted: launching Bolt directly")
        JobAccessibilityService.instance?.launchBoltApp()
    }
}
