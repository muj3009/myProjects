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

  /// [isBusyTime] — driver request: whether 8+ jobs have been detected in
  /// the last 5 minutes (computed by the caller — AutomationController —
  /// since that requires job-history I/O this pure engine deliberately
  /// doesn't do itself; see RuleConfig.quietTimeMinimumPoundsPerMile).
  /// Defaults to false (treated as "not busy") so any caller that doesn't
  /// pass it gets the same behavior as before this parameter existed.
  DecisionOutcome evaluate(TaxiJob job, DriverSettings settings, {bool isBusyTime = false}) {
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

    // Driver request: a "high-value job" — at or above a fare floor and a
    // £/mile floor — is accepted immediately, ignoring every other rule
    // (pickup distance, trip distance, minimum fare, hourly rate). The one
    // deliberate exception is the postcode blocklist: driver-confirmed that
    // a destination they've explicitly blocked must still always be
    // rejected, no matter how good the fare is. Checked before the normal
    // fail/unknown/accept decision tree entirely, since "ignore all other
    // filters" means this can't be scoped to "only when nothing else failed"
    // the way the counter-offer rescues below are.
    if (ruleConfig.highValueJob.enabled && job.fare != null) {
      final highValue = ruleConfig.highValueJob;
      if (job.fare! >= highValue.fareFloor) {
        final postcodeBlocked = evaluations.any(
          (e) => e.ruleName == const PostcodeBlocklistRule().name && e.result == RuleResult.fail,
        );
        if (!postcodeBlocked && poundsPerMile != null) {
          if (poundsPerMile >= highValue.acceptRateFloor) {
            return DecisionOutcome(
              decision: JobDecision.accepted,
              evaluations: evaluations,
              reason: _bulletList([
                'Fare is £${job.fare!.toStringAsFixed(2)} (at or above your £${highValue.fareFloor.toStringAsFixed(2)} '
                    'high-value threshold) at £${poundsPerMile.toStringAsFixed(2)}/mile (at or above your '
                    '£${highValue.acceptRateFloor.toStringAsFixed(2)}/mile floor) — accepted immediately, '
                    'ignoring your other rules',
              ]),
              poundsPerMile: poundsPerMile,
              estimatedHourlyRate: hourlyRate,
            );
          } else if (job.platform == PlatformType.bolt) {
            return DecisionOutcome(
              decision: JobDecision.counterOffered,
              evaluations: evaluations,
              reason: _bulletList([
                'Fare is £${job.fare!.toStringAsFixed(2)} (at or above your £${highValue.fareFloor.toStringAsFixed(2)} '
                    'high-value threshold) but only £${poundsPerMile.toStringAsFixed(2)}/mile — JobFilter sent a '
                    'counter-offer instead of rejecting it',
              ]),
              poundsPerMile: poundsPerMile,
              estimatedHourlyRate: hourlyRate,
            );
          }
        }
      }
    }

    if (failed.isNotEmpty) {
      // Driver request: during a quiet period (not busy — see isBusyTime),
      // relax the effective minimum £/mile down to this value rather than
      // rejecting. Scoped the same as the rescues below (only when £/mile is
      // the sole failing rule) and checked first, since an outright accept
      // is a better outcome for the driver than a counter-offer attempt.
      if (ruleConfig.quietTimeMinimumPoundsPerMile.enabled &&
          !isBusyTime &&
          failed.length == 1 &&
          failed.first.ruleName == const MinimumPoundsPerMileRule().name &&
          poundsPerMile != null &&
          poundsPerMile >= ruleConfig.quietTimeMinimumPoundsPerMile.value) {
        return DecisionOutcome(
          decision: JobDecision.accepted,
          evaluations: evaluations,
          reason: _bulletList([
            'It\'s quiet right now, so JobFilter relaxed your minimum down to '
                '£${ruleConfig.quietTimeMinimumPoundsPerMile.value.toStringAsFixed(2)}/mile — this job pays '
                '£${poundsPerMile.toStringAsFixed(2)}/mile, so it was accepted',
          ]),
          poundsPerMile: poundsPerMile,
          estimatedHourlyRate: hourlyRate,
        );
      }

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

      // Driver request: a flat-fare alternative to the percentage-based
      // rescue above — a Bolt job worth at least this much still gets a
      // counter-offer even if it's nowhere near the driver's minimum
      // £/mile, since the total money can still make it worth trying for
      // more rather than rejecting outright. Independent of the band-percent
      // rescue above — either one qualifying is enough.
      if (job.platform == PlatformType.bolt &&
          ruleConfig.counterOfferFareFloor.enabled &&
          failed.length == 1 &&
          failed.first.ruleName == const MinimumPoundsPerMileRule().name &&
          job.fare != null &&
          job.fare! >= ruleConfig.counterOfferFareFloor.value) {
        return DecisionOutcome(
          decision: JobDecision.counterOffered,
          evaluations: evaluations,
          reason: _bulletList([
            failed.first.detail,
            'The fare is still £${job.fare!.toStringAsFixed(2)} (at or above your '
                '£${ruleConfig.counterOfferFareFloor.value.toStringAsFixed(2)} counter-offer floor), so '
                'JobFilter sent a counter-offer instead of rejecting it',
          ]),
          poundsPerMile: poundsPerMile,
          estimatedHourlyRate: hourlyRate,
        );
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
