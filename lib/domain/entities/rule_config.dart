import 'package:equatable/equatable.dart';

import '../../core/constants/app_constants.dart';

/// One threshold rule, independently enable-able (spec section 6/32).
/// [enabled] false means the rule is skipped entirely during evaluation
/// (treated as PASS), not evaluated-and-ignored.
class ThresholdRule extends Equatable {
  const ThresholdRule({required this.enabled, required this.value});

  final bool enabled;
  final double value;

  ThresholdRule copyWith({bool? enabled, double? value}) =>
      ThresholdRule(enabled: enabled ?? this.enabled, value: value ?? this.value);

  @override
  List<Object?> get props => [enabled, value];
}

/// A list of destination-postcode outward-code prefixes (e.g. "LE4", "LE5")
/// that always REJECT a job, regardless of every other rule (spec: driver
/// request — some areas are a hard no no matter how good the fare looks).
/// [enabled] false means skipped entirely, same as [ThresholdRule].
class PostcodeBlocklistConfig extends Equatable {
  const PostcodeBlocklistConfig({this.enabled = false, this.blockedPrefixes = const []});

  final bool enabled;

  /// Compared as a case-insensitive prefix against the destination's
  /// outward code — "LE4" blocks "LE4 1AB", "LE40 9ZZ", etc.
  final List<String> blockedPrefixes;

  PostcodeBlocklistConfig copyWith({bool? enabled, List<String>? blockedPrefixes}) =>
      PostcodeBlocklistConfig(
        enabled: enabled ?? this.enabled,
        blockedPrefixes: blockedPrefixes ?? this.blockedPrefixes,
      );

  @override
  List<Object?> get props => [enabled, blockedPrefixes];
}

/// The full set of configurable rules (spec section 6). Deliberately a plain
/// data holder — evaluation logic lives in domain/rules, not here, so new
/// rules can be added without widening this class's responsibilities.
class RuleConfig extends Equatable {
  const RuleConfig({
    this.minimumPoundsPerMile = const ThresholdRule(
      enabled: true,
      value: AppConstants.defaultMinimumPoundsPerMile,
    ),
    this.maximumPickupDistanceMiles = const ThresholdRule(enabled: false, value: 3.0),
    this.minimumFare = const ThresholdRule(enabled: false, value: 7.0),
    this.maximumTripDistanceMiles = const ThresholdRule(enabled: false, value: 15.0),
    this.minimumHourlyRate = const ThresholdRule(enabled: false, value: 20.0),
    this.postcodeBlocklist = const PostcodeBlocklistConfig(),
    this.counterOfferBandPercent = const ThresholdRule(
      enabled: false,
      value: AppConstants.defaultCounterOfferBandPercent,
    ),
  });

  /// Rule 1 — mandatory by default; the core "is this job worth it" check.
  final ThresholdRule minimumPoundsPerMile;

  /// Rule 2 — reject jobs whose pickup (deadhead) distance is too large.
  final ThresholdRule maximumPickupDistanceMiles;

  /// Rule 3 — reject jobs below a flat minimum fare regardless of distance.
  final ThresholdRule minimumFare;

  /// Rule 4 — reject unusually long trips if the driver doesn't want them.
  final ThresholdRule maximumTripDistanceMiles;

  /// Rule 5 — only evaluated when a reliable duration estimate is available.
  final ThresholdRule minimumHourlyRate;

  /// Rule 6 — reject any job going to a blocked destination area, regardless
  /// of £/mile or any other rule.
  final PostcodeBlocklistConfig postcodeBlocklist;

  /// Rule 7 (Bolt-only) — a job whose £/mile is at least this percentage of
  /// [minimumPoundsPerMile] (e.g. 85 means £1.70 of a £2.00 minimum)
  /// counter-offers via Bolt's own "Change price" flow (highest suggested
  /// amount) instead of being rejected outright. [enabled] false falls back
  /// to the normal reject, same as every other rule here.
  final ThresholdRule counterOfferBandPercent;

  RuleConfig copyWith({
    ThresholdRule? minimumPoundsPerMile,
    ThresholdRule? maximumPickupDistanceMiles,
    ThresholdRule? minimumFare,
    ThresholdRule? maximumTripDistanceMiles,
    ThresholdRule? minimumHourlyRate,
    PostcodeBlocklistConfig? postcodeBlocklist,
    ThresholdRule? counterOfferBandPercent,
  }) {
    return RuleConfig(
      minimumPoundsPerMile: minimumPoundsPerMile ?? this.minimumPoundsPerMile,
      maximumPickupDistanceMiles:
          maximumPickupDistanceMiles ?? this.maximumPickupDistanceMiles,
      minimumFare: minimumFare ?? this.minimumFare,
      maximumTripDistanceMiles: maximumTripDistanceMiles ?? this.maximumTripDistanceMiles,
      minimumHourlyRate: minimumHourlyRate ?? this.minimumHourlyRate,
      postcodeBlocklist: postcodeBlocklist ?? this.postcodeBlocklist,
      counterOfferBandPercent: counterOfferBandPercent ?? this.counterOfferBandPercent,
    );
  }

  @override
  List<Object?> get props => [
        minimumPoundsPerMile,
        maximumPickupDistanceMiles,
        minimumFare,
        maximumTripDistanceMiles,
        minimumHourlyRate,
        postcodeBlocklist,
        counterOfferBandPercent,
      ];
}
