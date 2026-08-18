import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/constants/app_constants.dart';
import '../entities/taxi_job.dart';

/// Deduplicates jobs that reappear because the driver-app UI redraws/refreshes
/// the same offer (spec sections 15/18). A fingerprint intentionally excludes
/// the detection timestamp — two sightings of the *same* job a few seconds
/// apart must hash identically so they're recognised as duplicates.
class JobFingerprintService {
  JobFingerprintService({Duration? retention})
      : _retention = retention ?? AppConstants.fingerprintRetention;

  final Duration _retention;
  final Map<String, DateTime> _recentFingerprints = {};

  /// Builds a stable hash from the fields that identify a job, per spec
  /// section 18: `platform + fare + pickup + destination`.
  ///
  /// Deliberately excludes distance — a real device showed the exact same
  /// job re-read 2-3 times in the space of ~150ms during a multi-job burst
  /// getting treated as 2-3 *different* jobs (each one fully evaluated and
  /// actioned again), because [tripDistanceMiles]/[pickupDistanceMiles] are
  /// live, GPS-derived figures that can shift by a hundredth of a mile
  /// between reads of a job that hasn't actually changed at all, flipping
  /// the rounded value and producing a different hash. The pickup/
  /// destination addresses and fare are set once when Bolt creates the
  /// offer and never change for its lifetime, so they're a strictly more
  /// reliable identity on their own than adding a field that can silently
  /// drift.
  static String buildFingerprint(TaxiJob job) {
    final raw = [
      job.platform.name,
      job.fare?.toStringAsFixed(2) ?? '?',
      job.pickupAddress?.trim().toLowerCase() ?? '?',
      job.destinationAddress?.trim().toLowerCase() ?? '?',
    ].join('|');
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// Returns true if this fingerprint was already seen within the retention
  /// window. Does NOT record it — call [record] once processing actually
  /// proceeds, so a job that was skipped for other reasons can still be
  /// re-evaluated on its next sighting.
  bool isDuplicate(String fingerprint) {
    _evictExpired();
    return _recentFingerprints.containsKey(fingerprint);
  }

  void record(String fingerprint) {
    _evictExpired();
    _recentFingerprints[fingerprint] = DateTime.now();
  }

  void _evictExpired() {
    final cutoff = DateTime.now().subtract(_retention);
    _recentFingerprints.removeWhere((_, seenAt) => seenAt.isBefore(cutoff));
  }

  void clear() => _recentFingerprints.clear();
}
