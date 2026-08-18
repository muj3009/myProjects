import 'dart:io';

import '../accessibility/accessibility_status.dart';
import '../automation/automation_method_channel.dart';

/// One permission/setup item shown on the guided Permissions screen (spec
/// section 24). Every entry explains *why* it's needed — this app never
/// requests a permission without the driver seeing that explanation first,
/// and never attempts to silently toggle a setting.
class PermissionItem {
  const PermissionItem({
    required this.id,
    required this.title,
    required this.explanation,
    required this.isGranted,
    required this.isRequired,
  });

  final String id;
  final String title;
  final String explanation;
  final bool isGranted;
  final bool isRequired;
}

/// Aggregates the Android-specific setup state the automation flow depends
/// on. Not used on iOS — the iOS Permissions/Settings screen has nothing to
/// check here since it performs no cross-app automation (spec section 26).
class PermissionStatusService {
  PermissionStatusService({AutomationMethodChannel? channel})
      : _channel = channel ?? AutomationMethodChannel();

  final AutomationMethodChannel _channel;

  Future<List<PermissionItem>> loadAndroidPermissionItems() async {
    if (!Platform.isAndroid) return const [];

    final accessibility = await _channel.getAccessibilityStatus();
    final batteryOk = await _channel.isBatteryOptimizationIgnored();
    final notificationListenerOk = await _channel.isNotificationListenerEnabled();
    final overlayOk = await _channel.isOverlayPermissionGranted();

    return [
      PermissionItem(
        id: 'accessibility_service',
        title: 'Accessibility access',
        explanation:
            'JobFilter needs this permission to detect job information shown '
            'in supported driver applications.',
        isGranted: accessibility == AccessibilityStatus.enabled,
        isRequired: true,
      ),
      PermissionItem(
        id: 'notification_listener',
        title: 'Notification access',
        explanation:
            "Lets JobFilter bring Bolt's job-offer screen on screen the "
            'instant a job arrives while Bolt is in the background — without '
            'this, background jobs are only shown as a quiet notification '
            'with no fare details JobFilter can read.',
        isGranted: notificationListenerOk,
        isRequired: true,
      ),
      PermissionItem(
        id: 'overlay_permission',
        title: 'Display over other apps',
        explanation:
            "Required by Android for JobFilter to bring Bolt's job screen up "
            'automatically while Bolt is in the background — without it, '
            'Android silently blocks that and background jobs go unhandled.',
        isGranted: overlayOk,
        isRequired: true,
      ),
      PermissionItem(
        id: 'battery_optimization',
        title: 'Unrestricted battery usage',
        explanation:
            'Prevents Android from pausing job monitoring in the background. '
            'Without this, automation may stop while your screen is off.',
        isGranted: batteryOk,
        isRequired: false,
      ),
    ];
  }
}
