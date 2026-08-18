# Decision engine

## Contract

```dart
DecisionOutcome evaluate(TaxiJob job, DriverSettings settings)
```

in `domain/services/job_decision_engine.dart`. Pure function of its two arguments — no I/O, no
platform calls, no mutation of `job`. This is what makes `test/domain/job_decision_engine_test.dart`
possible without any mocking at all.

## Rule engine, not hard-coded rules (spec section 11)

```
TaxiJob + DriverSettings
        ↓
  RuleConfigView (resolved for the job's platform + distance-calculation mode)
        ↓
  [MinimumPoundsPerMileRule, MaximumPickupDistanceRule, MinimumFareRule,
   MaximumTripDistanceRule, MinimumHourlyRateRule]   (domain/rules/*.dart)
        ↓
  each disabled rule is skipped entirely; each enabled rule returns PASS / FAIL / UNKNOWN
        ↓
  any FAIL  -> rejected
  else any UNKNOWN -> pending (no auto-accept)
  else -> accepted
```

Every rule implements the same `Rule` interface (`domain/rules/rule.dart`):

```dart
abstract interface class Rule {
  String get name;
  bool isEnabled(RuleConfigView settings);
  bool get mandatory; // always true today — see the interface doc comment
  RuleEvaluation evaluate(TaxiJob job, RuleConfigView settings);
}
```

Adding rule #6+ from spec section 11's "later we may add..." list (destination filters, postcode
blacklists, time-of-day, etc.) means writing one new class implementing `Rule` and adding it to
the list `JobDecisionEngine` is constructed with — no change to the engine's control flow, the
database schema (rule config is stored as JSON, see `docs/architecture.md`), or any screen beyond
adding a row to `RulesScreen`.

## £/mile precision (spec section 10)

`fare / distance` is rounded to the nearest penny (`CurrencyService.roundToPence`) before being
compared against the driver's minimum, specifically so `£10 / 5 = 2.0` doesn't fail an
`>=` comparison against `2.00` due to binary floating-point representation. This is what makes
"exactly £2.00/mile accepts at a £2.00 minimum" hold in practice, not just in theory — see the
"exactly at the threshold" test case.

## Dead miles (spec section 12)

`DriverSettings.distanceCalculationMode` selects which distance the £/mile rule divides by:

- `tripDistance` (default) — passenger-carrying distance only.
- `totalDrivingDistance` — pickup + trip, i.e. everything the driver actually drives for the job.

`TaxiJob.totalDrivingDistanceMiles` computes the second from the two stored distances. Every
other rule (pickup/trip maxima, minimum fare, hourly rate) is unaffected by this setting — it
only changes what "£/mile" means for `MinimumPoundsPerMileRule`.

## Why UNKNOWN isn't FAIL (spec section 8/35/51)

A rule returns `RuleResult.unknown` when it can't evaluate at all (e.g. no duration was parsed,
so `MinimumHourlyRateRule` can't compute a rate) — this is different from `FAIL`, which means the
rule evaluated and the job didn't meet it. The engine's outcome for "no FAILs, but at least one
UNKNOWN" is `JobDecision.pending`, which `AutomationController` treats identically to `rejected`
for the purpose of *not* performing an accept action, but is tracked and displayed separately (as
"insufficient information") so the driver/debug screen can tell "this job wasn't good enough"
apart from "JobFilter couldn't read this job properly." Spec section 51's stated priority —
"accuracy > speed" and "a wrong ACCEPT is more dangerous than a missed job" — is the reason this
distinction exists rather than collapsing UNKNOWN into REJECT.
