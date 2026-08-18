import 'package:equatable/equatable.dart';

/// Raw extraction result from a [JobParser], before any decision-making.
/// Every field is nullable — a parser reports what it actually found and
/// nothing more (spec section 8: "If fare cannot be reliably detected, DO
/// NOT guess"). [AutomationController] combines this with a platform, id, and
/// timestamp to build a full [TaxiJob].
class ParsedJobData extends Equatable {
  const ParsedJobData({
    this.fare,
    this.tripDistanceMiles,
    this.pickupDistanceMiles,
    this.estimatedDurationMinutes,
    this.pickupAddress,
    this.destinationAddress,
    this.destinationPostcode,
    this.displayedPoundsPerMile,
    required this.rawText,
    required this.jobCardDetected,
  });

  final double? fare;
  final double? tripDistanceMiles;
  final double? pickupDistanceMiles;
  final int? estimatedDurationMinutes;
  final String? pickupAddress;
  final String? destinationAddress;

  /// Outward code only (e.g. "LE4") — see PostcodeBlocklistRule, the only
  /// thing that reads this.
  final String? destinationPostcode;

  /// Bolt shows its own computed £/mile directly on the card (e.g. "£1.03/mi
  /// (NET, tax included)") — a real device proved this uses *total* driving
  /// distance (pickup + trip), not trip-only, which disagreed sharply with
  /// this app's own trip-only computation for the same job (£1.03 vs £1.94).
  /// When present, this is the platform's own authoritative figure and
  /// should be preferred over re-deriving one from fare/distance, which adds
  /// avoidable risk (wrong distance basis, pickup/trip mix-ups) on top of a
  /// number the app already has directly. Null on platforms that don't
  /// display this (Uber never has, in every sample this session).
  final double? displayedPoundsPerMile;

  /// The exact text the parser worked from, retained for the debug screen only.
  final String rawText;

  /// Whether the parser believes a job offer card is actually present in
  /// [rawText] at all (as opposed to, say, the driver's home/map screen).
  /// Distinct from whether fields were successfully extracted — a job card
  /// can be detected with fare/distance still unknown.
  final bool jobCardDetected;

  bool get hasReliableFinancials => fare != null && tripDistanceMiles != null;

  @override
  List<Object?> get props => [
        fare,
        tripDistanceMiles,
        pickupDistanceMiles,
        estimatedDurationMinutes,
        pickupAddress,
        destinationAddress,
        destinationPostcode,
        displayedPoundsPerMile,
        jobCardDetected,
      ];
}
