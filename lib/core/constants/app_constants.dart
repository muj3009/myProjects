/// Central, non-secret configuration constants.
///
/// Thresholds that a driver can change live in [DriverSettings] / the database,
/// not here. This file only holds values that are truly fixed at build time.
class AppConstants {
  const AppConstants._();

  /// Display name shown throughout the UI. Kept separate from the package/bundle
  /// identifiers so the product can be renamed without touching store listings.
  static const String appName = 'JobFilter';

  /// Kilometres-to-miles conversion factor used across the app. Distances are
  /// normalized to miles internally regardless of the driver's display preference.
  static const double kmToMiles = 0.621371;

  /// How long a job fingerprint is remembered to suppress duplicate processing
  /// when the driver-app UI refreshes the same job.
  static const Duration fingerprintRetention = Duration(minutes: 5);

  /// Sensible bounds for the £/mile and fare settings, used for input validation.
  static const double minAllowedPoundsPerMile = 0.01;
  static const double maxAllowedPoundsPerMile = 50.0;
  static const double minAllowedFare = 0.0;
  static const double maxAllowedFare = 500.0;
  static const double minAllowedDistance = 0.1;
  static const double maxAllowedDistance = 200.0;

  /// Default driver-facing minimum £/mile, matching the product spec's example.
  static const double defaultMinimumPoundsPerMile = 2.00;

  /// Default value for [RuleConfig.counterOfferBandPercent] — driver-editable
  /// in the Rules screen, matching the product spec's own 85% example.
  static const double defaultCounterOfferBandPercent = 85.0;

  /// Default value for [RuleConfig.lowFareCounterOfferThreshold] — driver
  /// request: a Bolt job below this fare is so cheap that it's always worth
  /// trying for more rather than rejecting outright, so it gets the maximum
  /// counter-offer instead.
  static const double defaultLowFareCounterOfferThreshold = 4.0;

  /// Defaults for [RuleConfig.highValueJob] — driver request: a £15+ job at
  /// £1.60+/mile is accepted immediately, bypassing every other rule except
  /// the postcode blocklist; a £15+ job between £1.30/mile and £1.60/mile
  /// gets a counter-offer instead of a reject; below £1.30/mile, this
  /// override does nothing and normal rules apply.
  static const double defaultHighValueJobFareFloor = 15.0;
  static const double defaultHighValueJobAcceptRateFloor = 1.60;
  static const double defaultHighValueJobCounterOfferRateFloor = 1.30;

  /// Default value for [RuleConfig.quietTimeMinimumPoundsPerMile] — driver
  /// request: during quiet periods, relax the effective minimum £/mile down
  /// to this value (never up) rather than the driver's normal minimum.
  static const double defaultQuietTimeMinimumPoundsPerMile = 1.60;

  /// "Busy time" definition (driver-confirmed numbers, not currently
  /// driver-editable): this many or more jobs detected within
  /// [busyTimeWindow] counts as busy — see JobDecisionEngine's isBusyTime
  /// parameter and AutomationController's busy-time detection.
  static const int busyTimeJobThreshold = 8;
  static const Duration busyTimeWindow = Duration(minutes: 5);
}
