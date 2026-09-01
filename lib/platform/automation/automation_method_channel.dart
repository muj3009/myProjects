import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/utils/app_logger.dart';
import '../../domain/enums/platform_type.dart';
import '../accessibility/accessibility_status.dart';
import '../channel_names.dart';

/// Thin Dart-side wrapper around the platform channel that talks to the
/// Android Kotlin automation module. This is the ONLY file that should touch
/// [MethodChannel]/[EventChannel] directly for automation — everything else
/// (AutomationController, screens) goes through [PlatformActionExecutor] or
/// [ScreenTextProvider] instead, per spec section 2's layering requirement.
///
/// Every method here is Android-specific. iOS never registers handlers for
/// this channel, so calls from an iOS build should not be made — the
/// application layer selects [IosAutomationProvider] instead based on
/// `Platform.isAndroid`.
class AutomationMethodChannel {
  AutomationMethodChannel({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    EventChannel? controlEventChannel,
  })  : _methodChannel = methodChannel ?? const MethodChannel(ChannelNames.automationMethods),
        _eventChannel = eventChannel ?? const EventChannel(ChannelNames.automationEvents),
        _controlEventChannel =
            controlEventChannel ?? const EventChannel(ChannelNames.automationControlEvents);

  static const _tag = 'AutomationChannel';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final EventChannel _controlEventChannel;

  Stream<String>? _detectedTextStream;
  Stream<void>? _stopRequestedStream;

  /// Emits once whenever the driver taps STOP on the persistent foreground
  /// notification, so [AutomationController] can run the same emergency-stop
  /// path as the in-app button (spec section 25).
  Stream<void> stopRequestedFromNotificationEvents() {
    return _stopRequestedStream ??= _controlEventChannel
        .receiveBroadcastStream()
        .map((_) {})
        .handleError((Object e) => AppLogger.instance.error(_tag, 'Control event stream error: $e'));
  }

  /// Stream of raw text snapshots the Accessibility Service emits whenever it
  /// observes a UI change in a monitored driver app. One event per relevant
  /// change, NOT a continuous poll — see docs/android-automation.md.
  Stream<String> detectedTextEvents() {
    return _detectedTextStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => event as String)
        .handleError((Object e) => AppLogger.instance.error(_tag, 'Event stream error: $e'));
  }

  Future<AccessibilityStatus> getAccessibilityStatus() async {
    try {
      final enabled = await _methodChannel.invokeMethod<bool>('isAccessibilityServiceEnabled');
      return enabled == true ? AccessibilityStatus.enabled : AccessibilityStatus.disabled;
    } on PlatformException catch (e) {
      AppLogger.instance.warning(_tag, 'Failed to read accessibility status: $e');
      return AccessibilityStatus.unknown;
    }
  }

  Future<void> openAccessibilitySettings() async {
    await _invokeVoid('openAccessibilitySettings');
  }

  Future<bool> isBatteryOptimizationIgnored() async {
    final result = await _methodChannel.invokeMethod<bool>('isBatteryOptimizationIgnored');
    return result ?? false;
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    await _invokeVoid('requestIgnoreBatteryOptimizations');
  }

  /// Separate from [getAccessibilityStatus] — Android's "Notification
  /// access" is its own permission grant, required by
  /// BoltJobNotificationListenerService (native) to fire Bolt's suppressed
  /// full-screen job-offer intent while backgrounded. See that class's doc
  /// comment for why this exists at all.
  Future<bool> isNotificationListenerEnabled() async {
    final result = await _methodChannel.invokeMethod<bool>('isNotificationListenerEnabled');
    return result ?? false;
  }

  Future<void> openNotificationListenerSettings() async {
    await _invokeVoid('openNotificationListenerSettings');
  }

  /// "Display over other apps" — a real device proved Android's Background
  /// Activity Launch restrictions block
  /// BoltJobNotificationListenerService's attempt to open Bolt's job screen
  /// unless JobFilter holds this (the platform's own block log names
  /// BAL_ALLOW_SAW_PERMISSION as exactly what lifts it).
  Future<bool> isOverlayPermissionGranted() async {
    final result = await _methodChannel.invokeMethod<bool>('isOverlayPermissionGranted');
    return result ?? false;
  }

  Future<void> openOverlayPermissionSettings() async {
    await _invokeVoid('openOverlayPermissionSettings');
  }

  Future<String?> getForegroundPackageName() async {
    try {
      return await _methodChannel.invokeMethod<String>('getForegroundPackageName');
    } on PlatformException catch (e) {
      AppLogger.instance.warning(_tag, 'Failed to read foreground package: $e');
      return null;
    }
  }

  Future<void> startForegroundMonitoring() async {
    await _invokeVoid('startForegroundMonitoring');
  }

  Future<void> stopForegroundMonitoring() async {
    await _invokeVoid('stopForegroundMonitoring');
  }

  /// Attempts to tap the currently-identified Accept control. The native
  /// side re-validates that a matching job is still visible before acting —
  /// see docs/android-automation.md "Safety checks executed natively".
  /// [cardAnchor] (e.g. a pickup address) lets Bolt target one specific
  /// offer when more than one is visible at once; Uber ignores it entirely
  /// and finds its accept button by keyword instead — see
  /// [PlatformActionExecutor.acceptJob] and
  /// AutomationMethodChannelHandler.acceptJob (Kotlin) for why: a real
  /// device's `uiautomator dump` proved Uber's whole job card, accept
  /// button included, is a real clickable node in the accessibility tree
  /// with no card to open first, unlike Bolt's.
  Future<bool> tapAcceptControl({required PlatformType platform, String? cardAnchor}) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'tapAcceptControl',
      {'platform': platform.name, 'cardAnchor': cardAnchor},
    );
    return result ?? false;
  }

  Future<bool> tapRejectControl({required PlatformType platform, String? cardAnchor}) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'tapRejectControl',
      {'platform': platform.name, 'cardAnchor': cardAnchor},
    );
    return result ?? false;
  }

  /// Bolt-only — opens the job's "Change price" flow and taps the highest
  /// suggested counter-offer amount. See
  /// [JobAccessibilityService.counterOfferJobCard] (Kotlin) for the tap
  /// sequence, built against a real device's actual screen structure.
  Future<bool> counterOfferJob({required PlatformType platform, String? cardAnchor}) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'counterOfferJob',
      {'platform': platform.name, 'cardAnchor': cardAnchor},
    );
    return result ?? false;
  }

  /// Requests a screenshot of the current screen for OCR fallback use only
  /// (spec section 9). Returns PNG bytes, or null if unavailable/denied.
  Future<Uint8List?> captureScreenshotForOcr() async {
    try {
      return await _methodChannel.invokeMethod<Uint8List>('captureScreenshotForOcr');
    } on PlatformException catch (e) {
      AppLogger.instance.warning(_tag, 'Screenshot capture failed: $e');
      return null;
    }
  }

  /// Full, uncropped display frame for the visual-understanding pipeline —
  /// see [UberVisualSurfaceProvider]. Distinct from
  /// [captureScreenshotForOcr], which crops to the bottom ~55% purely as a
  /// speed optimization for plain-text OCR reading; the visual model needs
  /// the whole frame because its detections are normalized against real
  /// display geometry. Returns null if unavailable/denied (e.g. API < 30,
  /// or the foreground app isn't a monitored one at the moment of capture).
  Future<Map<Object?, Object?>?> captureScreenFrame() async {
    try {
      return await _methodChannel.invokeMapMethod<Object?, Object?>('captureScreenFrame');
    } on PlatformException catch (e) {
      AppLogger.instance.warning(_tag, 'Screen frame capture failed: $e');
      return null;
    }
  }

  /// Same as [captureScreenFrame], cropped to the bottom 45% before JPEG
  /// compression — used by production's decision badge (see
  /// [AutomationController._processUberVisual]), which never dispatches a
  /// gesture and so has no need for full-screen absolute coordinates, only
  /// the fare/distance/duration/keyword text that crop still fully contains.
  /// A real device showed the badge appearing late (sometimes after the job
  /// card was already gone) with the full-frame capture; this exists
  /// specifically to close that gap by giving both JPEG encoding and ML Kit
  /// OCR meaningfully less image to process.
  Future<Map<Object?, Object?>?> captureScreenFrameForDetection() async {
    try {
      return await _methodChannel.invokeMapMethod<Object?, Object?>('captureScreenFrameForDetection');
    } on PlatformException catch (e) {
      AppLogger.instance.warning(_tag, 'Cropped screen frame capture failed: $e');
      return null;
    }
  }

  /// Shows (or updates) the small floating ACCEPT/REJECT badge used for
  /// Uber — see [AutomationController._processUberVisual]. Deliberately the
  /// ONLY thing JobFilter does for Uber's job offers: no gesture is ever
  /// dispatched at this control, the driver taps Uber's own real button
  /// themselves. [poundsPerMileText] is shown above the ACCEPT/REJECT label
  /// — the £/mile figure, plus the estimated £/hour ("the time factor")
  /// appended when a duration was actually available.
  Future<void> showUberDecisionOverlay({required String poundsPerMileText, required bool isAccept}) async {
    await _invokeVoidWithArgs('showUberDecisionOverlay', {
      'poundsPerMileText': poundsPerMileText,
      'isAccept': isAccept,
    });
  }

  /// Clears the badge — called the moment the visual pipeline no longer
  /// sees a confident match on screen (job acted on, expired, or gone),
  /// so it never lingers showing a stale decision.
  Future<void> hideUberDecisionOverlay() async {
    await _invokeVoid('hideUberDecisionOverlay');
  }

  /// Posts a real Android notification (with sound) — called only when
  /// Bolt's fully-automated accept actually succeeds (see
  /// [AutomationController._processCard]). Bolt's job offer is a system
  /// notification/small overlay panel, not something that keeps the app in
  /// front, so a driver whose attention is on another app has no other way
  /// to learn a job was just committed on their behalf. Never called for
  /// Uber, which only ever shows a badge for the driver to act on
  /// themselves — they already know, since they tapped it.
  Future<void> showJobAcceptedNotification({required String contentText}) async {
    await _invokeVoidWithArgs('showJobAcceptedNotification', {'contentText': contentText});
  }

  /// Driver request: a small draggable "online" indicator, like Uber/Bolt's
  /// own status circle, floating over any app while automation is active.
  /// Called from [AutomationController.start]/`stop`, not tied to whether
  /// the Accessibility Service itself is bound — that stays connected
  /// regardless of whether the driver has automation switched on.
  Future<void> showOnlineBubble() async {
    await _invokeVoid('showOnlineBubble');
  }

  Future<void> hideOnlineBubble() async {
    await _invokeVoid('hideOnlineBubble');
  }

  Future<void> _invokeVoidWithArgs(String method, Map<String, Object?> args) async {
    try {
      await _methodChannel.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      AppLogger.instance.warning(_tag, '$method failed: $e');
    }
  }

  Future<void> _invokeVoid(String method) async {
    try {
      await _methodChannel.invokeMethod<void>(method);
    } on PlatformException catch (e) {
      AppLogger.instance.warning(_tag, '$method failed: $e');
    }
  }

  /// Clears the last emitted text in the accessibility service so the next
  /// detection will be emitted even if the text is identical to a previous detection.
  Future<void> clearLastEmittedText() async {
    await _invokeVoid('clearLastEmittedText');
  }
}
