import 'package:flutter_test/flutter_test.dart';
import 'package:jobfilter/domain/entities/driver_settings.dart';
import 'package:jobfilter/domain/entities/rule_config.dart';
import 'package:jobfilter/domain/entities/taxi_job.dart';
import 'package:jobfilter/domain/enums/distance_unit.dart';
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

  group('low-fare auto counter-offer (Rule 8, driver request)', () {
    test('Bolt job below minimum £/mile and below the low-fare threshold is counter-offered', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          lowFareCounterOfferThreshold: ThresholdRule(enabled: true, value: 4.00),
        ),
      );
      final outcome = engine.evaluate(
        _job(fare: 3.00, tripDistanceMiles: 5, platform: PlatformType.bolt), // £0.60/mile
        settings,
      );
      expect(outcome.decision, JobDecision.counterOffered);
    });

    test('at/above the low-fare threshold still rejects outright', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          lowFareCounterOfferThreshold: ThresholdRule(enabled: true, value: 4.00),
        ),
      );
      final outcome = engine.evaluate(
        _job(fare: 4.00, tripDistanceMiles: 5, platform: PlatformType.bolt), // £0.80/mile
        settings,
      );
      expect(outcome.decision, JobDecision.rejected);
    });

    test('never fires for Uber — no counter-offer flow exists there', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          lowFareCounterOfferThreshold: ThresholdRule(enabled: true, value: 4.00),
        ),
      );
      final outcome = engine.evaluate(
        _job(fare: 3.00, tripDistanceMiles: 5, platform: PlatformType.uber),
        settings,
      );
      expect(outcome.decision, JobDecision.rejected);
    });

    test('disabled by default — an old settings object sees no behavior change', () {
      final settings = DriverSettings(
        rules: const RuleConfig(minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00)),
      );
      final outcome = engine.evaluate(
        _job(fare: 3.00, tripDistanceMiles: 5, platform: PlatformType.bolt),
        settings,
      );
      expect(outcome.decision, JobDecision.rejected);
    });
  });

  group('high-value job override (Rule 9, driver request)', () {
    test('fare + rate both at/above the floors accepts immediately, bypassing another failing rule', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          maximumPickupDistanceMiles: ThresholdRule(enabled: true, value: 3.0),
          highValueJob: HighValueJobOverride(enabled: true, fareFloor: 15.0, acceptRateFloor: 1.50),
        ),
      );
      final outcome = engine.evaluate(
        _job(fare: 16, tripDistanceMiles: 8, pickupDistanceMiles: 50), // £2.00/mile, pickup would fail
        settings,
      );
      expect(outcome.decision, JobDecision.accepted);
    });

    test('fare at/above floor but rate below acceptRateFloor counter-offers on Bolt', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          highValueJob: HighValueJobOverride(enabled: true, fareFloor: 15.0, acceptRateFloor: 1.50),
        ),
      );
      final outcome = engine.evaluate(
        _job(fare: 16, tripDistanceMiles: 11.43, platform: PlatformType.bolt), // ≈£1.40/mile
        settings,
      );
      expect(outcome.decision, JobDecision.counterOffered);
    });

    test('same below-floor case on Uber falls through to a normal reject, not a counter-offer', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          highValueJob: HighValueJobOverride(enabled: true, fareFloor: 15.0, acceptRateFloor: 1.50),
        ),
      );
      final outcome = engine.evaluate(
        _job(fare: 16, tripDistanceMiles: 11.43, platform: PlatformType.uber), // ≈£1.40/mile
        settings,
      );
      expect(outcome.decision, JobDecision.rejected);
    });

    test('rate at/above acceptRateFloor (£1.60) accepts immediately', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          highValueJob: HighValueJobOverride(
            enabled: true,
            fareFloor: 15.0,
            acceptRateFloor: 1.60,
            counterOfferRateFloor: 1.30,
          ),
        ),
      );
      final outcome = engine.evaluate(
        _job(fare: 24, tripDistanceMiles: 15), // £1.60/mile exactly
        settings,
      );
      expect(outcome.decision, JobDecision.accepted);
    });

    test('rate inside the £1.30–£1.60 band counter-offers on Bolt', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          highValueJob: HighValueJobOverride(
            enabled: true,
            fareFloor: 15.0,
            acceptRateFloor: 1.60,
            counterOfferRateFloor: 1.30,
          ),
        ),
      );
      final outcome = engine.evaluate(
        _job(fare: 21, tripDistanceMiles: 15, platform: PlatformType.bolt), // £1.40/mile
        settings,
      );
      expect(outcome.decision, JobDecision.counterOffered);
    });

    test('rate exactly at counterOfferRateFloor (£1.30) still counter-offers', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          highValueJob: HighValueJobOverride(
            enabled: true,
            fareFloor: 15.0,
            acceptRateFloor: 1.60,
            counterOfferRateFloor: 1.30,
          ),
        ),
      );
      final outcome = engine.evaluate(
        _job(fare: 19.50, tripDistanceMiles: 15, platform: PlatformType.bolt), // £1.30/mile exactly
        settings,
      );
      expect(outcome.decision, JobDecision.counterOffered);
    });

    test('rate below counterOfferRateFloor (£1.30) does nothing — falls through to a normal reject', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          highValueJob: HighValueJobOverride(
            enabled: true,
            fareFloor: 15.0,
            acceptRateFloor: 1.60,
            counterOfferRateFloor: 1.30,
          ),
        ),
      );
      final outcome = engine.evaluate(
        _job(fare: 15, tripDistanceMiles: 12.5, platform: PlatformType.bolt), // £1.20/mile
        settings,
      );
      expect(outcome.decision, JobDecision.rejected);
    });

    test('a blocked destination postcode still rejects, even at a qualifying fare and rate', () {
      final settings = DriverSettings(
        rules: RuleConfig(
          minimumPoundsPerMile: const ThresholdRule(enabled: true, value: 2.00),
          highValueJob:
              const HighValueJobOverride(enabled: true, fareFloor: 15.0, acceptRateFloor: 1.50),
          postcodeBlocklist: const PostcodeBlocklistConfig(enabled: true, blockedPrefixes: ['LE4']),
        ),
      );
      final job = TaxiJob(
        id: 'test-job',
        platform: PlatformType.bolt,
        detectedAt: DateTime(2026, 1, 1),
        decision: JobDecision.pending,
        fare: 16,
        tripDistanceMiles: 8,
        destinationPostcode: 'LE4',
      );
      final outcome = engine.evaluate(job, settings);
      expect(outcome.decision, JobDecision.rejected);
    });

    test('below the fare floor entirely is unaffected — normal rules apply', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          highValueJob: HighValueJobOverride(enabled: true, fareFloor: 15.0, acceptRateFloor: 1.50),
        ),
      );
      final outcome = engine.evaluate(_job(fare: 10, tripDistanceMiles: 5), settings); // £2.00/mile
      expect(outcome.decision, JobDecision.accepted);
    });
  });

  group('quiet-time relaxed minimum £/mile (Rule 10, driver request)', () {
    test('during quiet time, a job at/above the relaxed floor is accepted', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          quietTimeMinimumPoundsPerMile: ThresholdRule(enabled: true, value: 1.60),
        ),
      );
      final outcome = engine.evaluate(
        _job(fare: 8.50, tripDistanceMiles: 5), // £1.70/mile
        settings,
        isBusyTime: false,
      );
      expect(outcome.decision, JobDecision.accepted);
    });

    test('the identical job during busy time still uses the normal minimum and rejects', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          quietTimeMinimumPoundsPerMile: ThresholdRule(enabled: true, value: 1.60),
        ),
      );
      final outcome = engine.evaluate(
        _job(fare: 8.50, tripDistanceMiles: 5), // £1.70/mile
        settings,
        isBusyTime: true,
      );
      expect(outcome.decision, JobDecision.rejected);
    });

    test('below even the relaxed floor still rejects during quiet time', () {
      final settings = DriverSettings(
        rules: const RuleConfig(
          minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00),
          quietTimeMinimumPoundsPerMile: ThresholdRule(enabled: true, value: 1.60),
        ),
      );
      final outcome = engine.evaluate(
        _job(fare: 7.50, tripDistanceMiles: 5), // £1.50/mile
        settings,
        isBusyTime: false,
      );
      expect(outcome.decision, JobDecision.rejected);
    });

    test('disabled by default — isBusyTime has no effect on existing behavior', () {
      final settings = DriverSettings(
        rules: const RuleConfig(minimumPoundsPerMile: ThresholdRule(enabled: true, value: 2.00)),
      );
      final outcome = engine.evaluate(
        _job(fare: 8.50, tripDistanceMiles: 5), // £1.70/mile
        settings,
        isBusyTime: false,
      );
      expect(outcome.decision, JobDecision.rejected);
    });
  });
}
