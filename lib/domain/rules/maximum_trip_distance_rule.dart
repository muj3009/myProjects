import '../entities/rule_evaluation.dart';
import '../entities/taxi_job.dart';
import '../enums/rule_result.dart';
import 'rule.dart';

/// Rule 4 (spec section 6) — reject unusually long trips, e.g. so a driver
/// nearing the end of their shift doesn't get pulled far from home.
class MaximumTripDistanceRule implements Rule {
  const MaximumTripDistanceRule();

  @override
  String get name => 'Maximum trip distance';

  @override
  bool get mandatory => true;

  @override
  bool isEnabled(RuleConfigView settings) =>
      settings.rules.maximumTripDistanceMiles.enabled;

  @override
  RuleEvaluation evaluate(TaxiJob job, RuleConfigView settings) {
    final trip = job.tripDistanceMiles;
    if (trip == null) {
      return RuleEvaluation(
        ruleName: name,
        result: RuleResult.unknown,
        mandatory: mandatory,
        detail: 'Trip distance could not be determined',
      );
    }

    final maximum = settings.rules.maximumTripDistanceMiles.value;
    final pass = trip <= maximum;
    return RuleEvaluation(
      ruleName: name,
      result: pass ? RuleResult.pass : RuleResult.fail,
      mandatory: mandatory,
      detail: pass
          ? 'Trip distance is ${trip.toStringAsFixed(1)} mi, within the '
              '${maximum.toStringAsFixed(1)} mi maximum you set'
          : 'You set a maximum trip distance of ${maximum.toStringAsFixed(1)} mi, but '
              'this trip is ${trip.toStringAsFixed(1)} mi',
    );
  }
}
