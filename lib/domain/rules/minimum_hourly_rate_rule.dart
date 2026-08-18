import '../entities/rule_evaluation.dart';
import '../entities/taxi_job.dart';
import '../enums/rule_result.dart';
import 'rule.dart';

/// Rule 5 (spec section 6) — only evaluated when a reliable trip-duration
/// estimate is available; otherwise UNKNOWN rather than a guessed FAIL.
///
/// estimatedHourlyRate = fare / (durationMinutes / 60)
class MinimumHourlyRateRule implements Rule {
  const MinimumHourlyRateRule();

  @override
  String get name => 'Minimum estimated hourly rate';

  @override
  bool get mandatory => true;

  @override
  bool isEnabled(RuleConfigView settings) => settings.rules.minimumHourlyRate.enabled;

  @override
  RuleEvaluation evaluate(TaxiJob job, RuleConfigView settings) {
    final fare = job.fare;
    final durationMinutes = job.estimatedDurationMinutes;
    if (fare == null || durationMinutes == null || durationMinutes <= 0) {
      return RuleEvaluation(
        ruleName: name,
        result: RuleResult.unknown,
        mandatory: mandatory,
        detail: 'Trip duration could not be reliably determined',
      );
    }

    final hours = durationMinutes / 60.0;
    final hourlyRate = fare / hours;
    final minimum = settings.rules.minimumHourlyRate.value;

    final pass = hourlyRate >= minimum;
    return RuleEvaluation(
      ruleName: name,
      result: pass ? RuleResult.pass : RuleResult.fail,
      mandatory: mandatory,
      detail: pass
          ? 'Estimated hourly rate is £${hourlyRate.toStringAsFixed(2)}/hour, at or above '
              'the £${minimum.toStringAsFixed(2)}/hour minimum you set'
          : 'You set a minimum estimated hourly rate of £${minimum.toStringAsFixed(2)}/hour, but this '
              'job estimates to £${hourlyRate.toStringAsFixed(2)}/hour',
    );
  }
}
