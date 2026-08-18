import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../screen_text_provider.dart';

/// Extension point for a future source: structured job data delivered via a
/// system notification the driver app posts (spec section 9 lists this as
/// priority 2, above OCR). Neither Uber Driver nor Bolt Driver is currently
/// known to post machine-readable notification content for job offers, so
/// this provider always reports unavailable rather than guessing at a
/// notification schema that doesn't exist — see docs/parser-design.md.
///
/// If a driver app (or an official API) starts providing this legitimately,
/// only this file needs to change; [ScreenTextProviderChain] already tries
/// providers in priority order.
class NotificationTextProvider implements ScreenTextProvider {
  const NotificationTextProvider();

  @override
  String get name => 'NotificationTextProvider';

  @override
  Future<Result<String>> getScreenText() async {
    return const Result.err(
      AutomationFailure('No structured notification source is currently available'),
    );
  }
}
