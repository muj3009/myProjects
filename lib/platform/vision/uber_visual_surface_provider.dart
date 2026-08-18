import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/errors/failures.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/result.dart';
import '../automation/automation_method_channel.dart';
import 'screen_frame.dart';

const _tag = 'UberVisualSurfaceProvider';

/// Screen-acquisition layer for the visual-understanding pipeline (spec:
/// production visual architecture, section 1). Wraps
/// `AccessibilityService.takeScreenshot()` — Android's own, no-extra-consent
/// API for a service that's already been granted the accessibility
/// permission — via [AutomationMethodChannel.captureScreenFrame].
///
/// This is the FIRST-CHOICE provider. A [MediaProjectionScreenProvider]
/// (requiring the one-time system screen-capture consent dialog) is only
/// worth adding later if a real device shows this API to be insufficient —
/// it hasn't been so far; see [captureFrame]'s own reliability notes.
class UberVisualSurfaceProvider {
  UberVisualSurfaceProvider({AutomationMethodChannel? channel})
      : _channel = channel ?? AutomationMethodChannel();

  final AutomationMethodChannel _channel;

  /// Single-flight guard — a slow capture and a second, concurrent one would
  /// both hit the native screenshot pipeline at once. See OcrTextProvider's
  /// own copy of this same guard for the real-device evidence that made it
  /// necessary (concurrent captures intermittently failed with
  /// FileNotFoundException on the temp files each produced).
  bool _capturing = false;

  /// [cropped] uses [AutomationMethodChannel.captureScreenFrameForDetection]
  /// (bottom 45% only) instead of the full frame — see that method's doc
  /// comment for why production passes true and the debug screen's
  /// calibration display passes false (default).
  Future<Result<ScreenFrame>> captureFrame({bool cropped = false}) async {
    if (_capturing) {
      AppLogger.instance.debug(_tag, 'captureFrame: skipped — previous capture still in progress');
      return const Result.err(AutomationFailure('Screen capture already in progress'));
    }
    _capturing = true;
    try {
      final raw = cropped ? await _channel.captureScreenFrameForDetection() : await _channel.captureScreenFrame();
      if (raw == null) {
        return const Result.err(AutomationFailure('Screen frame unavailable'));
      }
      final bytes = raw['bytes'] as Uint8List?;
      final width = raw['width'] as int?;
      final height = raw['height'] as int?;
      final rotation = raw['rotation'] as int? ?? 0;
      if (bytes == null || width == null || height == null) {
        AppLogger.instance.warning(_tag, 'captureFrame: malformed native result $raw');
        return const Result.err(AutomationFailure('Screen frame malformed'));
      }
      return Result.ok(
        ScreenFrame(
          bytes: bytes,
          width: width,
          height: height,
          densityPixelRatio: ui.PlatformDispatcher.instance.views.first.devicePixelRatio,
          rotation: rotation,
          timestamp: DateTime.now(),
        ),
      );
    } finally {
      _capturing = false;
    }
  }
}
