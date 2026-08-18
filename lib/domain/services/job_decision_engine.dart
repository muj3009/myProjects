import '../entities/driver_settings.dart';
import '../entities/rule_evaluation.dart';
import '../entities/taxi_job.dart';
import '../enums/job_decision.dart';
import '../enums/platform_type.dart';
import '../enums/rule_result.dart';
import '../rules/maximum_pickup_distance_rule.dart';
import '../rules/maximum_trip_distance_rule.dart';
import '../rules/minimum_fare_rule.dart';
import '../rules/minimum_hourly_rate_rule.dart';
import '../rules/minimum_pounds_per_mile_rule.dart';
import '../rules/postcode_blocklist_rule.dart';
import '../rules/rule.dart';

/// Pure business-logic rule engine (spec section 10/11). Contains no UI code
/// and no platform calls — it only turns (job, settings) into a decision.
///
/// Strategy, in priority order:
///   1. If any enabled mandatory rule FAILs           -> REJECT
///   2. Else if any enabled mandatory rule is UNKNOWN  -> PENDING (no auto-accept)
///   3. Else (all enabled rules PASS)                  -> ACCEPT
///
/// This mirrors spec section 11 exactly, and section 51/52's priority order:
/// safety and correct parsing outrank speed — an uncertain job is never
/// auto-accepted, even if that means missing an otherwise-good job.
class JobDecisionEngine {
  JobDecisionEngine({List<Rule>? rules})
      : _rules = rules ??
            const [
              PostcodeBlocklistRule(),
              MinimumPoundsPerMileRule(),
              MaximumPickupDistanceRule(),
              MinimumFareRule(),
              MaximumTripDistanceRule(),
              MinimumHourlyRateRule(),
            ];

  final List<Rule> _rules;

  /// All rules the engine knows about, including disabled ones — exposed for
  /// the Rule Builder UI so it can render a row per rule.
  List<Rule> get availableRules => List.unmodifiable(_rules);

  DecisionOutcome evaluate(TaxiJob job, DriverSettings settings) {
    final ruleConfig = settings.rulesFor(job.platform);
    final view = RuleConfigView(
      rules: ruleConfig,
      distanceCalculationMode: settings.distanceCalculationMode,
    );

    final evaluations = <RuleEvaluation>[];
    for (final rule in _rules) {
      if (!rule.isEnabled(view)) continue;
      evaluations.add(rule.evaluate(job, view));
    }

    final failed = evaluations.where((e) => e.result == RuleResult.fail).toList();
    final unknown = evaluations.where((e) => e.result == RuleResult.unknown).toList();

    // £/mile and estimated hourly rate are useful even when the final
    // decision isn't ACCEPT, so the driver/debug screen can see the numbers.
    final poundsPerMile = MinimumPoundsPerMileRule.resolvePoundsPerMile(job, view);
    final hourlyRate = job.fare != null &&
            job.estimatedDurationMinutes != null &&
            job.estimatedDurationMinutes! > 0
        ? job.fare! / (job.estimatedDurationMinutes! / 60.0)
        : null;

    if (failed.isNotEmpty) {
      // Driver request: a Bolt job that fails ONLY on £/mile, and isn't too
      // far under the threshold, gets a counter-offer instead of an outright
      // reject — see RuleConfig.counterOfferBandPercent's doc comment.
      // Scoped to exactly one failing rule so every other rule (postcode
      // blocklist, max distance, etc.) still overrides this unconditionally,
      // same as any other fail.
      if (job.platform == PlatformType.bolt &&
          ruleConfig.counterOfferBandPercent.enabled &&
          failed.length == 1 &&
          failed.first.ruleName == const MinimumPoundsPerMileRule().name &&
          poundsPerMile != null) {
        final minimum = ruleConfig.minimumPoundsPerMile.value;
        final bandPercent = ruleConfig.counterOfferBandPercent.value;
        final counterOfferFloor = minimum * (bandPercent / 100.0);
        if (poundsPerMile >= counterOfferFloor) {
          return DecisionOutcome(
            decision: JobDecision.counterOffered,
            evaluations: evaluations,
            reason: _bulletList([
              failed.first.detail,
              'That\'s still within ${bandPercent.round()}% of your minimum, so JobFilter sent '
                  'a counter-offer instead of rejecting it',
            ]),
            poundsPerMile: poundsPerMile,
            estimatedHourlyRate: hourlyRate,
          );
        }
      }

      return DecisionOutcome(
        decision: JobDecision.rejected,
        evaluations: evaluations,
        reason: _bulletList(failed.map((e) => e.detail)),
        poundsPerMile: poundsPerMile,
        estimatedHourlyRate: hourlyRate,
      );
    }

    if (unknown.isNotEmpty) {
      return DecisionOutcome(
        decision: JobDecision.pending,
        evaluations: evaluations,
        reason: _bulletList(unknown.map((e) => '${e.ruleName}: ${e.detail}')),
        poundsPerMile: poundsPerMile,
        estimatedHourlyRate: hourlyRate,
      );
    }

    // Every enabled rule passed — explain each one, same as a rejection
    // explains each rule that failed, so an accepted job is just as clear.
    return DecisionOutcome(
      decision: JobDecision.accepted,
      evaluations: evaluations,
      reason: evaluations.isEmpty
          ? 'No rules were enabled to check this job against.'
          : _bulletList(evaluations.map((e) => e.detail)),
      poundsPerMile: poundsPerMile,
      estimatedHourlyRate: hourlyRate,
    );
  }

  /// One bullet per line rather than a run-on paragraph — a driver request:
  /// with more than one rule contributing to a decision, a wall of joined
  /// sentences was hard to scan quickly at a glance in Job History.
  static String _bulletList(Iterable<String?> lines) {
    return lines
        .where((line) => line != null && line.isNotEmpty)
        .map((line) => '• $line')
        .join('\n');
  }
}
