import '../entities/driver_settings.dart';
import '../entities/rule_config.dart';
import '../entities/rule_evaluation.dart';
import '../entities/taxi_job.dart';
import '../enums/distance_unit.dart';

/// Contract for a single, independently-configurable filter rule (spec
/// section 11). Implementations must be pure: no I/O, no platform calls, no
/// mutation of [job] — see JobDecisionEngine, which is the only place these
/// are composed into a final decision.
abstract interface class Rule {
  /// Stable, human-readable name shown in Simulation Mode / debug output.
  String get name;

  /// Whether this rule is currently switched on in [settings]. A disabled
  /// rule is skipped by the engine entirely (treated as if it doesn't exist).
  bool isEnabled(RuleConfigView settings);

  /// Whether a FAIL/UNKNOWN verdict from this rule should block an ACCEPT.
  /// All rules in this app are mandatory-when-enabled by design (spec
  /// section 11: "If any mandatory rule FAILS: REJECT"), but the flag is
  /// kept so a future advisory-only rule doesn't require an engine change.
  bool get mandatory => true;

  RuleEvaluation evaluate(TaxiJob job, RuleConfigView settings);
}

/// Narrow view over [DriverSettings] that a [Rule] actually needs, already
/// resolved for the job's platform (platform overrides applied) and distance
/// unit/mode. Keeps rules from depending on the whole settings object shape.
class RuleConfigView {
  const RuleConfigView({
    required this.rules,
    required this.distanceCalculationMode,
  });

  final RuleConfig rules;
  final DistanceCalculationMode distanceCalculationMode;
}
