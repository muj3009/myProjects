import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/state/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../platform/permissions/permission_status_service.dart';
import '../../widgets/section_card.dart';

/// Guided permission setup (spec section 24). Every item explains why it's
/// needed before the driver is sent to system settings — nothing is enabled
/// silently, and this screen never itself flips an OS permission.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen>
    with WidgetsBindingObserver {
  List<PermissionItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final service = ref.read(permissionStatusServiceProvider);
    final items = await service.loadAndroidPermissionItems();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return Scaffold(
        appBar: AppBar(title: const Text('Permissions & setup')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'JobFilter does not require any special permissions on iPhone. '
              'Automatic cross-app job detection is an Android-only capability '
              'due to iOS platform restrictions — see Simulation Mode for manual '
              'job analysis on iPhone.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final channel = ref.read(automationMethodChannelProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Permissions & setup')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final item in _items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: (item.isGranted
                                            ? StatusColors.accepted
                                            : StatusColors.pendingOrUnknown)
                                        .withValues(alpha: 0.14),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    item.isGranted
                                        ? Icons.check_circle
                                        : Icons.priority_high_rounded,
                                    color: item.isGranted
                                        ? StatusColors.accepted
                                        : StatusColors.pendingOrUnknown,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.explanation,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                            ),
                            if (!item.isGranted) ...[
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: () async {
                                  if (item.id == 'accessibility_service') {
                                    await channel.openAccessibilitySettings();
                                  } else if (item.id ==
                                      'battery_optimization') {
                                    await channel
                                        .requestIgnoreBatteryOptimizations();
                                  } else if (item.id ==
                                      'notification_listener') {
                                    await channel
                                        .openNotificationListenerSettings();
                                  } else if (item.id == 'overlay_permission') {
                                    await channel
                                        .openOverlayPermissionSettings();
                                  }
                                },
                                child: const Text('Open Android Settings'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
