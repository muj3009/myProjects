import 'dart:convert';

import 'package:flutter/material.dart';

import '../../domain/entities/driver_settings.dart';
import '../../domain/entities/rule_config.dart';
import '../../domain/enums/distance_unit.dart';
import '../../domain/enums/platform_type.dart';

/// SQLite row <-> [DriverSettings] mapping. Rule thresholds and per-platform
/// overrides are stored as JSON text so new rule fields don't require a
/// schema migration for every addition (spec section 41).
class DriverSettingsMapper {
  const DriverSettingsMapper._();

  static const int singletonRowId = 0;

  static Map<String, Object?> toRow(DriverSettings settings) {
    return {
      'id': singletonRowId,
      'app_name': settings.appName,
      'automation_enabled': settings.automationEnabled ? 1 : 0,
      'platform_selection': settings.platformSelection.name,
      'distance_unit': settings.distanceUnit.name,
      'distance_calculation_mode': settings.distanceCalculationMode.name,
      'theme_mode': settings.themeMode.name,
      'currency_code': settings.currencyCode,
      'rules_json': jsonEncode(_ruleConfigToJson(settings.rules)),
      'platform_overrides_json': jsonEncode({
        for (final entry in settings.platformOverrides.entries)
          entry.key.name: _ruleConfigToJson(entry.value),
      }),
    };
  }

  static DriverSettings fromRow(Map<String, Object?> row) {
    final overridesRaw = jsonDecode(row['platform_overrides_json'] as String) as Map<String, dynamic>;    return DriverSettings(
      appName: row['app_name'] as String,
      automationEnabled: (row['automation_enabled'] as int) == 1,
      platformSelection: PlatformSelection.values.byName(row['platform_selection'] as String),      distanceUnit: DistanceUnit.values.byName(row['distance_unit'] as String),
      distanceCalculationMode:
          DistanceCalculationMode.values.byName(row['distance_calculation_mode'] as String),
      themeMode: _themeModeFromRow(row['theme_mode']),
      currencyCode: row['currency_code'] as String,
      rules: _ruleConfigFromJson(jsonDecode(row['rules_json'] as String) as Map<String, dynamic>),
      platformOverrides: {
        for (final entry in overridesRaw.entries)
          PlatformType.values.byName(entry.key): _ruleConfigFromJson(entry.value as Map<String, dynamic>),
      },
    );
  }

  /// Safely resolves the persisted [ThemeMode] stored as its `.name` string
  /// (e.g. "system", "light", "dark"). Falls back to [ThemeMode.system] if
  /// the column is absent/null or holds an unknown value — defensive for any
  /// row written by an app version before the theme setting existed.
  static ThemeMode _themeModeFromRow(Object? raw) {
    if (raw is! String) return ThemeMode.system;
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => ThemeMode.system,
    );
  }

  static Map<String, dynamic> _ruleConfigToJson(RuleConfig config) => {
        'minimumPoundsPerMile': _thresholdToJson(config.minimumPoundsPerMile),
        'maximumPickupDistanceMiles': _thresholdToJson(config.maximumPickupDistanceMiles),
        'minimumFare': _thresholdToJson(config.minimumFare),
        'maximumTripDistanceMiles': _thresholdToJson(config.maximumTripDistanceMiles),
        'minimumHourlyRate': _thresholdToJson(config.minimumHourlyRate),
        'postcodeBlocklist': _postcodeBlocklistToJson(config.postcodeBlocklist),
        'counterOfferBandPercent': _thresholdToJson(config.counterOfferBandPercent),
        'lowFareCounterOfferThreshold':
            _thresholdToJson(config.lowFareCounterOfferThreshold),
        'highValueJob': _highValueJobToJson(config.highValueJob),
        'quietTimeMinimumPoundsPerMile': _thresholdToJson(config.quietTimeMinimumPoundsPerMile),
      };

  static RuleConfig _ruleConfigFromJson(Map<String, dynamic> json) {
    const defaults = RuleConfig();
    return RuleConfig(
      minimumPoundsPerMile:
          _thresholdFromJson(json['minimumPoundsPerMile'], defaults.minimumPoundsPerMile),
      maximumPickupDistanceMiles: _thresholdFromJson(
          json['maximumPickupDistanceMiles'], defaults.maximumPickupDistanceMiles),
      minimumFare: _thresholdFromJson(json['minimumFare'], defaults.minimumFare),
      maximumTripDistanceMiles: _thresholdFromJson(
          json['maximumTripDistanceMiles'], defaults.maximumTripDistanceMiles),
      minimumHourlyRate:
          _thresholdFromJson(json['minimumHourlyRate'], defaults.minimumHourlyRate),
      postcodeBlocklist:
          _postcodeBlocklistFromJson(json['postcodeBlocklist'], defaults.postcodeBlocklist),
      counterOfferBandPercent: _thresholdFromJson(
          json['counterOfferBandPercent'], defaults.counterOfferBandPercent),
      lowFareCounterOfferThreshold: _thresholdFromJson(
          json['lowFareCounterOfferThreshold'], defaults.lowFareCounterOfferThreshold),
      highValueJob: _highValueJobFromJson(json['highValueJob'], defaults.highValueJob),
      quietTimeMinimumPoundsPerMile: _thresholdFromJson(
          json['quietTimeMinimumPoundsPerMile'], defaults.quietTimeMinimumPoundsPerMile),
    );
  }

  static Map<String, dynamic> _highValueJobToJson(HighValueJobOverride override) => {
        'enabled': override.enabled,
        'fareFloor': override.fareFloor,
        'acceptRateFloor': override.acceptRateFloor,
        'counterOfferRateFloor': override.counterOfferRateFloor,
      };

  static HighValueJobOverride _highValueJobFromJson(
    dynamic json,
    HighValueJobOverride fallback,
  ) {
    if (json == null) return fallback;
    final map = json as Map<String, dynamic>;
    return HighValueJobOverride(
      enabled: map['enabled'] as bool? ?? fallback.enabled,
      fareFloor: (map['fareFloor'] as num?)?.toDouble() ?? fallback.fareFloor,
      acceptRateFloor: (map['acceptRateFloor'] as num?)?.toDouble() ?? fallback.acceptRateFloor,
      counterOfferRateFloor:
          (map['counterOfferRateFloor'] as num?)?.toDouble() ?? fallback.counterOfferRateFloor,
    );
  }

  static Map<String, dynamic> _thresholdToJson(ThresholdRule rule) =>
      {'enabled': rule.enabled, 'value': rule.value};

  static ThresholdRule _thresholdFromJson(dynamic json, ThresholdRule fallback) {
    if (json == null) return fallback;
    final map = json as Map<String, dynamic>;
    return ThresholdRule(
      enabled: map['enabled'] as bool? ?? fallback.enabled,
      value: (map['value'] as num?)?.toDouble() ?? fallback.value,
    );
  }

  static Map<String, dynamic> _postcodeBlocklistToJson(PostcodeBlocklistConfig config) =>
      {'enabled': config.enabled, 'blockedPrefixes': config.blockedPrefixes};

  static PostcodeBlocklistConfig _postcodeBlocklistFromJson(
    dynamic json,
    PostcodeBlocklistConfig fallback,
  ) {
    if (json == null) return fallback;
    final map = json as Map<String, dynamic>;
    return PostcodeBlocklistConfig(
      enabled: map['enabled'] as bool? ?? fallback.enabled,
      blockedPrefixes:
          (map['blockedPrefixes'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              fallback.blockedPrefixes,
    );
  }
}
