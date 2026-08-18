import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../automation/automation_method_channel.dart';
import '../screen_text_provider.dart';

/// Primary [ScreenTextProvider]: reads text already surfaced by the Android
/// Accessibility Service's semantic UI tree. This never involves rendering,
/// screenshots, or OCR — it's the cheapest and most reliable source, so it's
/// always tried first (spec section 9).
///
/// In this Dart layer the provider is a thin pull-based wrapper; in practice
/// [AutomationController] mostly reacts to
/// [AutomationMethodChannel.detectedTextEvents] directly, and this class is
/// used when an on-demand re-read of the current screen is needed instead of
/// waiting for the next event.
class AccessibilityTextProvider implements ScreenTextProvider {
  AccessibilityTextProvider({AutomationMethodChannel? channel})
      : _channel = channel ?? AutomationMethodChannel();

  final AutomationMethodChannel _channel;

  @override
  String get name => 'AccessibilityTextProvider';

  @override
  Future<Result<String>> getScreenText() async {
    final package = await _channel.getForegroundPackageName();
    if (package == null) {
      return const Result.err(
        AutomationFailure('No foreground package reported by the Accessibility Service'),
      );
    }
    // The Accessibility Service pushes text via the event stream as UI
    // changes happen; there is no separate "read now" method because
    // re-querying the whole node tree on demand would defeat the
    // event-driven, low-CPU design (spec section 45).
    return const Result.err(
      AutomationFailure(
        'On-demand accessibility read not supported; subscribe to detectedTextEvents() instead',
      ),
    );
  }
}
