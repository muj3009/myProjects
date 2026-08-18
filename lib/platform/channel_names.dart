/// Method/event channel names shared between Dart and the Android Kotlin
/// implementation. Centralized so the Dart and native sides can't drift
/// silently — grep this string on the Kotlin side to find every usage.
class ChannelNames {
  const ChannelNames._();

  static const String automationMethods = 'com.jobfilter.app/automation';
  static const String automationEvents = 'com.jobfilter.app/automation_events';

  /// Fires when the driver taps STOP on the persistent foreground-service
  /// notification (spec section 25), so Dart can run the same emergency-stop
  /// path as the in-app STOP AUTOMATION button.
  static const String automationControlEvents = 'com.jobfilter.app/automation_control_events';
}
