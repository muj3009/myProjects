package com.jobfilter.app.automation

import io.flutter.plugin.common.EventChannel

/**
 * Small glue object connecting the two Android-only components that need to
 * push events into Flutter — [JobAccessibilityService] (detected job text)
 * and [AutomationForegroundService] (the notification's STOP action) — to
 * the [EventChannel] sinks owned by AutomationMethodChannelHandler.
 *
 * Kept as a single object rather than wiring services directly together
 * because Android may create/destroy the accessibility service and the
 * foreground service independently; neither should need a direct reference
 * to the other.
 */
object AutomationBridge {
    private var detectedTextSink: EventChannel.EventSink? = null
    private var controlEventSink: EventChannel.EventSink? = null

    fun attachDetectedTextSink(sink: EventChannel.EventSink?) {
        detectedTextSink = sink
    }

    fun attachControlEventSink(sink: EventChannel.EventSink?) {
        controlEventSink = sink
    }

    /** Called by [JobAccessibilityService] whenever it observes new job-relevant text. */
    fun emitDetectedText(text: String) {
        detectedTextSink?.success(text)
    }

    /** Called by [AutomationForegroundService] when its STOP action is tapped. */
    fun emitStopRequested() {
        controlEventSink?.success(null)
    }
}
