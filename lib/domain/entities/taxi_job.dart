import 'package:equatable/equatable.dart';

import '../enums/job_decision.dart';
import '../enums/platform_type.dart';

/// A single detected (or manually entered, in Simulation Mode) job.
///
/// Every numeric field is nullable on purpose: the parser must never invent a
/// value it did not actually read (spec section 8 — "If fare cannot be
/// reliably detected, DO NOT guess"). Downstream code (the decision engine)
/// is responsible for treating a null as UNKNOWN, not as zero.
class TaxiJob extends Equatable {
  const TaxiJob({
    required this.id,
    required this.platform,
    required this.detectedAt,
    required this.decision,
    this.fare,
    this.tripDistanceMiles,
    this.pickupDistanceMiles,
    this.estimatedDurationMinutes,
    this.pickupAddress,
    this.destinationAddress,
    this.destinationPostcode,
    this.displayedPoundsPerMile,
    this.poundsPerMile,
    this.estimatedHourlyRate,
    this.decisionReason,
    this.rawDetectedText,
    this.fingerprint,
    this.isSimulated = false,
  });

  final String id;
  final PlatformType platform;

  final double? fare;
  final double? tripDistanceMiles;
  final double? pickupDistanceMiles;
  final int? estimatedDurationMinutes;

  /// The platform's own displayed £/mile, when it shows one directly (Bolt
  /// does; Uber never has, in every sample this session) — see
  /// [ParsedJobData.displayedPoundsPerMile] for why this is preferred over
  /// [poundsPerMile] (this app's own fare/distance-derived figure) when
  /// available.
  final double? displayedPoundsPerMile;

  final String? pickupAddress;
  final String? destinationAddress;

  /// Outward code only (e.g. "LE4" from "LE4 1AB") — see
  /// [PostcodeBlocklistRule], the only thing that reads this.
  final String? destinationPostcode;

  final DateTime detectedAt;

  final JobDecision decision;

  final double? poundsPerMile;
  final double? estimatedHourlyRate;

  /// Plain-English explanation of why this decision was reached — set for
  /// every outcome (accepted, rejected, counter-offered, pending), not just
  /// rejections, so the Job History screen can always tell the driver why.
  final String? decisionReason;

  /// Raw text the job was parsed from. Retained only for the on-device debug
  /// screen (spec section 34) — never transmitted off-device.
  final String? rawDetectedText;

  /// Deduplication key produced by JobFingerprintService. Nullable because
  /// simulated jobs (Simulation Mode) are never deduplicated.
  final String? fingerprint;

  /// True when this job came from the Simulation/Test screen rather than
  /// live detection, so it can be excluded from real statistics if desired.
  final bool isSimulated;

  /// Total distance actually driven for this job (pickup + trip), used by the
  /// "total driving distance" £/mile mode. Null if pickup distance is unknown.
  double? get totalDrivingDistanceMiles {
    if (tripDistanceMiles == null) return null;
    if (pickupDistanceMiles == null) return tripDistanceMiles;
    return tripDistanceMiles! + pickupDistanceMiles!;
  }

  TaxiJob copyWith({
    String? id,
    PlatformType? platform,
    double? fare,
    double? tripDistanceMiles,
    double? pickupDistanceMiles,
    int? estimatedDurationMinutes,
    String? pickupAddress,
    String? destinationAddress,
    String? destinationPostcode,
    double? displayedPoundsPerMile,
    DateTime? detectedAt,
    JobDecision? decision,
    double? poundsPerMile,
    double? estimatedHourlyRate,
    String? decisionReason,
    String? rawDetectedText,
    String? fingerprint,
    bool? isSimulated,
  }) {
    return TaxiJob(
      id: id ?? this.id,
      platform: platform ?? this.platform,
      fare: fare ?? this.fare,
      tripDistanceMiles: tripDistanceMiles ?? this.tripDistanceMiles,
      pickupDistanceMiles: pickupDistanceMiles ?? this.pickupDistanceMiles,
      estimatedDurationMinutes: estimatedDurationMinutes ?? this.estimatedDurationMinutes,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      destinationPostcode: destinationPostcode ?? this.destinationPostcode,
      displayedPoundsPerMile: displayedPoundsPerMile ?? this.displayedPoundsPerMile,
      detectedAt: detectedAt ?? this.detectedAt,
      decision: decision ?? this.decision,
      poundsPerMile: poundsPerMile ?? this.poundsPerMile,
      estimatedHourlyRate: estimatedHourlyRate ?? this.estimatedHourlyRate,
      decisionReason: decisionReason ?? this.decisionReason,
      rawDetectedText: rawDetectedText ?? this.rawDetectedText,
      fingerprint: fingerprint ?? this.fingerprint,
      isSimulated: isSimulated ?? this.isSimulated,
    );
  }

  @override
  List<Object?> get props => [
        id,
        platform,
        fare,
        tripDistanceMiles,
        pickupDistanceMiles,
        estimatedDurationMinutes,
        pickupAddress,
        destinationAddress,
        destinationPostcode,
        displayedPoundsPerMile,
        detectedAt,
        decision,
        poundsPerMile,
        estimatedHourlyRate,
        decisionReason,
        fingerprint,
        isSimulated,
      ];
}
