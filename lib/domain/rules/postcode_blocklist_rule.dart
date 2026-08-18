import '../entities/rule_evaluation.dart';
import '../entities/taxi_job.dart';
import '../enums/rule_result.dart';
import 'rule.dart';

/// Rule 6 (driver request) — reject any job whose destination outward
/// postcode matches a driver-configured blocklist (e.g. "LE4", "LE5"),
/// regardless of £/mile, fare, or any other rule. Works exactly like every
/// other rule here: JobDecisionEngine already rejects the whole job the
/// moment ANY enabled mandatory rule fails, so simply failing this rule on a
/// blocked postcode is what gives "regardless of £/mile" — no special-casing
/// needed in the engine itself.
///
/// A postcode that couldn't be read PASSES rather than blocks (spec section
/// 8: never guess) — this rule only ever overrides a decision when it
/// positively identifies a blocked area; it never withholds a decision the
/// other rules would otherwise reach just because OCR missed the address.
class PostcodeBlocklistRule implements Rule {
  const PostcodeBlocklistRule();

  @override
  String get name => 'Destination postcode blocklist';

  @override
  bool get mandatory => true;

  @override
  bool isEnabled(RuleConfigView settings) => settings.rules.postcodeBlocklist.enabled;

  @override
  RuleEvaluation evaluate(TaxiJob job, RuleConfigView settings) {
    final postcode = job.destinationPostcode;
    if (postcode == null) {
      return RuleEvaluation(
        ruleName: name,
        result: RuleResult.pass,
        mandatory: mandatory,
        detail: 'Destination postcode not available — not blocked',
      );
    }

    final blockedPrefixes = settings.rules.postcodeBlocklist.blockedPrefixes;
    final matchedPrefix = blockedPrefixes.firstWhere(
      (prefix) => postcode.toUpperCase().startsWith(prefix.trim().toUpperCase()),
      orElse: () => '',
    );
    final blocked = matchedPrefix.isNotEmpty;

    return RuleEvaluation(
      ruleName: name,
      result: blocked ? RuleResult.fail : RuleResult.pass,
      mandatory: mandatory,
      detail: blocked
          ? 'The destination postcode $postcode is on your blocked list (matches "$matchedPrefix")'
          : 'The destination postcode $postcode is not on your blocked list',
    );
  }
}
