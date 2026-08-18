import '../../domain/entities/taxi_job.dart';
import '../../domain/enums/job_decision.dart';
import '../../domain/enums/platform_type.dart';

/// SQLite row <-> [TaxiJob] mapping, kept out of the domain entity so the
/// domain layer has zero knowledge of how (or whether) it's persisted.
class TaxiJobMapper {
  const TaxiJobMapper._();

  static Map<String, Object?> toRow(TaxiJob job) {
    return {
      'id': job.id,
      'platform': job.platform.name,
      'fare': job.fare,
      'trip_distance_miles': job.tripDistanceMiles,
      'pickup_distance_miles': job.pickupDistanceMiles,
      'estimated_duration_minutes': job.estimatedDurationMinutes,
      'pickup_address': job.pickupAddress,
      'destination_address': job.destinationAddress,
      'destination_postcode': job.destinationPostcode,
      'detected_at': job.detectedAt.toIso8601String(),
      'decision': job.decision.name,
      'pounds_per_mile': job.poundsPerMile,
      'estimated_hourly_rate': job.estimatedHourlyRate,
      // Column name predates this field covering every decision, not just
      // rejections — kept as-is to avoid a schema migration for a rename.
      'rejection_reason': job.decisionReason,
      'raw_detected_text': job.rawDetectedText,
      'fingerprint': job.fingerprint,
      'is_simulated': job.isSimulated ? 1 : 0,
    };
  }

  static TaxiJob fromRow(Map<String, Object?> row) {
    return TaxiJob(
      id: row['id'] as String,
      platform: PlatformType.values.byName(row['platform'] as String),
      fare: (row['fare'] as num?)?.toDouble(),
      tripDistanceMiles: (row['trip_distance_miles'] as num?)?.toDouble(),
      pickupDistanceMiles: (row['pickup_distance_miles'] as num?)?.toDouble(),
      estimatedDurationMinutes: row['estimated_duration_minutes'] as int?,
      pickupAddress: row['pickup_address'] as String?,
      destinationAddress: row['destination_address'] as String?,
      destinationPostcode: row['destination_postcode'] as String?,
      detectedAt: DateTime.parse(row['detected_at'] as String),
      decision: JobDecision.values.byName(row['decision'] as String),
      poundsPerMile: (row['pounds_per_mile'] as num?)?.toDouble(),
      estimatedHourlyRate: (row['estimated_hourly_rate'] as num?)?.toDouble(),
      decisionReason: row['rejection_reason'] as String?,
      rawDetectedText: row['raw_detected_text'] as String?,
      fingerprint: row['fingerprint'] as String?,
      isSimulated: (row['is_simulated'] as int?) == 1,
    );
  }
}
