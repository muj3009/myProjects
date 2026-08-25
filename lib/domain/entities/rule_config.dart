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

/// "High-value job" override (spec: driver request) — at or above [fareFloor],
/// a job that also clears [acceptRateFloor] £/mile is accepted immediately,
/// bypassing every other threshold rule (pickup distance, trip distance,
/// minimum fare, hourly rate) — but never the postcode blocklist, which the
/// driver confirmed must still always apply regardless of fare. Still at/above
/// [fareFloor] but below [acceptRateFloor], a Bolt job gets a counter-offer
/// instead of a reject as long as its rate is at/above [counterOfferRateFloor]
/// — below that, this override does nothing and normal rules apply.
class HighValueJobOverride extends Equatable {
  const HighValueJobOverride({
    this.enabled = false,
    this.fareFloor = AppConstants.defaultHighValueJobFareFloor,
    this.acceptRateFloor = AppConstants.defaultHighValueJobAcceptRateFloor,
    this.counterOfferRateFloor = AppConstants.defaultHighValueJobCounterOfferRateFloor,
  });

  final bool enabled;
  final double fareFloor;
  final double acceptRateFloor;
  final double counterOfferRateFloor;

  HighValueJobOverride copyWith({
    bool? enabled,
    double? fareFloor,
    double? acceptRateFloor,
    double? counterOfferRateFloor,
  }) =>
      HighValueJobOverride(
        enabled: enabled ?? this.enabled,
        fareFloor: fareFloor ?? this.fareFloor,
        acceptRateFloor: acceptRateFloor ?? this.acceptRateFloor,
        counterOfferRateFloor: counterOfferRateFloor ?? this.counterOfferRateFloor,
      );

  @override
  List<Object?> get props => [enabled, fareFloor, acceptRateFloor, counterOfferRateFloor];
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
    this.lowFareCounterOfferThreshold = const ThresholdRule(
      enabled: false,
      value: AppConstants.defaultLowFareCounterOfferThreshold,
    ),
    this.highValueJob = const HighValueJobOverride(),
    this.quietTimeMinimumPoundsPerMile = const ThresholdRule(
      enabled: false,
      value: AppConstants.defaultQuietTimeMinimumPoundsPerMile,
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

  /// Rule 8 (Bolt-only) — a job whose total fare is BELOW this amount is so
  /// low that it's always worth an automatic maximum counter-offer rather
  /// than an outright reject when it only fails on £/mile, regardless of how
  /// far under the driver's minimum rate it is. Independent of
  /// [counterOfferBandPercent] — either one qualifying is enough to trigger
  /// a counter-offer.
  final ThresholdRule lowFareCounterOfferThreshold;

  /// Rule 9 — see [HighValueJobOverride].
  final HighValueJobOverride highValueJob;

  /// Rule 10 — during quiet periods (8+ jobs detected in the last 5 minutes
  /// counts as busy — see JobDecisionEngine.evaluate's isBusyTime parameter),
  /// relax the effective minimum £/mile down to this value if it's lower
  /// than [minimumPoundsPerMile] — never up. During busy periods,
  /// [minimumPoundsPerMile] applies completely unchanged.
  final ThresholdRule quietTimeMinimumPoundsPerMile;

  RuleConfig copyWith({
    ThresholdRule? minimumPoundsPerMile,
    ThresholdRule? maximumPickupDistanceMiles,
    ThresholdRule? minimumFare,
    ThresholdRule? maximumTripDistanceMiles,
    ThresholdRule? minimumHourlyRate,
    PostcodeBlocklistConfig? postcodeBlocklist,
    ThresholdRule? counterOfferBandPercent,
    ThresholdRule? lowFareCounterOfferThreshold,
    HighValueJobOverride? highValueJob,
    ThresholdRule? quietTimeMinimumPoundsPerMile,
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
      lowFareCounterOfferThreshold:
          lowFareCounterOfferThreshold ?? this.lowFareCounterOfferThreshold,
      highValueJob: highValueJob ?? this.highValueJob,
      quietTimeMinimumPoundsPerMile:
          quietTimeMinimumPoundsPerMile ?? this.quietTimeMinimumPoundsPerMile,
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
        lowFareCounterOfferThreshold,
        highValueJob,
        quietTimeMinimumPoundsPerMile,
      ];
}
