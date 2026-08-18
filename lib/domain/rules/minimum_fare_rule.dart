import '../entities/rule_evaluation.dart';
import '../entities/taxi_job.dart';
import '../enums/rule_result.dart';
import 'rule.dart';

/// Rule 3 (spec section 6) — reject jobs below a flat minimum fare, even if
/// the £/mile rate looks acceptable (protects against very short, low-value trips).
class MinimumFareRule implements Rule {
  const MinimumFareRule();

  @override
  String get name => 'Minimum fare';

  @override
  bool get mandatory => true;

  @override
  bool isEnabled(RuleConfigView settings) => settings.rules.minimumFare.enabled;

  @override
  RuleEvaluation evaluate(TaxiJob job, RuleConfigView settings) {
    final fare = job.fare;
    if (fare == null) {
      return RuleEvaluation(
        ruleName: name,
        result: RuleResult.unknown,
        mandatory: mandatory,
        detail: 'Fare could not be determined',
      );
    }

    final minimum = settings.rules.minimumFare.value;
    final pass = fare >= minimum;
    return RuleEvaluation(
      ruleName: name,
      result: pass ? RuleResult.pass : RuleResult.fail,
      mandatory: mandatory,
      detail: pass
          ? 'Fare is £${fare.toStringAsFixed(2)}, at or above the £${minimum.toStringAsFixed(2)} minimum you set'
          : 'You set a minimum fare of £${minimum.toStringAsFixed(2)}, but this job only pays £${fare.toStringAsFixed(2)}',
    );
  }
}
