import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../enums/distance_unit.dart';
import '../enums/platform_type.dart';
import 'rule_config.dart';

/// All driver-configurable state (spec sections 5, 6, 41). Persisted as a
/// single row in the settings table; every field has a safe default so a
/// fresh install behaves sensibly with zero configuration.
class DriverSettings extends Equatable {
  const DriverSettings({
    this.appName = 'JobFilter',
    this.automationEnabled = false,
    this.platformSelection = PlatformSelection.both,
    this.distanceUnit = DistanceUnit.miles,
    this.distanceCalculationMode = DistanceCalculationMode.tripDistance,
    this.themeMode = ThemeMode.system,
    this.rules = const RuleConfig(),
    this.platformOverrides = const {},
    this.currencyCode = 'GBP',
  });

  final String appName;
  final bool automationEnabled;
  final PlatformSelection platformSelection;
  final DistanceUnit distanceUnit;
  final DistanceCalculationMode distanceCalculationMode;

  /// How the app chooses light vs dark: follow the system, or force one.
  final ThemeMode themeMode;

  /// Global (default) rule thresholds.
  final RuleConfig rules;

  /// Per-platform overrides of [rules] (spec section 6, "Rule 6 —
  /// Platform-specific settings"). A platform absent from this map inherits
  /// [rules] unchanged.
  final Map<PlatformType, RuleConfig> platformOverrides;

  final String currencyCode;

  /// Resolve the effective rule set for a given platform, applying any override.
  RuleConfig rulesFor(PlatformType platform) => platformOverrides[platform] ?? rules;

  DriverSettings copyWith({
    String? appName,
    bool? automationEnabled,
    PlatformSelection? platformSelection,
    DistanceUnit? distanceUnit,
    DistanceCalculationMode? distanceCalculationMode,
    ThemeMode? themeMode,
    RuleConfig? rules,
    Map<PlatformType, RuleConfig>? platformOverrides,
    String? currencyCode,
  }) {
    return DriverSettings(
      appName: appName ?? this.appName,
      automationEnabled: automationEnabled ?? this.automationEnabled,
      platformSelection: platformSelection ?? this.platformSelection,
      distanceUnit: distanceUnit ?? this.distanceUnit,
      distanceCalculationMode: distanceCalculationMode ?? this.distanceCalculationMode,
      themeMode: themeMode ?? this.themeMode,
      rules: rules ?? this.rules,
      platformOverrides: platformOverrides ?? this.platformOverrides,
      currencyCode: currencyCode ?? this.currencyCode,
    );
  }

  @override
  List<Object?> get props => [
        appName,
        automationEnabled,
        platformSelection,
        distanceUnit,
        distanceCalculationMode,
        themeMode,
        rules,
        platformOverrides,
        currencyCode,
      ];
}
