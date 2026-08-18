import 'package:equatable/equatable.dart';

import '../enums/job_decision.dart';
import '../enums/rule_result.dart';

/// Outcome of a single rule, kept for transparency in Simulation Mode and the
/// debug screen (spec sections 33/34) — the driver should always be able to
/// see *why* a decision was made, not just the final verdict.
class RuleEvaluation extends Equatable {
  const RuleEvaluation({
    required this.ruleName,
    required this.result,
    required this.mandatory,
    this.detail,
  });

  final String ruleName;
  final RuleResult result;

  /// Whether a FAIL/UNKNOWN on this rule blocks an ACCEPT. Disabled rules are
  /// never included in the evaluation list at all (see JobDecisionEngine).
  final bool mandatory;

  final String? detail;

  @override
  List<Object?> get props => [ruleName, result, mandatory, detail];
}

/// Full output of JobDecisionEngine.evaluate — the final decision plus the
/// per-rule breakdown that produced it.
class DecisionOutcome extends Equatable {
  const DecisionOutcome({
    required this.decision,
    required this.evaluations,
    this.reason,
    this.poundsPerMile,
    this.estimatedHourlyRate,
  });

  final JobDecision decision;
  final List<RuleEvaluation> evaluations;
  final String? reason;
  final double? poundsPerMile;
  final double? estimatedHourlyRate;

  @override
  List<Object?> get props => [decision, evaluations, reason, poundsPerMile, estimatedHourlyRate];
}
