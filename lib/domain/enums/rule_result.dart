/// Result of evaluating a single [Rule] against a job. `unknown` is distinct
/// from `fail` on purpose: missing data must never be treated as a pass, but it
/// is also not automatically a hard rejection unless the rule is mandatory —
/// see JobDecisionEngine and docs/decision-engine.md.
enum RuleResult {
  pass,
  fail,
  unknown,
}
