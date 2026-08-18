import 'package:flutter_test/flutter_test.dart';
import 'package:jobfilter/domain/entities/taxi_job.dart';
import 'package:jobfilter/domain/enums/job_decision.dart';
import 'package:jobfilter/domain/enums/platform_type.dart';
import 'package:jobfilter/domain/services/job_fingerprint_service.dart';

TaxiJob _job({String id = 'a'}) {
  return TaxiJob(
    id: id,
    platform: PlatformType.uber,
    detectedAt: DateTime.now(),
    decision: JobDecision.pending,
    fare: 12.50,
    tripDistanceMiles: 5.2,
    pickupDistanceMiles: 1.0,
    pickupAddress: '10 High Street',
    destinationAddress: '20 Station Road',
  );
}

void main() {
  test('the same job produces the same fingerprint regardless of detection time', () {
    final fp1 = JobFingerprintService.buildFingerprint(_job(id: 'a'));
    final fp2 = JobFingerprintService.buildFingerprint(_job(id: 'b'));
    expect(fp1, fp2);
  });

  test('a materially different job produces a different fingerprint', () {
    final base = JobFingerprintService.buildFingerprint(_job());
    final different = JobFingerprintService.buildFingerprint(
      _job().copyWith(fare: 15.00),
    );
    expect(base, isNot(different));
  });

  test('duplicate detection: the same job is only flagged after being recorded once', () {
    final service = JobFingerprintService();
    final fingerprint = JobFingerprintService.buildFingerprint(_job());

    expect(service.isDuplicate(fingerprint), isFalse);
    service.record(fingerprint);
    expect(service.isDuplicate(fingerprint), isTrue);
  });

  test('fingerprints expire after the retention window', () async {
    final service = JobFingerprintService(retention: const Duration(milliseconds: 20));
    final fingerprint = JobFingerprintService.buildFingerprint(_job());

    service.record(fingerprint);
    expect(service.isDuplicate(fingerprint), isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(service.isDuplicate(fingerprint), isFalse);
  });
}
