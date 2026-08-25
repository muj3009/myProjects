package com.jobfilter.app.automation

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Rect
import android.hardware.display.DisplayManager
import android.os.Build
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import androidx.annotation.RequiresApi
import com.jobfilter.app.R
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Spec section 14 — the Accessibility Service. Scoped by
 * accessibility_service_config.xml to only receive events from the two
 * supported driver apps' packages; the system will not deliver events from
 * any other app to this service, which is the first of several safety layers
 * described in spec section 15.
 *
 * Responsibilities are intentionally narrow: track the current foreground
 * package, extract visible text when that package's UI changes, and (only
 * when explicitly asked, via [findAndClickButtonByKeywords]) locate and tap
 * a single clearly-identified control. It never polls continuously — see
 * docs/android-automation.md for the event-driven design and its
 * battery/CPU rationale (spec section 45).
 */
class JobAccessibilityService : AccessibilityService() {

    companion object {
        var instance: JobAccessibilityService? = null
            private set

        private const val MAX_TREE_DEPTH = 40

        /// See [pollRunnable]'s doc comment. A real device proved jobs can
        /// genuinely disappear (taken by another driver, or Bolt's own
        /// timeout) well within a second of appearing — tightened from the
        /// original 700ms specifically to shrink the worst-case delay
        /// between a card rendering and this loop noticing it, at the cost
        /// of more frequent wake-ups while automation is active.
        private const val POLL_INTERVAL_MS = 300L

        /// Retry cadence for the multi-step tap sequences below (open card ->
        /// wait for detail view; tap "Change price" -> wait for the counter-offer
        /// chips). Tightened from 100ms for the same reason as
        /// [POLL_INTERVAL_MS] — each step still retries up to 6 times, so the
        /// worst-case wait per step drops from 600ms to 360ms without reducing
        /// how long a step is willing to keep trying overall.
        private const val ACTION_RETRY_INTERVAL_MS = 60L

        /// Matches Bolt's counter-offer chip buttons ("£8.36") exactly — a
        /// real device's `findAndClickButtonByKeywords` miss-dump showed the
        /// "Accept £8.04" button's text always carries that "Accept " prefix,
        /// so anchoring to the start of the string is what tells the two
        /// apart without needing to know either button's exact wording.
        private val COUNTER_OFFER_PRICE_REGEX = Regex("^£\\d+\\.\\d{2}$")

        /// Matches each stacked job card's fare label (e.g. "£6.48 (NET, tax
        /// included)") — used only for [countFareCardNodes]'s diagnostic
        /// count of how many job offers are simultaneously stacked on
        /// screen, not for parsing (BoltJobParser owns real fare parsing).
        private val FARE_CARD_LABEL_REGEX = Regex("^£\\d+\\.\\d{2} \\(NET")
    }

    /** Package name of the app that most recently produced an accessibility event. */
    var lastForegroundPackage: String? = null
        private set

    /**
     * Text emitted by the most recent [onAccessibilityEvent] call, so an
     * unchanged screen never gets re-processed. A real device showed events
     * firing hundreds of times per second (likely a live-updating map
     * redrawing) with effectively identical extracted text each time —
     * without this guard, every one of those re-triggers a full Dart-side
     * parse/OCR-throttle-check cycle, starving the one OCR capture that's
     * actually trying to run of CPU time and stretching it out to several
     * seconds, during which every other job on screen was silently ignored.
     */
    private var lastEmittedText: String? = null

    /**
     * Called whenever an accept/reject/counter-offer action ends in genuine,
     * final failure (every mechanism tried — swipe, fallback tap — came up
     * empty). A real device proved this matters: [lastEmittedText]'s dedup
     * means a still-unchanged card is NEVER re-sent to Dart, no matter how
     * many times [pollRunnable] ticks — so the whole "don't record the
     * fingerprint on failure so the next poll retries" design in
     * AutomationController silently never actually got a next poll to retry
     * on. A job whose first (and only) attempt failed just sat there,
     * fully visible and fully actionable, until it eventually expired on
     * its own — indistinguishable from "JobFilter did nothing" to the
     * driver. Clearing this here means the very next poll tick (up to
     * [POLL_INTERVAL_MS] later, not "never") treats the still-visible card
     * as newly seen and gives Dart another chance.
     */
    fun invalidateLastEmittedText() {
        lastEmittedText = null
    }

    /**
     * Polling backstop for Bolt — a real device proved this is genuinely
     * necessary, not just theoretical caution: with Bolt never opened this
     * session and a driver on a different app, Bolt's own "New ride
     * request" notification demonstrably posted (confirmed via its
     * notification-sound log entry) while ZERO accessibility events of any
     * kind reached [onAccessibilityEvent] — not typeWindowsChanged, not the
     * typeNotificationStateChanged handler added specifically for this. The
     * app process itself was confirmed alive throughout (Dart's own Uber
     * poll timer kept running normally), so this isn't the service being
     * killed — Android (most likely Samsung's own OneUI notification-shade
     * layer, going by the Sec-prefixed classes in that log) is simply not
     * delivering the event to this service at all in that specific
     * scenario. Rather than chase which exact event type or packageNames
     * quirk would fix that per-device, this sidesteps the question
     * entirely: check for monitored-app content on a fixed schedule
     * regardless of whether any event ever fires, the same proven approach
     * [AutomationController]'s own Uber poll timer already uses on the Dart
     * side. [emitTextForPackage]'s own lastEmittedText dedup makes calling
     * this redundantly alongside the event-driven paths completely safe —
     * it's a no-op whenever nothing has actually changed.
     */
    private var pollTickCount = 0
    private val pollHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val pollRunnable = object : Runnable {
        override fun run() {
            pollTickCount++
            // A heartbeat every ~10th tick (roughly every 7s), not every
            // tick (every 700ms would be pure log spam) — the only way to
            // tell "this loop stopped running" apart from "it's running but
            // finding nothing" from logcat alone, which mattered directly:
            // an earlier real-device session couldn't tell those two apart
            // and wasted time debugging the wrong one.
            if (pollTickCount % 10 == 0) {
                android.util.Log.d("JobFilterSwipe", "pollRunnable: heartbeat tick=$pollTickCount")
            }
            // Wrapped so one bad tick (e.g. `windows` momentarily
            // inaccessible right as a window is torn down) can never
            // silently kill the whole loop forever — without this, an
            // uncaught exception here would skip the postDelayed call below
            // and this backstop would just stop existing for the rest of
            // the session with no crash, no log, nothing to notice by.
            try {
                var anyMonitoredWindowVisible = false
                for (pkg in MonitoredPackages.ANDROID_PACKAGE_NAMES) {
                    val hasWindow = packageHasAnyWindow(pkg)
                    if (hasWindow) {
                        anyMonitoredWindowVisible = true
                        android.util.Log.d("JobFilterSwipe", "pollRunnable: found window for pkg=$pkg")
                        lastForegroundPackage = pkg
                        emitTextForPackage(pkg)
                    }
                }
                // A real device showed a recurring job — same fare, same
                // addresses, byte-for-byte identical extracted text — get
                // silently ignored forever after its first appearance, even
                // though the driver genuinely needed it decided again. Root
                // cause: lastEmittedText's dedup (meant only to stop a
                // static, still-visible screen from re-triggering hundreds
                // of times a second) has no way to tell "still the same
                // screen" apart from "this exact text came back after truly
                // disappearing" — both look identical to a plain string
                // comparison. Clearing it here, only once every monitored
                // window has genuinely gone, means the guard still does its
                // original job (screen stays up unchanged → no reprocessing)
                // but no longer suppresses a legitimately new appearance of
                // old text.
                if (!anyMonitoredWindowVisible) {
                    lastEmittedText = null
                }
            } catch (e: Exception) {
                android.util.Log.d("JobFilterSwipe", "pollRunnable: tick failed, continuing: $e")
            }
            pollHandler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    private fun packageHasAnyWindow(packageName: String): Boolean {
        for (window in windows) {
            val root = window.root ?: continue
            val matches = root.packageName?.toString() == packageName
            @Suppress("DEPRECATION")
            root.recycle()
            if (matches) return true
        }
        return false
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        pollHandler.postDelayed(pollRunnable, POLL_INTERVAL_MS)
        addBalExemptionOverlay()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        // TYPE_WINDOWS_CHANGED fires whenever the set of visible windows
        // changes at all (a window added/removed/resized) — a real device
        // proved this is the ONLY event type that fires when Uber shows its
        // job-offer overlay while a genuinely different app is in the
        // foreground: typeWindowStateChanged/typeWindowContentChanged are
        // both scoped to whichever window Android currently considers
        // "active", which isn't Uber's overlay in that case, so nothing
        // reached this service at all and the decision badge never showed.
        // This event's own packageName can't be trusted the same way —
        // it describes a change to the window LIST, not one window's
        // content — so instead of reading it, this actively re-scans
        // `windows` for any window that belongs to a monitored package.
        if (event.eventType == AccessibilityEvent.TYPE_WINDOWS_CHANGED) {
            var monitoredPackage: String? = null
            for (window in windows) {
                val root = window.root ?: continue
                val pkg = root.packageName?.toString()
                @Suppress("DEPRECATION")
                root.recycle()
                if (pkg != null && MonitoredPackages.ANDROID_PACKAGE_NAMES.contains(pkg)) {
                    monitoredPackage = pkg
                    break
                }
            }
            // Logged unconditionally (not just on a match) so a real device
            // can confirm whether this event is even being delivered at all
            // — if `packageNames` in accessibility_service_config.xml
            // filters TYPE_WINDOWS_CHANGED at the OS level before delivery
            // (a real risk: this event type isn't cleanly attributable to
            // one app), this line simply never appears in logcat, which
            // tells us the fix needs a different approach entirely rather
            // than a bug in the handling below.
            android.util.Log.d(
                "JobFilterVision",
                "onAccessibilityEvent: TYPE_WINDOWS_CHANGED received, monitoredPackage=$monitoredPackage"
            )
            if (monitoredPackage != null) {
                lastForegroundPackage = monitoredPackage
                emitTextForPackage(monitoredPackage)
            }
            return
        }

        // TYPE_NOTIFICATION_STATE_CHANGED: Bolt posts a genuine Android
        // heads-up notification ("New ride request") the instant an offer
        // arrives — a real device confirmed this, distinct from anything in
        // Bolt's own app UI. Unlike TYPE_WINDOWS_CHANGED, this event type IS
        // reliably attributed to the posting app's package, so no window
        // re-scan is needed to identify which app it's from — just an extra,
        // earlier trigger to check for the job card, on top of the existing
        // window-based triggers (the card itself may render a beat after the
        // notification posts, which those still catch).
        if (event.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) {
            val notifPackage = event.packageName?.toString()
            android.util.Log.d(
                "JobFilterVision",
                "onAccessibilityEvent: TYPE_NOTIFICATION_STATE_CHANGED from pkg=$notifPackage"
            )
            if (notifPackage != null && MonitoredPackages.ANDROID_PACKAGE_NAMES.contains(notifPackage)) {
                lastForegroundPackage = notifPackage
                emitTextForPackage(notifPackage)
            }
            return
        }

        val packageName = event.packageName?.toString() ?: return
        lastForegroundPackage = packageName

        // accessibility_service_config.xml already restricts delivery to the
        // monitored packages, but re-checking here keeps this class correct
        // even if the config is ever loosened for a future feature.
        if (!MonitoredPackages.ANDROID_PACKAGE_NAMES.contains(packageName)) return

        emitTextForPackage(packageName)
    }

    /**
     * Walks every currently visible window and keeps only ones that actually
     * belong to [packageName]. This is purely for the fare/route *text* the
     * decision engine needs (spec section 9/13) — accepting or rejecting a
     * job goes through JobAccessibilityService's own
     * findAndClickButtonByKeywords/findAndClickDeclineButton directly, not
     * through anything derived from this extracted text. A real device's
     * `uiautomator dump` confirmed Uber's fare/route details aren't exposed
     * as node text/content-description at all (unlike its buttons, which
     * are), so for Uber this text comes from OCR instead (see
     * OcrTextProvider) and this extraction mainly serves Bolt, whose offer
     * sheet is a genuine additional window.
     */
    private fun emitTextForPackage(packageName: String) {
        val builder = StringBuilder()
        var matchedWindowCount = 0
        for (window in windows) {
            val root = window.root ?: continue
            try {
                if (root.packageName?.toString() != packageName) continue
                matchedWindowCount++
                extractText(root, builder)
            } finally {
                @Suppress("DEPRECATION")
                root.recycle()
            }
        }

        val text = builder.toString()
        // Live diagnostic (spec: temporary, to trace a real-device report of
        // total silence — Bolt's own window clearly found and a genuine job
        // card visible on screen, per a driver's screenshot, yet zero
        // detected-text events reaching Dart for many minutes straight).
        // Distinguishes every possible silent-failure point: no window
        // matched at all vs. matched but extraction produced nothing vs.
        // produced text that's just being deduped as unchanged.
        android.util.Log.d(
            "JobFilterSwipe",
            "emitTextForPackage($packageName): matchedWindows=$matchedWindowCount textLen=${text.length} " +
                "isBlank=${text.isBlank()} sameAsLast=${text == lastEmittedText}"
        )
        if (text.isNotBlank() && text != lastEmittedText) {
            lastEmittedText = text
            AutomationBridge.emitDetectedText(text)
        }
    }

    private fun extractText(
        node: AccessibilityNodeInfo,
        builder: StringBuilder = StringBuilder(),
        depth: Int = 0
    ): String {
        if (depth > MAX_TREE_DEPTH) return builder.toString()
        // A real device showed a stale fare from a past, genuinely-dismissed
        // job offer still getting "detected" as if it were live — Bolt
        // doesn't always clear a recycled card view's text when it's hidden,
        // it just stops rendering it. Without this check that leftover text
        // was indistinguishable from a real one, since jobCardDetected only
        // ever looked at the extracted string, not whether it came from
        // something actually on screen. isVisibleToUser is Android's own
        // signal for exactly this — skipping the whole subtree here also
        // means recycled-but-hidden siblings/children never get walked.
        //
        // A bounds-overlap fallback was tried here (treat a node as present
        // if its bounds still overlap the screen even when isVisibleToUser
        // is false) to fix a *different* real-device report — a destination
        // address clipped at the very bottom of the screen was apparently
        // getting dropped. That fallback was wrong: a real device then
        // showed it readmitting a stale, recycled card (Bolt's own "Today"
        // earnings summary, £31.32, got detected and REJECTED as if it were
        // a live job) — the recycled node kept its old non-zero, on-screen
        // bounds even though isVisibleToUser correctly says false, so the
        // bounds check couldn't tell the two cases apart. Reverted to the
        // strict check; the bottom-clipping case needs a different fix that
        // doesn't reopen this hole (see BoltJobParser's dashboard exclusion
        // phrases for the defense-in-depth alternative).
        if (!node.isVisibleToUser) return builder.toString()

        node.text?.let { if (it.isNotBlank()) builder.append(it).append('\n') }
        node.contentDescription?.let { if (it.isNotBlank()) builder.append(it).append('\n') }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            try {
                extractText(child, builder, depth + 1)
            } finally {
                @Suppress("DEPRECATION")
                child.recycle()
            }
        }
        return builder.toString()
    }

    /**
     * Finds a clickable control whose text/content-description contains one
     * of [keywords] and taps it. Walks up to the nearest clickable ancestor
     * because the matching text is often on a label inside a larger button,
     * not on the clickable node itself.
     *
     * Returns false (never throws) if no confident match is found — callers
     * must treat that as "no action taken", per spec section 15's safety
     * checklist, not retry with a looser match.
     */
    fun findAndClickButtonByKeywords(keywords: List<String>): Boolean {
        val lowerKeywords = keywords.map { it.lowercase() }
        for (root in monitoredWindowRoots()) {
            try {
                val target = findClickableNodeByKeywords(root, lowerKeywords)
                if (target != null) {
                    val clicked = target.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    android.util.Log.d(
                        "JobFilterSwipe",
                        "findAndClickButtonByKeywords($keywords): pkg=${root.packageName} found=true clicked=$clicked"
                    )
                    return clicked
                }
                // Logged only on a miss, on purpose — every real-device
                // sample of this window via `uiautomator dump` (system-
                // privileged, bypasses this service's own accessibility
                // connection) found the button at a shallow depth (16),
                // ruling out MAX_TREE_DEPTH, yet this service's own search
                // of the very same window kept coming back empty. Dumping
                // every clickable Button this traversal actually sees here
                // is the only way to tell "the offer already expired by
                // click-time" (dump would be sparse/dashboard-only) apart
                // from "this service's connection just can't see that
                // specific content" (dump would show other buttons, just
                // never Confirm/Match) instead of guessing which one it is.
                android.util.Log.d(
                    "JobFilterSwipe",
                    "findAndClickButtonByKeywords($keywords): miss in pkg=${root.packageName}, " +
                        "buttons seen: ${dumpButtonTexts(root)}"
                )
            } finally {
                @Suppress("DEPRECATION")
                root.recycle()
            }
        }
        android.util.Log.d("JobFilterSwipe", "findAndClickButtonByKeywords($keywords): not found in any monitored window")
        return false
    }

    /**
     * Root nodes of every currently visible window belonging to a monitored
     * package — not just [rootInActiveWindow]. A real device proved these
     * can differ: `findAndClickButtonByKeywords` searching only
     * [rootInActiveWindow] consistently failed to find Uber's "Confirm"/
     * "Match" button while the driver was actively looking at a live job
     * offer (package correctly reported as com.ubercab.driver, so it wasn't
     * a staleness issue), even though a `uiautomator dump` — which enumerates
     * all windows, not just the "active" one — found that exact button every
     * time. Uber most likely renders the offer card in a separate window
     * Android's accessibility framework doesn't consider "active", the same
     * reason [onAccessibilityEvent] already walks [windows] instead of
     * relying on a single root. Callers must recycle each returned node.
     */
    /**
     * Human-readable label for [AccessibilityWindowInfo.getType]'s int
     * constant — Phase 0's window-type investigation (spec: final Uber
     * production fix) needs to know WHICH window Uber's job card actually
     * lives in (TYPE_APPLICATION vs. an overlay type), not just a number.
     */
    private fun windowTypeName(type: Int): String = when (type) {
        AccessibilityWindowInfo.TYPE_APPLICATION -> "APPLICATION"
        AccessibilityWindowInfo.TYPE_INPUT_METHOD -> "INPUT_METHOD"
        AccessibilityWindowInfo.TYPE_SYSTEM -> "SYSTEM"
        AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY -> "ACCESSIBILITY_OVERLAY"
        AccessibilityWindowInfo.TYPE_SPLIT_SCREEN_DIVIDER -> "SPLIT_SCREEN_DIVIDER"
        else -> "UNKNOWN($type)"
    }

    private fun monitoredWindowRoots(): List<AccessibilityNodeInfo> {
        val roots = mutableListOf<AccessibilityNodeInfo>()
        val allWindows = windows
        // Logged unconditionally, on purpose — a real device kept reporting
        // "not found in any monitored window" even after searching every
        // window, not just the active one, which only makes sense if either
        // the overlay Uber renders its job card in isn't in this list at
        // all, or it's there under a package/type this service doesn't
        // expect. Every window's full detail (Phase 0, spec sections A-D of
        // the production Uber fix: type, displayId, bounds, focus state),
        // present or not, is the only way to tell those apart instead of
        // guessing. Safe to trim once that's settled.
        android.util.Log.d(
            "JobFilterSwipe",
            "monitoredWindowRoots: ${allWindows.size} window(s): " +
                allWindows.joinToString(" | ") { w ->
                    val bounds = Rect()
                    w.getBoundsInScreen(bounds)
                    "[id=${w.id} type=${windowTypeName(w.type)} pkg=${w.root?.packageName} " +
                        "title=${w.title} displayId=${w.displayId} layer=${w.layer} " +
                        "active=${w.isActive} focused=${w.isFocused} " +
                        "a11yFocused=${w.isAccessibilityFocused} bounds=$bounds hasRoot=${w.root != null}]"
                }
        )
        for (window in allWindows) {
            val root = window.root ?: continue
            if (MonitoredPackages.ANDROID_PACKAGE_NAMES.contains(root.packageName?.toString())) {
                roots.add(root)
            } else {
                @Suppress("DEPRECATION")
                root.recycle()
            }
        }
        return roots
    }

    /**
     * Whether a monitored app currently owns *any* visible window — the
     * same "search every window, not just [rootInActiveWindow]" fix
     * [monitoredWindowRoots] applies for finding buttons, reused here as a
     * lightweight yes/no check for screenshot capture guards. A real device
     * proved these can genuinely disagree: a driver confirmed a live Uber
     * offer was on screen at the exact moment a [rootInActiveWindow]-only
     * guard rejected the capture as "wrong app". Every returned root is
     * recycled immediately since only presence is being checked.
     */
    private fun isMonitoredPackageForeground(): Boolean {
        for (window in windows) {
            val root = window.root ?: continue
            val isMonitored = MonitoredPackages.ANDROID_PACKAGE_NAMES.contains(root.packageName?.toString())
            @Suppress("DEPRECATION")
            root.recycle()
            if (isMonitored) return true
        }
        return false
    }

    /**
     * Every clickable OR text-bearing node's class/text/importance, for
     * diagnosing a failed search. `important=false` on a node that
     * `uiautomator` independently showed had real text/a real label is
     * Phase 0's direct confirmation that flagIncludeNotImportantViews (see
     * accessibility_service_config.xml) is the actual fix, rather than a
     * guess — this is checked, not assumed.
     */
    private fun dumpButtonTexts(node: AccessibilityNodeInfo, depth: Int = 0): String {
        if (depth > MAX_TREE_DEPTH) return ""
        val parts = mutableListOf<String>()
        val text = node.text?.toString() ?: node.contentDescription?.toString() ?: ""
        if (node.isClickable || text.isNotBlank()) {
            parts.add("${node.className}:\"$text\":important=${node.isImportantForAccessibility}")
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            try {
                val childDump = dumpButtonTexts(child, depth + 1)
                if (childDump.isNotEmpty()) parts.add(childDump)
            } finally {
                @Suppress("DEPRECATION")
                child.recycle()
            }
        }
        return parts.joinToString(", ")
    }

    /**
     * Uber-specific: clicks the job card's decline "X" — an icon with no
     * text or content-description at all, confirmed via a real device's
     * `uiautomator dump` across multiple live job cards, so it can never be
     * found by keyword search like [findAndClickButtonByKeywords]. Every
     * sample showed exactly the same shape: two clickable
     * `android.widget.Button` nodes on the card, the labeled accept button
     * (Confirm/Match) and one other with no label at all — this clicks
     * whichever clickable Button does *not* match [acceptKeywords], which
     * was that same unlabeled "other" button every time.
     */
    fun findAndClickDeclineButton(acceptKeywords: List<String>): Boolean {
        val lowerAcceptKeywords = acceptKeywords.map { it.lowercase() }
        for (root in monitoredWindowRoots()) {
            try {
                val target = findDeclineButtonNode(root, lowerAcceptKeywords)
                if (target != null) {
                    val clicked = target.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    android.util.Log.d(
                        "JobFilterSwipe",
                        "findAndClickDeclineButton: pkg=${root.packageName} found=true clicked=$clicked"
                    )
                    return clicked
                }
                // Same reasoning as findAndClickButtonByKeywords' identical
                // miss-dump: shows exactly what this service's own tree walk
                // sees in this window right now, so a miss here can be told
                // apart from "content genuinely isn't there" instead of guessed.
                android.util.Log.d(
                    "JobFilterSwipe",
                    "findAndClickDeclineButton: miss in pkg=${root.packageName}, buttons seen: ${dumpButtonTexts(root)}"
                )
            } finally {
                @Suppress("DEPRECATION")
                root.recycle()
            }
        }
        android.util.Log.d("JobFilterSwipe", "findAndClickDeclineButton: not found in any monitored window")
        return false
    }

    private fun findDeclineButtonNode(
        node: AccessibilityNodeInfo,
        acceptKeywords: List<String>,
        depth: Int = 0
    ): AccessibilityNodeInfo? {
        if (depth > MAX_TREE_DEPTH) return null

        if (node.isClickable && node.className?.toString() == "android.widget.Button") {
            val text = (node.text?.toString() ?: node.contentDescription?.toString() ?: "").lowercase()
            if (acceptKeywords.none { text.contains(it) }) return node
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = findDeclineButtonNode(child, acceptKeywords, depth + 1)
            if (found != null) return found
        }
        return null
    }

    /**
     * Taps a specific card open (identified by [cardAnchor], e.g. its pickup
     * address) then, after giving the resulting detail view time to render,
     * finds and taps a button matching [buttonKeywords] within it.
     *
     * Added after a real-device finding: Bolt's collapsed card only exposes
     * a swipe gesture, and that gesture always means decline regardless of
     * direction — there is no "swipe to accept". Accepting only works via
     * this open-then-tap-Accept flow.
     */
    fun tapCardThenButton(cardAnchor: String, buttonKeywords: List<String>, callback: (Boolean) -> Unit) {
        // Every monitored window, not just [rootInActiveWindow] — a real
        // device proved Bolt's own job-offer card can genuinely be found and
        // acted on the same way Uber's was (see [monitoredWindowRoots]'s doc
        // comment): when Bolt shows its card as an overlay while a different
        // app is truly "active" (e.g. the driver backgrounded Bolt to check
        // Maps), [rootInActiveWindow] returns that other app's root or null,
        // silently failing this accept attempt even though the card is
        // genuinely on screen and [onAccessibilityEvent]'s own
        // TYPE_WINDOWS_CHANGED handling already detected it.
        var opened = false
        for (root in monitoredWindowRoots()) {
            try {
                val anchor = findNodeByKeywords(root, listOf(cardAnchor.lowercase())) ?: continue

                var candidate: AccessibilityNodeInfo? = anchor
                var hops = 0
                while (candidate != null && !candidate.isClickable && hops < 10) {
                    candidate = candidate.parent
                    hops++
                }
                val clickableCard = candidate
                if (clickableCard?.isClickable == true) {
                    opened = clickableCard.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    android.util.Log.d(
                        "JobFilterSwipe",
                        "tapCardThenButton: pkg=${root.packageName} opened=$opened"
                    )
                    if (opened) break
                }
            } finally {
                @Suppress("DEPRECATION")
                root.recycle()
            }
        }

        if (!opened) {
            android.util.Log.d("JobFilterSwipe", "tapCardThenButton: anchor/card not found in any monitored window")
            callback(false)
            return
        }

        // The detail view (with the real Accept button) renders after a
        // transition animation, so searching immediately after the click
        // can miss it — but a real device showed some offer windows as
        // short as ~2.7 seconds total, so a fixed wait before even trying
        // wastes time that may not exist. Poll instead: try right away,
        // then every 100ms, succeeding the moment the button actually
        // appears rather than always paying the full worst-case delay.
        pollForButton(buttonKeywords, attemptsLeft = 6, callback = callback)
    }

    private fun pollForButton(keywords: List<String>, attemptsLeft: Int, callback: (Boolean) -> Unit) {
        val tapped = findAndClickButtonByKeywords(keywords)
        if (tapped || attemptsLeft <= 0) {
            android.util.Log.d(
                "JobFilterSwipe",
                "tapCardThenButton: buttonTapped=$tapped (attemptsLeft=$attemptsLeft)"
            )
            callback(tapped)
            return
        }
        android.os.Handler(mainLooper).postDelayed({
            pollForButton(keywords, attemptsLeft - 1, callback)
        }, ACTION_RETRY_INTERVAL_MS)
    }

    /**
     * Bolt-only — driver request: a near-miss £/mile job counter-offers
     * instead of being rejected outright. Built directly against a real
     * device's actual screens (not guessed): opens the card (same anchor
     * mechanism as [tapCardThenButton]), taps "Change price", then taps
     * whichever suggested price chip is numerically highest — confirmed on
     * a real device to always be the rightmost of the visible options, but
     * matched by parsed value here rather than screen position, since that
     * survives however many chips happen to be shown.
     */
    fun counterOfferJobCard(cardAnchor: String, callback: (Boolean) -> Unit) {
        // A real device showed a second screen shape entirely: once the
        // driver already has one job accepted, a new offer shows as a
        // single non-swipeable expanded detail view (map +
        // Decline/Change price/Accept) rather than the collapsed list card
        // — "Change price" is already directly visible there, nothing to
        // open first. Trying that before ever touching the anchor means
        // this one call handles both screen shapes.
        if (findAndClickButtonByKeywords(listOf("change price"))) {
            android.util.Log.d("JobFilterSwipe", "counterOfferJobCard: Change price tapped directly (no open needed)")
            pollForHighestCounterOffer(attemptsLeft = 6, callback = callback)
            return
        }

        var opened = false
        for (root in monitoredWindowRoots()) {
            try {
                val anchor = findNodeByKeywords(root, listOf(cardAnchor.lowercase())) ?: continue

                var candidate: AccessibilityNodeInfo? = anchor
                var hops = 0
                while (candidate != null && !candidate.isClickable && hops < 10) {
                    candidate = candidate.parent
                    hops++
                }
                val clickableCard = candidate
                if (clickableCard?.isClickable == true) {
                    opened = clickableCard.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    android.util.Log.d(
                        "JobFilterSwipe",
                        "counterOfferJobCard: pkg=${root.packageName} opened=$opened"
                    )
                    if (opened) break
                }
            } finally {
                @Suppress("DEPRECATION")
                root.recycle()
            }
        }

        if (!opened) {
            android.util.Log.d("JobFilterSwipe", "counterOfferJobCard: anchor/card not found in any monitored window")
            callback(false)
            return
        }

        pollForChangePriceButton(attemptsLeft = 6, callback = callback)
    }

    private fun pollForChangePriceButton(attemptsLeft: Int, callback: (Boolean) -> Unit) {
        val tapped = findAndClickButtonByKeywords(listOf("change price"))
        if (tapped) {
            android.util.Log.d("JobFilterSwipe", "counterOfferJobCard: Change price tapped")
            pollForHighestCounterOffer(attemptsLeft = 6, callback = callback)
            return
        }
        if (attemptsLeft <= 0) {
            android.util.Log.d("JobFilterSwipe", "counterOfferJobCard: Change price button not found")
            callback(false)
            return
        }
        android.os.Handler(mainLooper).postDelayed({
            pollForChangePriceButton(attemptsLeft - 1, callback)
        }, ACTION_RETRY_INTERVAL_MS)
    }

    private fun pollForHighestCounterOffer(attemptsLeft: Int, callback: (Boolean) -> Unit) {
        val tapped = findAndClickHighestCounterOfferButton()
        if (tapped || attemptsLeft <= 0) {
            android.util.Log.d("JobFilterSwipe", "counterOfferJobCard: highest counter-offer tapped=$tapped")
            callback(tapped)
            return
        }
        android.os.Handler(mainLooper).postDelayed({
            pollForHighestCounterOffer(attemptsLeft - 1, callback)
        }, ACTION_RETRY_INTERVAL_MS)
    }

    private fun findAndClickHighestCounterOfferButton(): Boolean {
        for (root in monitoredWindowRoots()) {
            try {
                val candidates = mutableListOf<Pair<AccessibilityNodeInfo, Double>>()
                collectCounterOfferPriceNodes(root, candidates)
                val best = candidates.maxByOrNull { it.second } ?: continue
                val clicked = best.first.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                android.util.Log.d(
                    "JobFilterSwipe",
                    "findAndClickHighestCounterOfferButton: pkg=${root.packageName} " +
                        "picked £${best.second} clicked=$clicked (from ${candidates.size} options)"
                )
                if (clicked) return true
            } finally {
                @Suppress("DEPRECATION")
                root.recycle()
            }
        }
        android.util.Log.d(
            "JobFilterSwipe",
            "findAndClickHighestCounterOfferButton: no price buttons found in any monitored window"
        )
        return false
    }

    private fun collectCounterOfferPriceNodes(
        node: AccessibilityNodeInfo,
        results: MutableList<Pair<AccessibilityNodeInfo, Double>>,
        depth: Int = 0
    ) {
        if (depth > MAX_TREE_DEPTH) return
        val text = (node.text?.toString() ?: "").trim()
        if (COUNTER_OFFER_PRICE_REGEX.matches(text)) {
            // A real device showed this text living on a plain, non-clickable
            // TextView with its clickable ancestor a few levels up — the
            // same "Change price" button (found via findClickableNodeByKeywords,
            // just below) worked precisely because it already does this same
            // walk-up; this collector originally didn't, and found nothing.
            var candidate: AccessibilityNodeInfo? = node
            var hops = 0
            while (candidate != null && !candidate.isClickable && hops < 10) {
                candidate = candidate.parent
                hops++
            }
            if (candidate?.isClickable == true) {
                text.removePrefix("£").toDoubleOrNull()?.let { results.add(candidate to it) }
            }
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            collectCounterOfferPriceNodes(child, results, depth + 1)
        }
    }

    /** Direction to swipe a job-offer card — Bolt's own decline gesture. */
    enum class SwipeDirection { LEFT, RIGHT }

    /**
     * Swipes the currently visible job-offer card left (reject) or right
     * (accept) — Bolt shows no explicit button on its collapsed card, only
     * this gesture (see docs/parser-design.md for the real-device finding
     * that drove this). [anchorKeywords] locates a stable label inside the
     * card (e.g. "instant") so its on-screen bounds can be used as the
     * swipe's start/end points; callers must fall back to
     * [findAndClickButtonByKeywords] if this returns false, since not every
     * layout (or platform) uses a swipeable card.
     *
     * Searches every monitored window, not just [rootInActiveWindow] — the
     * same fix [tapCardThenButton] needed: if the driver has backgrounded
     * Bolt to check another app while a job card is genuinely showing (as an
     * overlay), [rootInActiveWindow] returns that other app's root instead,
     * which used to make this refuse to swipe at all even though the card
     * really is on screen and was already correctly detected. Still refuses
     * outright if no monitored window exists anywhere (the driver has
     * genuinely switched away with no offer visible) — this must never swipe
     * blind at whatever happens to be on screen.
     */
    fun swipeJobCard(direction: SwipeDirection, anchorKeywords: List<String>, callback: (Boolean) -> Unit) {
        // A live session on a real device proved the swipe is not a hard
        // all-or-nothing block: with an identical gesture, some attempts
        // against a fresh card genuinely succeed (verifySwipeDismissed
        // independently confirmed the card actually gone) while others on
        // the very same device, same code, same job shape, don't — the
        // driver separately confirmed "sometimes the swipe works randomly".
        // That pattern (not 0% and not 100%) is the signature of a marginal
        // case sitting right at Bolt's own swipe-to-dismiss recognizer
        // threshold, where small, unavoidable scheduling/animation timing
        // jitter between attempts tips an individual gesture's effective
        // velocity over or under it — not a deliberate block, which would
        // instead show 0% no matter how the gesture is shaped. The fix for
        // a marginal-probability event is to retry it, not to keep
        // reshaping the gesture: 3 independent attempts compound a
        // per-attempt success rate that's merely "sometimes" into "almost
        // always", each one re-finding the card fresh (not reusing stale
        // bounds) in case the list shifted between attempts.
        attemptSwipeJobCard(direction, anchorKeywords, attemptsLeft = 3, callback = callback)
    }

    private fun attemptSwipeJobCard(
        direction: SwipeDirection,
        anchorKeywords: List<String>,
        attemptsLeft: Int,
        callback: (Boolean) -> Unit
    ) {
        var bounds: Rect? = null
        // Diagnostic for the single-job-vs-stacked-list question: driver
        // reported swipe reliably works when multiple jobs are stacked but
        // not for a single job on its own, which would point at Bolt using
        // a genuinely different screen/widget for the single-offer case
        // rather than a plain RecyclerView list item. Counting fare nodes
        // (each stacked card has its own "£X.XX (NET, tax included)" node)
        // in the SAME window the anchor/bounds came from — logged as a
        // short, single-line count (not a full tree dump) specifically so
        // it survives Monitor's line-length truncation and is directly
        // correlatable with the swipe outcome that follows it, without
        // needing another rebuild to add this if today's session hits the
        // single-job case again.
        var stackedJobCount = -1
        for (root in monitoredWindowRoots()) {
            try {
                val anchor = findNodeByKeywords(root, anchorKeywords.map { it.lowercase() })
                android.util.Log.d(
                    "JobFilterSwipe",
                    "swipeJobCard($direction) pkg=${root.packageName} anchorKeywords=$anchorKeywords found=${anchor != null}"
                )
                bounds = anchor?.let { findCardBounds(it, root) }
                if (bounds != null) {
                    stackedJobCount = countFareCardNodes(root)
                    break
                }
            } finally {
                @Suppress("DEPRECATION")
                root.recycle()
            }
        }
        if (bounds == null) {
            // A real device showed this happen right after a swipe that
            // actually worked: verifySwipeDismissed's first check ran too
            // soon (before Bolt's dismiss animation/tree update finished),
            // wrongly reported "still present", triggering a retry — and
            // that retry then couldn't find the card at all, because it
            // really was already gone. Treating "can't find it" as a
            // synonym for "verified dismissed" on a retry (attemptsLeft < 3
            // means at least one swipe was already dispatched this call)
            // fixes that false failure directly, instead of falling through
            // to tapCardThenButton and needlessly opening the card's detail
            // view for a job that was already correctly declined. On the
            // very first attempt (no swipe dispatched yet), not finding the
            // card is a genuinely different, more ambiguous situation —
            // still reported as failure there.
            val alreadyDismissedByEarlierAttempt = attemptsLeft < 3
            android.util.Log.d(
                "JobFilterSwipe",
                "swipeJobCard($direction): no card bounds found in any monitored window " +
                    "(treating as ${if (alreadyDismissedByEarlierAttempt) "already dismissed" else "not found"})"
            )
            callback(alreadyDismissedByEarlierAttempt)
            return
        }
        android.util.Log.d(
            "JobFilterSwipe",
            "swipeJobCard($direction) cardBounds=$bounds stackedJobCount=$stackedJobCount (attemptsLeft=$attemptsLeft)"
        )
        // A "nudge the list up first, to reveal a bottom-clipped card
        // before swiping" step was tried here and reverted — a real device
        // showed it consistently threw off the swipe's aim (Bolt's list was
        // still settling/animating from the nudge by the time the real
        // swipe fired immediately after, so the swipe missed the card's
        // actual position and Bolt never registered it as a decline) — a
        // job that used to swipe correctly on the first try started
        // failing every attempt and only got dismissed on a later retry,
        // by which point it had already expired. Direct swipe against the
        // originally-found bounds, as below, is what was reliably working.
        dispatchSwipe(bounds, direction) { success ->
            android.util.Log.d("JobFilterSwipe", "swipeJobCard($direction) gesture success=$success")
            if (!success) {
                if (attemptsLeft > 1) {
                    attemptSwipeJobCard(direction, anchorKeywords, attemptsLeft - 1, callback)
                } else {
                    callback(false)
                }
                return@dispatchSwipe
            }
            // Widened from 5 to 8 (480ms total, up from 300ms) — a
            // genuinely-registered swipe's dismiss animation may need more
            // than 300ms to finish removing the card from the tree, and a
            // false "failed" verdict here costs a real driver a job that
            // actually was declined correctly.
            verifySwipeDismissed(anchorKeywords, attemptsLeft = 8) { dismissed ->
                if (dismissed || attemptsLeft <= 1) {
                    callback(dismissed)
                } else {
                    android.util.Log.d(
                        "JobFilterSwipe",
                        "swipeJobCard($direction): attempt failed, retrying (attemptsLeft=${attemptsLeft - 1})"
                    )
                    attemptSwipeJobCard(direction, anchorKeywords, attemptsLeft - 1, callback)
                }
            }
        }
    }

    /**
     * A real device proved `dispatchGesture` reporting a swipe as
     * "successfully completed" does NOT mean Bolt actually registered it as
     * a decline — the card visibly stayed on screen, untouched, right up
     * until it expired on its own, while this service's own log said the
     * swipe worked. Android's callback only confirms the touch sequence was
     * delivered, never that the receiving app's own gesture recognizer
     * acted on it. This re-checks whether the same card is still findable
     * after the swipe completes; if it is, the swipe didn't really take
     * effect, so this reports failure instead of a false success — which
     * matters because [AutomationController] only retries a job on its next
     * poll tick when the action genuinely failed, not when it (wrongly)
     * believed it had already succeeded.
     */
    private fun verifySwipeDismissed(anchorKeywords: List<String>, attemptsLeft: Int, callback: (Boolean) -> Unit) {
        val stillThere = monitoredWindowRoots().any { root ->
            try {
                findNodeByKeywords(root, anchorKeywords.map { it.lowercase() }) != null
            } finally {
                @Suppress("DEPRECATION")
                root.recycle()
            }
        }
        if (!stillThere) {
            android.util.Log.d("JobFilterSwipe", "verifySwipeDismissed: card gone, swipe genuinely succeeded")
            callback(true)
            return
        }
        if (attemptsLeft <= 0) {
            android.util.Log.d(
                "JobFilterSwipe",
                "verifySwipeDismissed: card still present after swipe — treating as failed, not a real success"
            )
            callback(false)
            return
        }
        android.os.Handler(mainLooper).postDelayed({
            verifySwipeDismissed(anchorKeywords, attemptsLeft - 1, callback)
        }, ACTION_RETRY_INTERVAL_MS)
    }

    private fun findNodeByKeywords(
        node: AccessibilityNodeInfo,
        keywords: List<String>,
        depth: Int = 0
    ): AccessibilityNodeInfo? {
        if (depth > MAX_TREE_DEPTH) return null

        val text = (node.text?.toString() ?: node.contentDescription?.toString() ?: "").lowercase()
        if (text.isNotBlank() && keywords.any { text.contains(it) }) return node

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = findNodeByKeywords(child, keywords, depth + 1)
            if (found != null) return found
        }
        return null
    }

    /**
     * Walks up from [anchor] to the nearest reasonably card-sized ancestor.
     * Capped at 60% of the window's height so a structural quirk can't walk
     * all the way up to a container spanning multiple cards (or the whole
     * list) when a single-card wrapper doesn't exist at a shallower depth.
     */
    private fun findCardBounds(anchor: AccessibilityNodeInfo, root: AccessibilityNodeInfo): Rect? {
        val rootBounds = Rect()
        root.getBoundsInScreen(rootBounds)
        val maxHeight = (rootBounds.height() * 0.6).toInt()

        var candidate: AccessibilityNodeInfo? = anchor
        var hops = 0
        while (candidate != null && hops < 10) {
            val bounds = Rect()
            candidate.getBoundsInScreen(bounds)
            if (bounds.height() in 300..maxHeight && bounds.width() > 300) return bounds
            candidate = candidate.parent
            hops++
        }
        return null
    }

    /**
     * Diagnostic-only: counts fare-label nodes ([FARE_CARD_LABEL_REGEX])
     * anywhere under [root] — a rough proxy for "how many job offers are
     * stacked in this list right now" (0 or 1 = a single offer, 2+ =
     * genuinely stacked), logged alongside every swipe attempt to test
     * whether swipe reliability actually correlates with list size, per a
     * real driver's live observation that it reliably works for a stacked
     * list but not for a single offer on its own.
     */
    private fun countFareCardNodes(node: AccessibilityNodeInfo, depth: Int = 0): Int {
        if (depth > MAX_TREE_DEPTH) return 0
        var count = if (FARE_CARD_LABEL_REGEX.containsMatchIn(node.text?.toString() ?: "")) 1 else 0
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            try {
                count += countFareCardNodes(child, depth + 1)
            } finally {
                @Suppress("DEPRECATION")
                child.recycle()
            }
        }
        return count
    }

    private fun dispatchSwipe(bounds: Rect, direction: SwipeDirection, callback: (Boolean) -> Unit) {
        val centerY = bounds.centerY().toFloat()
        // A real device showed this landing card-bounds-to-card-bounds only
        // ever swiped the card "half way" — Android reported the gesture as
        // successfully dispatched every time, but the card visually snapped
        // back in place with nothing actually declined, meaning it never
        // crossed Bolt's own internal swipe-to-dismiss threshold (likely
        // velocity-based, not just distance — a slow 400ms drag has much
        // lower release velocity than a real flick even when it fully
        // crosses the card). Two changes address both possibilities at
        // once: the end point now runs to the actual screen edge (not just
        // this card's own detected bounds, which may be narrower than the
        // true swipeable width), and the duration is much shorter, so the
        // same distance now moves at a genuinely fast, decisive flick speed
        // instead of a slow deliberate drag.
        val screenWidth = resources.displayMetrics.widthPixels.toFloat()
        // REVERTED: sending endX past the actual display bounds (negative,
        // or beyond screenWidth) was tried here to address a driver's live
        // report that the card only visibly travels half way — but a real
        // device then showed dispatchGesture's callback never firing at all
        // for those out-of-bounds paths (no onCompleted, no onCancelled —
        // not even the `!dispatched` synchronous-false fallback), i.e. the
        // touch was never delivered at all, which is strictly worse than
        // the "half way" symptom this was meant to fix. Coordinates must
        // stay within the actual screen surface for dispatchGesture to
        // deliver anything. A 1px margin (down from 10f) still lands
        // essentially at the true edge without risking going past it.
        val edgeMargin = 1f
        // Widened from 20f — Material-style cards commonly carry a few
        // pixels of non-interactive elevation/shadow padding around their
        // real touchable content, and starting only 20px in from the
        // card's detected edge risks landing the touch-down in that
        // margin rather than on the actual content view Bolt's swipe
        // recognizer is listening on. 80px moves the start point solidly
        // inside the card. Testing this against the theory that
        // inconsistent hit-testing (not gesture shape/timing) explains
        // both the intermittent full successes and the partial visual
        // travel seen on failures.
        val contentInset = 80f
        val startX: Float
        val endX: Float
        if (direction == SwipeDirection.LEFT) {
            startX = bounds.right - contentInset
            endX = edgeMargin
        } else {
            startX = bounds.left + contentInset
            endX = screenWidth - edgeMargin
        }
        android.util.Log.d(
            "JobFilterSwipe",
            "dispatchSwipe($direction) from=($startX,$centerY) to=($endX,$centerY)"
        )
        // REVERTED (2026-08-18, same night) — abandoning multi-stage
        // acceleration entirely. Every chopped-into-short-segments version
        // tried tonight (2-stage, 4-stage gentle, 4-stage front-loaded) left
        // the card only partially, visibly displaced — a driver watching a
        // screen recording confirmed the drag genuinely engages (the card
        // shows Bolt's own salmon-pink swipe-in-progress background) but
        // never completes to a full swipe. Splitting the path into several
        // very short strokes (as short as 20ms) may simply not give
        // Android's gesture dispatcher enough real time between segments to
        // generate and deliver a smooth, fully-sampled motion event stream
        // for each one — under-sampling a short segment can under-deliver
        // its distance even though the commanded path itself covers the
        // full width. Replacing all of that with the simplest possible
        // thing: a single, unbroken stroke covering the complete distance
        // over a longer duration — enough real time for a full, smooth,
        // fully-sampled motion path with no segment-boundary discontinuities
        // at all, closest to what an actual complete human swipe looks like
        // to Android's own dispatcher. 350ms is the value confirmed working
        // live; tightened twice since per driver request for a snappier
        // feel (220ms, now 160ms) — still a single unbroken stroke, just
        // less real time per attempt each step. If jobs start going
        // unswiped again, this value going too low is the first thing to
        // check — revert toward 350ms before reaching for anything else.
        val path = Path().apply {
            moveTo(startX, centerY)
            lineTo(endX, centerY)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, 160L)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        val dispatched = dispatchGesture(
            gesture,
            object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) = callback(true)
                override fun onCancelled(gestureDescription: GestureDescription?) = callback(false)
            },
            null
        )
        if (!dispatched) callback(false)
    }

    private fun findClickableNodeByKeywords(
        node: AccessibilityNodeInfo,
        keywords: List<String>,
        depth: Int = 0
    ): AccessibilityNodeInfo? {
        if (depth > MAX_TREE_DEPTH) return null

        val text = (node.text?.toString() ?: node.contentDescription?.toString() ?: "").lowercase()
        if (text.isNotBlank() && keywords.any { text.contains(it) }) {
            var candidate: AccessibilityNodeInfo? = node
            var hops = 0
            while (candidate != null && !candidate.isClickable && hops < 10) {
                candidate = candidate.parent
                hops++
            }
            if (candidate?.isClickable == true) return candidate
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = findClickableNodeByKeywords(child, keywords, depth + 1)
            if (found != null) return found
        }
        return null
    }

    /**
     * OCR fallback support (spec section 9) — only reachable on API 30+
     * (AccessibilityService.takeScreenshot requires R). Below that, the
     * method channel handler returns null without calling this.
     */
    @RequiresApi(Build.VERSION_CODES.R)
    fun captureScreenshot(result: MethodChannel.Result) {
        // Same class of race as swipeJobCard: takeScreenshot()
        // captures whatever is on screen *right now*, which can already be
        // JobFilter's own UI (e.g. the driver switched over to check the
        // debug screen) rather than the monitored app that triggered this
        // call — a real device showed this literally get OCR'd as a fake
        // job, with "Accepted" (from the dashboard's own stats label)
        // matching the job-card keyword search and a settings value getting
        // read as a fare. Refuse rather than hand back a screenshot of the
        // wrong app under the caller's assumption it's still Uber/Bolt.
        //
        // Checked via [isMonitoredPackageForeground] (all currently visible
        // windows), not [rootInActiveWindow] alone — a real device proved
        // those can disagree: a driver confirmed a live Uber offer WAS on
        // screen at the exact moment this guard rejected the capture,
        // because Uber's job-card overlay isn't always the window Android's
        // accessibility framework considers "active", the same reason
        // [findAndClickButtonByKeywords] needed the identical fix earlier.
        if (!isMonitoredPackageForeground()) {
            result.success(null)
            return
        }
        // Timed and logged unconditionally, on purpose: a real device showed
        // this whole method taking up to 14+ seconds end to end even though
        // JPEG compression and ML Kit recognition (timed separately on the
        // Dart side) only ever accounted for a couple of seconds of that —
        // meaning the takeScreenshot() call itself, not anything downstream,
        // was the actual bottleneck. Nothing here previously said whether
        // that time was spent waiting for Android's own screenshot rate
        // limit, or a genuine failure (onFailure's errorCode was silently
        // discarded), so there was no way to tell those apart. Safe to trim
        // once that's root-caused.
        val callStart = android.os.SystemClock.elapsedRealtime()
        android.util.Log.d("JobFilterSwipe", "captureScreenshot: calling takeScreenshot()")
        takeScreenshot(
            Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    android.util.Log.d(
                        "JobFilterSwipe",
                        "captureScreenshot: onSuccess after ${android.os.SystemClock.elapsedRealtime() - callStart}ms"
                    )
                    try {
                        val hardwareBitmap =
                            Bitmap.wrapHardwareBuffer(screenshot.hardwareBuffer, screenshot.colorSpace)
                        val softwareBitmap = hardwareBitmap?.copy(Bitmap.Config.ARGB_8888, false)
                        screenshot.hardwareBuffer.close()

                        if (softwareBitmap == null) {
                            result.success(null)
                            return
                        }
                        // Cropped to the bottom half before compression — this
                        // capture only ever exists to OCR a job card's fare/route
                        // text (see OcrTextProvider), and every real sample of
                        // Uber's and Bolt's cards had all of that content, plus
                        // both action buttons, below 49% of screen height (button
                        // bounds around y=1946-2130 of 2340px tall). Cropping the
                        // top (map/status-bar) half away roughly halves the pixel
                        // data before both JPEG encoding and ML Kit recognition
                        // even start — a real device showed the full-screen
                        // recognition pass alone taking several seconds, long
                        // enough that Uber's job offer was routinely gone before
                        // OCR finished reading it. 45% keeps a safety margin above
                        // the earliest observed content start.
                        val cropTop = (softwareBitmap.height * 0.45).toInt()
                        val cropped = Bitmap.createBitmap(
                            softwareBitmap,
                            0,
                            cropTop,
                            softwareBitmap.width,
                            softwareBitmap.height - cropTop
                        )
                        softwareBitmap.recycle()

                        // JPEG, not PNG: a real device measured the PNG path (with
                        // its "quality" argument silently ignored, since PNG is
                        // lossless and always pays full DEFLATE cost) taking
                        // several *seconds* just to compress a single 1080x2340
                        // screenshot — long enough that Uber's job offer was
                        // routinely gone by the time OCR finished reading it.
                        // JPEG's encoder is built for speed and this is a UI
                        // screenshot read by an OCR engine, not an image a human
                        // will zoom into, so quality 90 is more than legible
                        // while cutting encode time dramatically on any device.
                        val stream = ByteArrayOutputStream()
                        cropped.compress(Bitmap.CompressFormat.JPEG, 90, stream)
                        cropped.recycle()
                        result.success(stream.toByteArray())
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }

                override fun onFailure(errorCode: Int) {
                    android.util.Log.d(
                        "JobFilterSwipe",
                        "captureScreenshot: onFailure errorCode=$errorCode after " +
                            "${android.os.SystemClock.elapsedRealtime() - callStart}ms"
                    )
                    result.success(null)
                }
            }
        )
    }

    /**
     * Visual-understanding pipeline support: returns the FULL, uncropped
     * display frame plus its exact pixel dimensions, unlike
     * [captureScreenshot] (which crops to the bottom ~55% purely as a speed
     * optimization for the plain-text OCR reading path). The visual model
     * needs the whole frame because its detected regions are normalized
     * against actual display geometry (0.0-1.0 of full width/height) — see
     * domain/vision/uber_offer_visual_model.dart — and a cropped frame would
     * need its own offset tracked and re-applied everywhere downstream,
     * which is exactly the kind of implicit per-capture assumption that
     * architecture is meant to avoid. Width/height are read directly off
     * the captured Bitmap and returned alongside the bytes so the Dart side
     * never has to re-decode the JPEG just to learn its own dimensions.
     */
    /**
     * `Context.getDisplay()` (the `display` property) throws
     * `UnsupportedOperationException` on a plain [AccessibilityService]
     * context — confirmed on a real device, every single call — because a
     * [android.app.Service] isn't a "visual" context per that API's own
     * contract. [DisplayManager] sidesteps that: it looks the display up by
     * ID directly rather than asking the calling context to be associated
     * with one.
     */
    private fun currentDisplayRotation(): Int {
        val displayManager = getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
        return displayManager?.getDisplay(Display.DEFAULT_DISPLAY)?.rotation ?: 0
    }

    @RequiresApi(Build.VERSION_CODES.R)
    fun captureScreenFrame(result: MethodChannel.Result) {
        // See [captureScreenshot]'s identical guard for why this checks all
        // windows rather than just [rootInActiveWindow].
        if (!isMonitoredPackageForeground()) {
            result.success(null)
            return
        }
        val callStart = android.os.SystemClock.elapsedRealtime()
        takeScreenshot(
            Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    android.util.Log.d(
                        "JobFilterVision",
                        "captureScreenFrame: onSuccess after ${android.os.SystemClock.elapsedRealtime() - callStart}ms"
                    )
                    try {
                        val hardwareBitmap =
                            Bitmap.wrapHardwareBuffer(screenshot.hardwareBuffer, screenshot.colorSpace)
                        val softwareBitmap = hardwareBitmap?.copy(Bitmap.Config.ARGB_8888, false)
                        screenshot.hardwareBuffer.close()

                        if (softwareBitmap == null) {
                            result.success(null)
                            return
                        }
                        val width = softwareBitmap.width
                        val height = softwareBitmap.height
                        val stream = ByteArrayOutputStream()
                        softwareBitmap.compress(Bitmap.CompressFormat.JPEG, 90, stream)
                        softwareBitmap.recycle()
                        result.success(
                            mapOf(
                                "bytes" to stream.toByteArray(),
                                "width" to width,
                                "height" to height,
                                "rotation" to currentDisplayRotation()
                            )
                        )
                    } catch (e: Exception) {
                        android.util.Log.d("JobFilterVision", "captureScreenFrame: exception $e")
                        result.success(null)
                    }
                }

                override fun onFailure(errorCode: Int) {
                    android.util.Log.d(
                        "JobFilterVision",
                        "captureScreenFrame: onFailure errorCode=$errorCode after " +
                            "${android.os.SystemClock.elapsedRealtime() - callStart}ms"
                    )
                    result.success(null)
                }
            }
        )
    }

    /**
     * Same capture as [captureScreenFrame], cropped to the bottom 45% before
     * JPEG compression — the same threshold [captureScreenshot] already
     * proved safe for every real Uber/Bolt card sample this project has
     * seen. [captureScreenFrame] can't crop (the debug screen's calibration
     * overlay needs real full-screen coordinates), but production's
     * decision badge (see AutomationController._processUberVisual) only
     * ever reads fare/distance/duration/keyword text — nothing in that path
     * uses absolute on-screen coordinates any more, since it never
     * dispatches a gesture — so the crop costs nothing there while cutting
     * real work on both ends: less bitmap to JPEG-encode here, and a
     * meaningfully smaller image for ML Kit to run text recognition on. A
     * real device showed the decision badge appearing late (sometimes after
     * the job card was already gone) with the full-frame capture; this
     * exists specifically to close that gap.
     */
    @RequiresApi(Build.VERSION_CODES.R)
    fun captureScreenFrameForDetection(result: MethodChannel.Result) {
        if (!isMonitoredPackageForeground()) {
            result.success(null)
            return
        }
        val callStart = android.os.SystemClock.elapsedRealtime()
        takeScreenshot(
            Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    android.util.Log.d(
                        "JobFilterVision",
                        "captureScreenFrameForDetection: onSuccess after " +
                            "${android.os.SystemClock.elapsedRealtime() - callStart}ms"
                    )
                    try {
                        val hardwareBitmap =
                            Bitmap.wrapHardwareBuffer(screenshot.hardwareBuffer, screenshot.colorSpace)
                        val softwareBitmap = hardwareBitmap?.copy(Bitmap.Config.ARGB_8888, false)
                        screenshot.hardwareBuffer.close()

                        if (softwareBitmap == null) {
                            result.success(null)
                            return
                        }
                        val cropTop = (softwareBitmap.height * 0.45).toInt()
                        val cropped = Bitmap.createBitmap(
                            softwareBitmap,
                            0,
                            cropTop,
                            softwareBitmap.width,
                            softwareBitmap.height - cropTop
                        )
                        softwareBitmap.recycle()
                        val width = cropped.width
                        val height = cropped.height
                        val stream = ByteArrayOutputStream()
                        cropped.compress(Bitmap.CompressFormat.JPEG, 90, stream)
                        cropped.recycle()
                        result.success(
                            mapOf(
                                "bytes" to stream.toByteArray(),
                                "width" to width,
                                "height" to height,
                                "rotation" to currentDisplayRotation()
                            )
                        )
                    } catch (e: Exception) {
                        android.util.Log.d("JobFilterVision", "captureScreenFrameForDetection: exception $e")
                        result.success(null)
                    }
                }

                override fun onFailure(errorCode: Int) {
                    android.util.Log.d(
                        "JobFilterVision",
                        "captureScreenFrameForDetection: onFailure errorCode=$errorCode after " +
                            "${android.os.SystemClock.elapsedRealtime() - callStart}ms"
                    )
                    result.success(null)
                }
            }
        )
    }

    private var decisionOverlayView: android.widget.TextView? = null

    /**
     * The human-taps-it flow (spec: this app never automates Uber's actual
     * accept/reject, per the decision to stop trying to defeat whatever
     * distinguishes a real touch from an [dispatchGesture]-injected one on
     * those controls) — this is a small, non-interactive badge shown over
     * whatever app is in front, telling the driver ACCEPT/REJECT and the
     * £/mile so they can tap Uber's own button themselves. [TYPE_ACCESSIBILITY_OVERLAY]
     * is used instead of a normal [TYPE_APPLICATION_OVERLAY] specifically
     * because it's granted automatically to a bound AccessibilityService —
     * no `SYSTEM_ALERT_WINDOW`/"draw over other apps" permission prompt
     * needed. [FLAG_NOT_TOUCHABLE] makes sure this badge can never itself
     * intercept the driver's tap meant for Uber's real button underneath.
     */
    fun showDecisionOverlay(poundsPerMileText: String, isAccept: Boolean) {
        mainExecutor.execute {
            val backgroundColor = if (isAccept) 0xFF2E7D32.toInt() else 0xFFC62828.toInt()
            val actionText = if (isAccept) "ACCEPT" else "REJECT"
            val displayText = "$poundsPerMileText\n$actionText"

            val existing = decisionOverlayView
            if (existing != null) {
                existing.text = displayText
                (existing.background as? android.graphics.drawable.GradientDrawable)?.setColor(backgroundColor)
                return@execute
            }

            try {
                val windowManager = getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager
                val view = android.widget.TextView(this).apply {
                    text = displayText
                    setTextColor(android.graphics.Color.WHITE)
                    textSize = 16f
                    typeface = android.graphics.Typeface.DEFAULT_BOLD
                    gravity = android.view.Gravity.CENTER
                    setPadding(48, 32, 48, 32)
                    background = android.graphics.drawable.GradientDrawable().apply {
                        cornerRadius = 32f
                        setColor(backgroundColor)
                    }
                }
                val params = android.view.WindowManager.LayoutParams(
                    android.view.WindowManager.LayoutParams.WRAP_CONTENT,
                    android.view.WindowManager.LayoutParams.WRAP_CONTENT,
                    android.view.WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    android.view.WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        android.view.WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                    android.graphics.PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = android.view.Gravity.TOP or android.view.Gravity.CENTER_HORIZONTAL
                    y = 150
                }
                windowManager.addView(view, params)
                decisionOverlayView = view
            } catch (e: Exception) {
                android.util.Log.d("JobFilterVision", "showDecisionOverlay: failed to add view: $e")
            }
        }
    }

    /**
     * Called whenever the visual pipeline no longer sees a confident
     * accept/reject match on screen — the job was acted on (by the driver),
     * expired, or the driver navigated away, and any of those must clear
     * this badge rather than leave a stale ACCEPT/REJECT floating over
     * whatever's on screen next.
     */
    fun hideDecisionOverlay() {
        mainExecutor.execute {
            val view = decisionOverlayView ?: return@execute
            try {
                val windowManager = getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager
                windowManager.removeView(view)
            } catch (e: Exception) {
                android.util.Log.d("JobFilterVision", "hideDecisionOverlay: failed to remove view: $e")
            }
            decisionOverlayView = null
        }
    }

    

    private var balExemptionOverlayView: android.view.View? = null

    /**
     * A real device proved Android blocks BoltJobNotificationListenerService
     * from firing Bolt's own suppressed job-offer intent while backgrounded —
     * confirmed directly via the platform's own "Background activity launch
     * blocked" log, which specifically evaluates whether the REAL caller
     * (JobFilter) holds `SYSTEM_ALERT_WINDOW` AND currently has a
     * non-app-owned visible window up (`realCallingUidHasNonAppVisibleWindow`)
     * as one of its recognized exemptions. Holding the permission alone,
     * confirmed empirically, was not sufficient — an actual window needs to
     * be showing. Unlike [showDecisionOverlay]'s `TYPE_ACCESSIBILITY_OVERLAY`
     * (exempt from the permission entirely, but also doesn't count for this
     * specific exemption check), this deliberately uses
     * `TYPE_APPLICATION_OVERLAY`, the type `SYSTEM_ALERT_WINDOW` actually
     * governs. 1x1 and fully transparent — it exists purely to satisfy this
     * platform check, never to be seen. Kept up for the service's entire
     * lifetime rather than added/removed per job, since the exemption is
     * evaluated at the moment a job notification posts, which can't be
     * predicted in advance.
     */
    private fun addBalExemptionOverlay() {
        if (balExemptionOverlayView != null) return
        try {
            val windowManager = getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager
            val view = android.view.View(this)
            val params = android.view.WindowManager.LayoutParams(
                1,
                1,
                android.view.WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                android.view.WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    android.view.WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                android.graphics.PixelFormat.TRANSLUCENT
            ).apply {
                gravity = android.view.Gravity.TOP or android.view.Gravity.START
            }
            windowManager.addView(view, params)
            balExemptionOverlayView = view
        } catch (e: Exception) {
            // Missing SYSTEM_ALERT_WINDOW grant is the expected failure mode
            // here (driver hasn't enabled "Display over other apps" yet) —
            // launchBoltApp will simply keep failing under BAL until they do.
            android.util.Log.d("JobFilterNotif", "addBalExemptionOverlay: failed to add view: $e")
        }
    }

    private fun removeBalExemptionOverlay() {
        val view = balExemptionOverlayView ?: return
        try {
            val windowManager = getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager
            windowManager.removeView(view)
        } catch (e: Exception) {
            android.util.Log.d("JobFilterNotif", "removeBalExemptionOverlay: failed to remove view: $e")
        }
        balExemptionOverlayView = null
    }


    /**
     * Called by [BoltJobNotificationListenerService] instead of firing
     * Bolt's own `fullScreenIntent`/`contentIntent` PendingIntent directly —
     * a real device proved Android's Background Activity Launch hardening
     * specifically targets and blocks exactly that pattern (a third-party
     * app re-firing another app's dormant PendingIntent to sneak an activity
     * to the foreground), regardless of what permissions the third party
     * holds. A plain, ordinary `startActivity()` using JobFilter's own
     * calling identity is a different, non-PendingIntent code path that
     * Android's standard SYSTEM_ALERT_WINDOW-based exemption (see
     * [addBalExemptionOverlay]) actually applies to.
     */
    fun launchBoltApp() {
        try {
            val intent = packageManager.getLaunchIntentForPackage(MonitoredPackages.BOLT_DRIVER)
                ?: return
            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            android.util.Log.d("JobFilterNotif", "launchBoltApp: startActivity called")
        } catch (e: Exception) {
            android.util.Log.d("JobFilterNotif", "launchBoltApp: failed: $e")
        }
    }

    override fun onInterrupt() {
        // Required override. No ongoing gesture/animation to cancel — this
        // service never performs continuous interactions.
    }

    override fun onDestroy() {
        super.onDestroy()
        pollHandler.removeCallbacks(pollRunnable)
        hideDecisionOverlay()
        removeBalExemptionOverlay()
        instance = null
    }
}
