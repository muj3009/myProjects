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
}
