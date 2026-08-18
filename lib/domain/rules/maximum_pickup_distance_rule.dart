import '../entities/rule_evaluation.dart';
import '../entities/taxi_job.dart';
import '../enums/rule_result.dart';
import 'rule.dart';

/// Rule 2 (spec section 6) — reject jobs whose deadhead/pickup distance is
/// too large, regardless of how good the trip itself pays.
class MaximumPickupDistanceRule implements Rule {
  const MaximumPickupDistanceRule();

  @override
  String get name => 'Maximum pickup distance';

  @override
  bool get mandatory => true;

  @override
  bool isEnabled(RuleConfigView settings) =>
      settings.rules.maximumPickupDistanceMiles.enabled;

  @override
  RuleEvaluation evaluate(TaxiJob job, RuleConfigView settings) {
    final pickup = job.pickupDistanceMiles;
    if (pickup == null) {
      return RuleEvaluation(
        ruleName: name,
        result: RuleResult.unknown,
        mandatory: mandatory,
        detail: 'Pickup distance could not be determined',
      );
    }

    final maximum = settings.rules.maximumPickupDistanceMiles.value;
    final pass = pickup <= maximum;
    return RuleEvaluation(
      ruleName: name,
      result: pass ? RuleResult.pass : RuleResult.fail,
      mandatory: mandatory,
      detail: pass
          ? 'Pickup distance is ${pickup.toStringAsFixed(1)} mi, within the '
              '${maximum.toStringAsFixed(1)} mi maximum you set'
          : 'You set a maximum pickup distance of ${maximum.toStringAsFixed(1)} mi, but '
              'this job\'s pickup is ${pickup.toStringAsFixed(1)} mi away',
    );
  }
}
