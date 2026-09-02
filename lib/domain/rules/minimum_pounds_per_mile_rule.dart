import '../entities/rule_evaluation.dart';
import '../entities/taxi_job.dart';
import '../enums/distance_unit.dart';
import '../enums/rule_result.dart';
import '../services/currency_service.dart';
import 'rule.dart';

/// Rule 1 (spec section 6/10) — the core "is this job worth it" check.
///
/// poundsPerMile = fare / distance, where `distance` is either the
/// passenger-trip distance or the total driving distance (pickup + trip),
/// depending on [RuleConfigView.distanceCalculationMode] (spec section 12) —
/// UNLESS the platform already displays its own £/mile directly (Bolt does;
/// see [TaxiJob.displayedPoundsPerMile]), in which case that figure is used
/// as-is instead of being re-derived. A real device proved this matters: for
/// the same Bolt job, Bolt's own displayed rate (£1.03/mile, computed from
/// total driving distance) and this app's trip-only computation (£1.94/mile)
/// disagreed enough to flip a driver's threshold from fail to pass —
/// preferring the platform's own number removes both that distance-basis
/// mismatch and this app's own pickup/trip parsing as a source of error.
class MinimumPoundsPerMileRule implements Rule {
  const MinimumPoundsPerMileRule();

  @override
  String get name => 'Minimum £/mile';

  @override
  bool get mandatory => true;

  @override
  bool isEnabled(RuleConfigView settings) {
    // Always on — this rule must never be disabled: the near-miss and
    // low-fare counter-offer rescues (which depend on the £/mile rule
    // being the sole failing rule) require it to evaluate first.
    return true;
  }

  @override
  RuleEvaluation evaluate(TaxiJob job, RuleConfigView settings) {
    final poundsPerMile = resolvePoundsPerMile(job, settings);

    if (poundsPerMile == null) {
      return RuleEvaluation(
        ruleName: name,
        result: RuleResult.unknown,
        mandatory: mandatory,
        detail: job.displayedPoundsPerMile == null && job.fare == null
            ? 'Fare or distance could not be determined'
            : 'Distance was zero or invalid',
      );
    }

    final minimum = settings.rules.minimumPoundsPerMile.value;
    final pass = poundsPerMile >= minimum;
    return RuleEvaluation(
      ruleName: name,
      result: pass ? RuleResult.pass : RuleResult.fail,
      mandatory: mandatory,
      detail: pass
          ? 'This job pays £${poundsPerMile.toStringAsFixed(2)}/mile, at or above '
              'the £${minimum.toStringAsFixed(2)}/mile minimum you set'
          : 'You set a minimum of £${minimum.toStringAsFixed(2)}/mile, but this job '
              'only pays £${poundsPerMile.toStringAsFixed(2)}/mile',
    );
  }

  /// Shared by [evaluate] and [JobDecisionEngine] so the figure a driver
  /// sees on screen is always the exact one the rule actually decided on.
  static double? resolvePoundsPerMile(TaxiJob job, RuleConfigView settings) {
    if (job.displayedPoundsPerMile != null) {
      return CurrencyService.roundToPence(job.displayedPoundsPerMile!);
    }

    final fare = job.fare;
    final distance = settings.distanceCalculationMode == DistanceCalculationMode.tripDistance
        ? job.tripDistanceMiles
        : job.totalDrivingDistanceMiles;
    if (fare == null || distance == null || distance <= 0) return null;
    return CurrencyService.roundToPence(fare / distance);
  }
}
