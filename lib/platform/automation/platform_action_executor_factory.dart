import 'dart:io';

import 'android_platform_action_executor.dart';
import 'ios_automation_provider.dart';
import 'platform_action_executor.dart';

/// Chooses the correct [PlatformActionExecutor] for the running OS. This is
/// the single place `Platform.isAndroid`/`Platform.isIOS` is checked for
/// automation purposes — everything downstream just uses the interface (spec
/// section 2's layering + section 26's "clearly separate Android automation
/// code from iOS functionality").
class PlatformActionExecutorFactory {
  const PlatformActionExecutorFactory._();

  static PlatformActionExecutor create() {
    if (Platform.isAndroid) {
      return AndroidPlatformActionExecutor();
    }
    if (Platform.isIOS) {
      return const IosAutomationProvider();
    }
    return const UnsupportedPlatformActionExecutor(
      'Automation is only available on Android and iOS builds',
    );
  }
}
