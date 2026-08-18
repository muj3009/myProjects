import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_logger.dart';
import '../../domain/entities/driver_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import 'providers.dart';

/// Holds the single source of truth for [DriverSettings]. Every settings
/// screen mutates state through this controller, which persists the change
/// immediately — the acceptance criterion "Changing £2.00 -> £2.50 must
/// immediately affect future decisions" holds because AutomationController
/// re-reads this provider's current value on every job, never a cached copy.
class SettingsController extends StateNotifier<DriverSettings> {
  SettingsController(this._repository) : super(const DriverSettings()) {
    unawaited(_load());
  }

  final SettingsRepository _repository;
  static const _tag = 'SettingsController';
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> _load() async {
    final result = await _repository.load();
    result.when(
      ok: (settings) => state = settings,
      err: (f) => AppLogger.instance.warning(_tag, 'Using defaults: $f'),
    );
    _loaded = true;
  }

  Future<void> update(DriverSettings Function(DriverSettings current) transform) async {
    final next = transform(state);
    state = next;
    final result = await _repository.save(next);
    result.when(
      ok: (_) => AppLogger.instance.info(_tag, 'Settings saved'),
      err: (f) => AppLogger.instance.error(_tag, 'Failed to persist settings: $f'),
    );
  }

  Future<void> setAutomationEnabled(bool enabled) =>
      update((s) => s.copyWith(automationEnabled: enabled));
}

final settingsControllerProvider = StateNotifierProvider<SettingsController, DriverSettings>((ref) {
  return SettingsController(ref.watch(settingsRepositoryProvider));
});
