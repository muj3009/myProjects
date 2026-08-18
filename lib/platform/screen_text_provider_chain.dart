import '../core/errors/failures.dart';
import '../core/utils/app_logger.dart';
import '../core/utils/result.dart';
import 'screen_text_provider.dart';

/// Tries a list of [ScreenTextProvider]s in order, per spec section 9's
/// required priority (accessibility, then notification, then OCR), and
/// returns the first successful result. Centralizing the fallback order here
/// means it can be changed in one place without touching AutomationController.
class ScreenTextProviderChain implements ScreenTextProvider {
  ScreenTextProviderChain(this._providersInPriorityOrder);

  final List<ScreenTextProvider> _providersInPriorityOrder;
  static const _tag = 'ScreenTextProviderChain';

  @override
  String get name => 'ScreenTextProviderChain';

  @override
  Future<Result<String>> getScreenText() async {
    if (_providersInPriorityOrder.isEmpty) {
      return const Result.err(AutomationFailure('No screen text providers configured'));
    }

    Failure? lastFailure;
    for (final provider in _providersInPriorityOrder) {
      final result = await provider.getScreenText();
      if (result.isOk) {
        return result;
      }
      lastFailure = result.failureOrNull;
      AppLogger.instance.debug(_tag, '${provider.name} unavailable: $lastFailure');
    }
    return Result.err(lastFailure ?? const AutomationFailure('No screen text available'));
  }
}
