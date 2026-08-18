package com.jobfilter.app.automation

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Registers and implements the `com.jobfilter.app/automation` method channel
 * and its two event channels (detected text, and STOP-from-notification).
 * This is the ONLY file that talks to Android system APIs for automation —
 * everything else (JobAccessibilityService, AutomationForegroundService)
 * goes through here or through [AutomationBridge], mirroring the Dart-side
 * layering in lib/platform/automation/automation_method_channel.dart.
 */
class AutomationMethodChannelHandler(
    private val activity: Activity,
    flutterEngine: FlutterEngine
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val METHOD_CHANNEL = "com.jobfilter.app/automation"
        private const val EVENT_CHANNEL = "com.jobfilter.app/automation_events"
        private const val CONTROL_EVENT_CHANNEL = "com.jobfilter.app/automation_control_events"

        private val ACCEPT_KEYWORDS = listOf("accept")
        private val REJECT_KEYWORDS = listOf("reject", "decline", "no thanks")

        // Bolt's collapsed job card has no visible accept/reject button at
        // all — it's swiped right/left instead. "instant" is the ride-type
        // badge shown on every card, used only to locate the card's bounds.
        private val CARD_ANCHOR_KEYWORDS = listOf("instant")

        // Uber's accept control is worded differently from Bolt's "Accept"
        // — "Confirm" for Exclusive fares, "Match" for standard/Priority —
        // and unlike Bolt, its whole job card (including this button) is a
        // genuine clickable android.widget.Button reachable directly, with
        // no card to open first. Confirmed on a real device via
        // `uiautomator dump` across multiple live job offers, contradicting
        // this project's earlier assumption that Uber exposed no
        // accessibility nodes at all — that finding likely just never
        // caught the tree at the right moment.
        private val UBER_ACCEPT_KEYWORDS = listOf("confirm", "match")
    }

    init {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(this)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    AutomationBridge.attachDetectedTextSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    AutomationBridge.attachDetectedTextSink(null)
                }
            }
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    AutomationBridge.attachControlEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    AutomationBridge.attachControlEventSink(null)
                }
            }
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAccessibilityServiceEnabled" -> result.success(isAccessibilityServiceEnabled())
            "openAccessibilitySettings" -> {
                activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                result.success(null)
            }
            "isBatteryOptimizationIgnored" -> result.success(isBatteryOptimizationIgnored())
            "requestIgnoreBatteryOptimizations" -> {
                requestIgnoreBatteryOptimizations()
                result.success(null)
            }
            "isNotificationListenerEnabled" -> result.success(isNotificationListenerEnabled())
            "openNotificationListenerSettings" -> {
                activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                result.success(null)
            }
            "isOverlayPermissionGranted" -> result.success(Settings.canDrawOverlays(activity))
            "openOverlayPermissionSettings" -> {
                activity.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:${activity.packageName}")
                    )
                )
                result.success(null)
            }
            "getForegroundPackageName" -> result.success(JobAccessibilityService.instance?.lastForegroundPackage)
            "startForegroundMonitoring" -> {
                startForegroundService()
                result.success(null)
            }
            "stopForegroundMonitoring" -> {
                stopForegroundService()
                result.success(null)
            }
            "tapAcceptControl" -> acceptJob(
                result,
                call.argument<String>("platform"),
                call.argument<String>("cardAnchor")
            )
            "tapRejectControl" -> rejectJob(
                result,
                call.argument<String>("platform"),
                call.argument<String>("cardAnchor")
            )
            "counterOfferJob" -> counterOfferJob(
                result,
                call.argument<String>("cardAnchor")
            )
            "captureScreenshotForOcr" -> captureScreenshot(result)
            "captureScreenFrame" -> captureScreenFrame(result)
            "captureScreenFrameForDetection" -> captureScreenFrameForDetection(result)
            "showUberDecisionOverlay" -> {
                val poundsPerMileText = call.argument<String>("poundsPerMileText")
                val isAccept = call.argument<Boolean>("isAccept")
                if (poundsPerMileText != null && isAccept != null) {
                    JobAccessibilityService.instance?.showDecisionOverlay(poundsPerMileText, isAccept)
                }
                result.success(null)
            }
            "hideUberDecisionOverlay" -> {
                JobAccessibilityService.instance?.hideDecisionOverlay()
                result.success(null)
            }
            "showJobAcceptedNotification" -> {
                val contentText = call.argument<String>("contentText")
                if (contentText != null) {
                    AutomationForegroundService.showJobAcceptedNotification(activity, contentText)
                }
                result.success(null)
            }
            "showOnlineBubble" -> {
                JobAccessibilityService.instance?.showOnlineBubble()
                result.success(null)
            }
            "hideOnlineBubble" -> {
                JobAccessibilityService.instance?.hideOnlineBubble()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Accepting has no swipe equivalent — a real-device test showed a
     * right-swipe (intended as accept) still registered as a decline in
     * Bolt, meaning the collapsed card's swipe gesture is decline-only in
     * either direction. Accepting only works via opening the specific card
     * (by [cardAnchor], e.g. its pickup address) and tapping the real
     * Accept button inside the resulting detail view.
     *
     * Uber ([platform] == "uber") skips all of that: its whole card,
     * including the accept button, is already a real clickable Button in
     * the tree with no card to open first — see [UBER_ACCEPT_KEYWORDS].
     */
    private fun acceptJob(result: MethodChannel.Result, platform: String?, cardAnchor: String?) {
        val service = JobAccessibilityService.instance
        if (service == null) {
            result.success(false)
            return
        }
        if (platform == "uber") {
            result.success(service.findAndClickButtonByKeywords(UBER_ACCEPT_KEYWORDS))
            return
        }
        // A real device showed a second screen shape entirely: once the
        // driver already has one job accepted, a new offer arriving shows
        // as a single non-swipeable expanded detail view (map +
        // Decline/Change price/Accept) instead of the collapsed swipeable
        // list card — its Accept button is already directly visible, with
        // nothing to open first. Trying that directly before ever touching
        // the anchor means this one call handles both screen shapes without
        // needing to know in advance which is showing.
        if (service.findAndClickButtonByKeywords(ACCEPT_KEYWORDS)) {
            result.success(true)
            return
        }
        val anchor = if (cardAnchor.isNullOrBlank()) CARD_ANCHOR_KEYWORDS.first() else cardAnchor
        service.tapCardThenButton(anchor, ACCEPT_KEYWORDS) { tapped ->
            // See [JobAccessibilityService.invalidateLastEmittedText] — a
            // genuinely failed attempt must not be the only attempt ever
            // made against this still-visible card.
            if (!tapped) service.invalidateLastEmittedText()
            result.success(tapped)
        }
    }

    /**
     * Tries Bolt's swipe-card gesture first (its collapsed job card has no
     * tappable reject button at all), falling back to a keyword-based
     * button tap for layouts that do have one (e.g. the expanded detail
     * view's "Decline"). Either path can legitimately find nothing — e.g.
     * no job currently visible, or the driver switched away to an unrelated
     * app — in which case this reports false rather than guessing.
     *
     * [cardAnchor] (e.g. a pickup address, passed from the Dart side's
     * parsed job data) targets one specific card when more than one offer
     * is visible at once — a real device showed two simultaneous Bolt
     * offers, and without this the swipe landed on whichever card happened
     * to match a generic "instant" search first, not necessarily the one
     * that was actually evaluated. Falls back to that generic anchor only
     * when the caller couldn't determine an address at all.
     *
     * Uber ([platform] == "uber") skips straight to
     * [JobAccessibilityService.findAndClickDeclineButton] — see [acceptJob].
     */
    private fun rejectJob(result: MethodChannel.Result, platform: String?, cardAnchor: String?) {
        val service = JobAccessibilityService.instance
        if (service == null) {
            result.success(false)
            return
        }
        if (platform == "uber") {
            result.success(service.findAndClickDeclineButton(UBER_ACCEPT_KEYWORDS))
            return
        }
        val anchorKeywords = if (cardAnchor.isNullOrBlank()) CARD_ANCHOR_KEYWORDS else listOf(cardAnchor)
        service.swipeJobCard(JobAccessibilityService.SwipeDirection.LEFT, anchorKeywords) { swiped ->
            if (swiped) {
                result.success(true)
            } else {
                val tapped = service.findAndClickButtonByKeywords(REJECT_KEYWORDS)
                // See [JobAccessibilityService.invalidateLastEmittedText] —
                // a real device showed dispatchGesture report success while
                // Bolt never actually registered the swipe, and this
                // fallback tap then also missing (normal — this card layout
                // has no reject button). Without this, that still-visible,
                // still-actionable card would never be looked at again.
                if (!tapped) service.invalidateLastEmittedText()
                result.success(tapped)
            }
        }
    }

    /**
     * Bolt-only — no [platform] parameter since Uber has no equivalent flow;
     * callers (AndroidPlatformActionExecutor) must never invoke this for
     * Uber. See [JobAccessibilityService.counterOfferJobCard] for the actual
     * tap sequence, built against a real device's screen structure: open the
     * card (by [cardAnchor], same anchor mechanism as accept/reject), tap
     * "Change price", then tap whichever suggested price is highest.
     */
    private fun counterOfferJob(result: MethodChannel.Result, cardAnchor: String?) {
        val service = JobAccessibilityService.instance
        if (service == null) {
            android.util.Log.d("JobFilterSwipe", "counterOfferJob: no accessibility service instance")
            result.success(false)
            return
        }
        // A real device showed a job card whose text only had one
        // distance/address line instead of the usual two, leaving the Dart
        // side with no pickup address to send as cardAnchor — this used to
        // return false immediately with zero logging, which was
        // indistinguishable from "nothing happened" to the driver. [acceptJob]
        // and [rejectJob] already fall back to the generic "instant" anchor
        // in this situation; this now does the same instead of refusing
        // outright, and always logs so a future blank anchor is diagnosable.
        val anchor = if (cardAnchor.isNullOrBlank()) {
            android.util.Log.d("JobFilterSwipe", "counterOfferJob: blank cardAnchor, falling back to generic anchor")
            CARD_ANCHOR_KEYWORDS.first()
        } else {
            cardAnchor
        }
        service.counterOfferJobCard(anchor) { success ->
            // See [JobAccessibilityService.invalidateLastEmittedText].
            if (!success) service.invalidateLastEmittedText()
            result.success(success)
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val expected = ComponentName(activity, JobAccessibilityService::class.java)
        val enabledServices = Settings.Secure.getString(
            activity.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        return enabledServices.split(":").any {
            it.equals(expected.flattenToString(), ignoreCase = true) ||
                it.equals(expected.flattenToShortString(), ignoreCase = true)
        }
    }

    private fun isNotificationListenerEnabled(): Boolean {
        return NotificationManagerCompat.getEnabledListenerPackages(activity).contains(activity.packageName)
    }

    private fun isBatteryOptimizationIgnored(): Boolean {
        val powerManager = activity.getSystemService(Context.POWER_SERVICE) as? PowerManager
        return powerManager?.isIgnoringBatteryOptimizations(activity.packageName) ?: true
    }

    private fun requestIgnoreBatteryOptimizations() {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${activity.packageName}")
        }
        activity.startActivity(intent)
    }

    private fun startForegroundService() {
        val intent = Intent(activity, AutomationForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startForegroundService(intent)
        } else {
            activity.startService(intent)
        }
    }

    private fun stopForegroundService() {
        activity.stopService(Intent(activity, AutomationForegroundService::class.java))
    }

    private fun captureScreenshot(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.success(null)
            return
        }
        val service = JobAccessibilityService.instance
        if (service == null) {
            result.success(null)
            return
        }
        service.captureScreenshot(result)
    }

    /** Full-frame capture for the visual-understanding pipeline — see [JobAccessibilityService.captureScreenFrame]. */
    private fun captureScreenFrame(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.success(null)
            return
        }
        val service = JobAccessibilityService.instance
        if (service == null) {
            result.success(null)
            return
        }
        service.captureScreenFrame(result)
    }

    /** Cropped capture for production's decision badge — see [JobAccessibilityService.captureScreenFrameForDetection]. */
    private fun captureScreenFrameForDetection(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.success(null)
            return
        }
        val service = JobAccessibilityService.instance
        if (service == null) {
            result.success(null)
            return
        }
        service.captureScreenFrameForDetection(result)
    }
}
