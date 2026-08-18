import '../core/utils/result.dart';

/// Source of text describing whatever is currently on screen in a monitored
/// driver app. Implementations are tried in the priority order defined in
/// spec section 9:
///   1. [AccessibilityTextProvider] — semantic UI node text (cheapest, most
///      reliable, no image processing).
///   2. NotificationTextProvider — structured notification payloads, where a
///      driver app legitimately posts one (not currently emitted by
///      Uber/Bolt, kept as an extension point).
///   3. [OcrTextProvider] — screenshot + on-device text recognition, used
///      only when the above yield nothing.
///
/// A single call must do minimal work: implementations must not poll
/// continuously (spec section 45) — they react to an event that already told
/// them something worth reading might be on screen.
abstract interface class ScreenTextProvider {
  String get name;

  Future<Result<String>> getScreenText();
}
