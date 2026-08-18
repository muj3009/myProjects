import 'package:flutter_test/flutter_test.dart';
import 'package:jobfilter/domain/entities/driver_settings.dart';
import 'package:jobfilter/domain/entities/rule_config.dart';
import 'package:jobfilter/domain/entities/taxi_job.dart';
import 'package:jobfilter/domain/enums/job_decision.dart';
import 'package:jobfilter/domain/enums/platform_type.dart';
import 'package:jobfilter/domain/services/job_decision_engine.dart';

TaxiJob _job({
  double? fare,
  double? tripDistanceMiles,
  double? pickupDistanceMiles,
  int? estimatedDurationMinutes,
  PlatformType platform = PlatformType.uber,
}) {
  return TaxiJob(
    id: 'test-job',
    platform: platform,
    detectedAt: DateTime(2026, 1, 1),
    decision: JobDecision.pending,
    fare: fare,
    tripDistanceMiles: tripDistanceMiles,
    pickupDistanceMiles: pickupDistanceMiles,
    estimatedDurationMinutes: estimatedDurationMinutes,
  );
}

void main() {
  final engine = JobDecisionEngine();

  group('minimum £/mile rule (spec section 10/37)', () {
    test('£10 / 5 miles = £2.00/mile accepts at a £2.00 minimum', () {
      final settings = const DriverSettings();
      final outcome = engine.evaluate(_job(fare: 10, tripDistanceMiles: 5), settings);
      expect(outcome.poundsPerMile, 2.00);
      expect(outcome.decision, JobDecision.accepted);
    });

    test('£9 / 5 miles = £1.80/mile rejects at a £2.00 minimum', () {
      final settings = const DriverSettings();
      final outcome = engine.evaluate(_job(fare: 9, tripDistanceMiles: 5), settings);
      expect(outcome.poundsPerMile, 1.80);
      expect(outcome.decision, JobDecision.rejected);
    });

    test('£20 / 10 miles = £2.00/mile accepts at a £2.00 minimum', () {
      final settings = const DriverSettings();
      final outcome = engine.evaluate(_job(fare: 20, tripDistanceMiles: 10), settings);
      expect(outcome.decision, JobDecision.accepted);
    });

    test('exactly at the threshold (£2.00 = £2.00 minimum) accepts', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
        ),
      );
      final outcome = engine.evaluate(_job(fare: 12.50, tripDistanceMiles: 6.25), settings);
      expect(outcome.poundsPerMile, 2.00);
      expect(outcome.decision, JobDecision.accepted);
    });

    test('spec example: £12.50 / 5.2 miles accepts at a £2.00 minimum', () {
      final settings = const DriverSettings();
      final outcome = engine.evaluate(_job(fare: 12.50, tripDistanceMiles: 5.2), settings);
      expect(outcome.poundsPerMile, closeTo(2.40, 0.01));
      expect(outcome.decision, JobDecision.accepted);
    });

    test('spec example: £8.50 / 6.0 miles rejects at a £2.00 minimum', () {
      final settings = const DriverSettings();
      final outcome = engine.evaluate(_job(fare: 8.50, tripDistanceMiles: 6.0), settings);
      expect(outcome.poundsPerMile, closeTo(1.42, 0.01));
      expect(outcome.decision, JobDecision.rejected);
    });
  });

  group('safety: never auto-accept on missing/invalid data (spec section 8/35)', () {
    test('missing fare results in PENDING, not accepted', () {
      final settings = const DriverSettings();
      final outcome = engine.evaluate(_job(tripDistanceMiles: 5), settings);
      expect(outcome.decision, JobDecision.pending);
    });

    test('missing distance results in PENDING, not accepted', () {
      final settings = const DriverSettings();
      final outcome = engine.evaluate(_job(fare: 10), settings);
      expect(outcome.decision, JobDecision.pending);
    });

    test('zero distance does not divide by zero and does not accept', () {
      final settings = const DriverSettings();
      final outcome = engine.evaluate(_job(fare: 10, tripDistanceMiles: 0), settings);
      expect(outcome.decision, JobDecision.pending);
    });
  });

  group('combined rules (spec section 11)', () {
    test('fails when any enabled mandatory rule fails, even if £/mile passes', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          maximumPickupDistanceMiles: ThresholdRule(enabled: true, value: 3.0),
        ),
      );
      final outcome = engine.evaluate(
        _job(fare: 20, tripDistanceMiles: 5, pickupDistanceMiles: 5.0),
        settings,
      );
      expect(outcome.decision, JobDecision.rejected);
    });

    test('minimum fare rule rejects a short job even with a good £/mile rate', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          minimumFare: ThresholdRule(enabled: true, value: 7.00),
        ),
      );
      final outcome = engine.evaluate(_job(fare: 5, tripDistanceMiles: 2), settings);
      expect(outcome.decision, JobDecision.rejected);
    });

    test('disabled rules are skipped entirely', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: false, value: 2.00),
        ),
      );
      final outcome = engine.evaluate(_job(fare: 1, tripDistanceMiles: 100), settings);
      expect(outcome.decision, JobDecision.accepted);
    });
  });

  group('dead miles / total driving distance (spec section 12)', () {
    test('trip distance mode ignores pickup distance', () {
      final settings = const DriverSettings();
      final outcome = engine.evaluate(
        _job(fare: 12, tripDistanceMiles: 5, pickupDistanceMiles: 2),
        settings,
      );
      expect(outcome.poundsPerMile, 2.40);
    });

    test('total driving distance mode divides by pickup + trip', () {
      final settings = const DriverSettings(
        distanceCalculationMode: DistanceCalculationMode.totalDrivingDistance,
      );
      final outcome = engine.evaluate(
        _job(fare: 12, tripDistanceMiles: 5, pickupDistanceMiles: 2),
        settings,
      );
      // £12 / 7 miles ≈ £1.71/mile — below the £2.00 default minimum.
      expect(outcome.decision, JobDecision.rejected);
    });
  });

  group('minimum hourly rate rule (spec section 6)', () {
    test('£24 fare over 45 minutes is £32/hour', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: false, value: 2.00),
          minimumHourlyRate: ThresholdRule(enabled: true, value: 20.00),
        ),
      );
      final outcome = engine.evaluate(
        _job(fare: 24, tripDistanceMiles: 5, estimatedDurationMinutes: 45),
        settings,
      );
      expect(outcome.estimatedHourlyRate, closeTo(32.0, 0.01));
      expect(outcome.decision, JobDecision.accepted);
    });

    test('unknown duration does not fail the rule, just leaves it unresolved', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: false, value: 2.00),
          minimumHourlyRate: ThresholdRule(enabled: true, value: 20.00),
        ),
      );
      final outcome = engine.evaluate(_job(fare: 24, tripDistanceMiles: 5), settings);
      expect(outcome.decision, JobDecision.pending);
    });
  });

  group('platform-specific overrides (spec section 6, Rule 6)', () {
    test('Bolt uses its override instead of the global minimum', () {
      final settings = DriverSettings(
        rules: const RuleConfig(minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00)),
        platformOverrides: const {
          PlatformType.bolt: RuleConfig(
            minimumPoundsPerMile: ThresholdRule(enabled: true, value: 1.50),
          ),
        },
      );
      final outcome = engine.evaluate(
        _job(fare: 9, tripDistanceMiles: 5, platform: PlatformType.bolt), // £1.80/mile
        settings,
      );
      expect(outcome.decision, JobDecision.accepted);
    });
  });
}
