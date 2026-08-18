import '../enums/platform_type.dart';
import 'job_parser.dart';
import 'parsed_job_data.dart';
import 'parsed_text_utils.dart';

/// Extracts job data from text pulled off the Uber Driver app's visible UI.
///
/// IMPORTANT: the exact wording/layout Uber uses is not publicly documented
/// and can change at any time (spec section 29). The keyword lists below are
/// a best-effort starting point and are expected to need tuning against a
/// real device — see docs/parser-design.md. This class deliberately contains
/// no coordinates and no assumptions about screen resolution.
class UberJobParser implements JobParser {
  const UberJobParser();

  @override
  PlatformType get platform => PlatformType.uber;

  // A genuine live job offer always shows its accept action verbatim —
  // "Confirm" for Exclusive fares, "Match" for standard/Priority (both
  // confirmed on a real device). Broader words like 'trip', 'rider', 'fare',
  // 'pickup' were tried first but proved unreliable: a real device showed
  // JobFilter treating Uber's own stats/earnings summary ("Net fare £9.31",
  // "See rider fare breakdown") and a past trip's receipt page ("Upfront
  // estimate: £5.65") as live job offers, since both screens legitimately
  // mention non-zero fares and those generic words too — so `fare > 0` alone
  // can't rule them out. Neither screen ever shows "Confirm" or "Match", so
  // anchoring on the accept button itself — the one thing genuinely unique
  // to an active offer — rules both out without a per-screen exclusion list,
  // and is exactly what OCR already needs to find to act on the job anyway.
  static const _jobCardKeywords = ['confirm', 'match'];
  static const _pickupKeywords = ['pickup', 'pick-up', 'to rider', 'collect'];
  static const _tripKeywords = ['trip', 'drop', 'dropoff', 'to destination', 'journey'];

  // Same real-device evidence as UberVisualUnderstandingEngine's identical
  // list: the home dashboard (offline OR idle-online) legitimately shows a
  // non-zero fare (the day's running earnings) and can contain a line whose
  // text happens to contain "confirm" or "match", which is all the keyword
  // check above requires. A real driver reported jobs being detected and
  // rejected while Uber wasn't even online, traced to exactly this — none of
  // ~40 real dumps of a genuine live offer ever carry any of these phrases,
  // since the offer screen is a full takeover with no dashboard chrome
  // behind it.
  static const _dashboardExclusionPhrases = [
    "you're online",
    "you're offline",
    'unable to go offline',
    'unlock gold',
  ];

  @override
  List<ParsedJobData> parse(String rawText) {
    final lower = rawText.toLowerCase();
    final fare = ParsedTextUtils.extractFare(rawText);
    // Keyword-only matching false-positives on ordinary dashboard chrome
    // (e.g. the static "Trip planner" menu item contains "trip", and promo
    // widgets like "Recommended for you £0.00" contain a currency-marked
    // amount). A real job offer always shows a priced (non-zero) fare, so
    // require both — consistent with extractFare's own "never guess without
    // a currency marker" rule.
    final jobCardDetected = fare != null &&
        fare > 0 &&
        _jobCardKeywords.any(lower.contains) &&
        !_dashboardExclusionPhrases.any(lower.contains);

    final distances = ParsedTextUtils.extractAllDistances(rawText);
    final durations = ParsedTextUtils.extractAllDurations(rawText);

    final resolved = ParsedTextUtils.resolvePickupAndTripDistances(
      rawText,
      distances,
      pickupKeywords: _pickupKeywords,
      tripKeywords: _tripKeywords,
    );
    // Not the first duration match alone — see
    // UberVisualUnderstandingEngine's identical fix for the real-device
    // evidence (a job's £/hour computed from pickup-only time alone came out
    // £77-85/hour, versus £17-23/hour from the correct pickup+trip total).
    final resolvedDurations = ParsedTextUtils.resolvePickupAndTripDurations(
      rawText,
      durations,
      pickupKeywords: _pickupKeywords,
      tripKeywords: _tripKeywords,
    );

    // Uber shows one offer at a time (unlike Bolt's simultaneous list), so
    // no per-card splitting is needed here — wrapped in a list purely to
    // satisfy the shared JobParser contract.
    return [
      ParsedJobData(
        fare: fare,
        tripDistanceMiles: resolved.trip,
        pickupDistanceMiles: resolved.pickup,
        estimatedDurationMinutes: resolvedDurations.totalMinutes,
        rawText: rawText,
        jobCardDetected: jobCardDetected,
      ),
    ];
  }
}
