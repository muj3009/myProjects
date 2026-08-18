import '../../core/errors/failures.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/result.dart';
import '../../domain/enums/platform_type.dart';
import '../accessibility/accessibility_status.dart';
import 'automation_method_channel.dart';
import 'platform_action_executor.dart';

/// Android implementation of [PlatformActionExecutor]. Delegates the actual
/// tap to the Accessibility Service via [AutomationMethodChannel]; the
/// service itself re-verifies the visible job before clicking anything
/// (spec section 15, point 6) — this class does not (and cannot, from Dart)
/// bypass that check.
class AndroidPlatformActionExecutor implements PlatformActionExecutor {
  AndroidPlatformActionExecutor({AutomationMethodChannel? channel})
      : _channel = channel ?? AutomationMethodChannel();

  final AutomationMethodChannel _channel;
  static const _tag = 'AndroidActionExecutor';

  /// Android only allows one gesture dispatch in flight at a time per
  /// accessibility service. Processing a stacked batch of cards
  /// concurrently (see [AutomationController]'s `Future.wait` over
  /// `_processCard`) means two of these native accept/reject/counter-offer
  /// calls can now genuinely overlap — a second `dispatchGesture` firing
  /// while an earlier one is still completing risks silently cancelling
  /// it. This queue serializes only the native round trip itself; each
  /// card's own evaluation/decision still runs fully concurrently and
  /// isn't delayed by this — a card only ever waits behind another one's
  /// actual on-screen tap/swipe, never behind its decision-making.
  Future<void> _actionQueue = Future.value();

  Future<bool> _enqueue(Future<bool> Function() action) {
    final result = _actionQueue.then((_) => action());
    // Chain the next link off a version that swallows this action's own
    // failure — so one tap/swipe failing can never wedge every subsequent
    // queued action behind it forever.
    _actionQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  bool get isAutomationSupportedOnThisPlatform => true;

  @override
  Future<bool> canPerformActions() async {
    final status = await _channel.getAccessibilityStatus();
    return status == AccessibilityStatus.enabled;
  }

  @override
  Future<Result<void>> acceptJob({required PlatformType platform, String? cardAnchor}) async {
    if (!await canPerformActions()) {
      return const Result.err(
        AutomationFailure('Accessibility Service is not enabled'),
      );
    }
    final tapped = await _enqueue(
      () => _channel.tapAcceptControl(platform: platform, cardAnchor: cardAnchor),
    );
    if (!tapped) {
      AppLogger.instance.warning(_tag, 'Accept control tap reported failure');
      return const Result.err(
        AutomationFailure('Accept control could not be located/tapped'),
      );
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> rejectJob({required PlatformType platform, String? cardAnchor}) async {
    if (!await canPerformActions()) {
      return const Result.err(
        AutomationFailure('Accessibility Service is not enabled'),
      );
    }
    final tapped = await _enqueue(
      () => _channel.tapRejectControl(platform: platform, cardAnchor: cardAnchor),
    );
    if (!tapped) {
      AppLogger.instance.warning(_tag, 'Reject control tap reported failure');
      return const Result.err(
        AutomationFailure('Reject control could not be located/tapped'),
      );
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> counterOfferJob({required PlatformType platform, String? cardAnchor}) async {
    if (!await canPerformActions()) {
      return const Result.err(
        AutomationFailure('Accessibility Service is not enabled'),
      );
    }
    final tapped = await _enqueue(
      () => _channel.counterOfferJob(platform: platform, cardAnchor: cardAnchor),
    );
    if (!tapped) {
      AppLogger.instance.warning(_tag, 'Counter-offer flow reported failure');
      return const Result.err(
        AutomationFailure('Counter-offer control could not be located/tapped'),
      );
    }
    return const Result.ok(null);
  }
}
