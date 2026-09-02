import '../enums/platform_type.dart';
import 'job_parser.dart';
import 'parsed_job_data.dart';
import 'parsed_text_utils.dart';

/// Extracts job data from text pulled off the Bolt Driver app's visible UI.
///
/// Bolt's layout and wording differ from Uber's and are equally undocumented
/// and subject to change (spec section 29) — this is a separate adapter, not
/// a copy-paste of [UberJobParser], so each can be tuned independently
/// against real devices without risking the other platform's accuracy.
class BoltJobParser implements JobParser {
  const BoltJobParser();

  @override
  PlatformType get platform => PlatformType.bolt;

  // 'instant'/'flex' (the ride-type badges) are trivially present in every
  // per-card segment by construction — see _cardStart below — and act as
  // the primary signal. The rest are kept for the no-split fallback path.
  static const _jobCardKeywords = [
    'instant',
    'flex',
    'available trips',
    'order',
    'passenger',
    'accept',
    'fare',
    'pickup',
  ];
  static const _pickupKeywords = ['pickup', 'to passenger', 'collect'];
  static const _tripKeywords = ['trip', 'drop', 'dropoff', 'to destination', 'ride'];

  // A real device showed the fallback keyword list above (needed for a
  // genuine single-job card with no "Instant" badge to split on) also
  // matching Bolt's own ride-HISTORY screen — "Accepted by another driver"
  // contains "accept", and that screen legitimately shows past fares too,
  // so `fare != null && keyword match` alone wasn't enough to rule it out.
  // These phrases are specific to that history list (past-ride status, not
  // anything a live offer would ever say) and, if present, mean this is
  // definitely not a job card regardless of what else matched — same
  // "anchor on something unambiguous" lesson as Uber's own stats/receipt
  // screen exclusion.
  static const _historyScreenExclusionPhrases = [
    'you did not respond',
    'accepted by another driver',
    'you declined',
    'you cancelled',
  ];

  // A real device log showed a job whose own swipe-to-reject genuinely
  // failed (unrelated cause — see the nudge-up-before-swipe revert) sitting
  // on screen with "Request expired" printed right alongside its still-intact
  // fare/address/keyword text. Bolt doesn't remove or blank the card when an
  // offer times out, it just adds this label on top — so without this
  // exclusion, jobCardDetected stays true forever for a card that can no
  // longer be swiped (there's nothing left to decide), and the fingerprint
  // "only record on success" logic (see AutomationController._processCard)
  // means a failed swipe against an expired card retries every poll tick
  // indefinitely instead of ever getting marked handled, until the card
  // eventually disappears on its own — wasted repeated swipe attempts for
  // the whole time it lingers.
  static const _expiredCardExclusionPhrases = ['request expired'];

  // REMOVED (2026-08-18): this used to also exclude on 'go offline' / 'see
  // offers here' / 'waiting for offers', on the assumption those only ever
  // appear on the truly-idle dashboard, never alongside a live offer card.
  // A live session proved that assumption wrong — Bolt's "Go offline"
  // toggle and "Waiting for more offers" copy are persistent bottom-of-
  // screen chrome, present regardless of whether a card is showing. Because
  // `_cardStart` splits each card's segment from its own "Instant" line up
  // to the *next* one (or end of string for the last/only card — see
  // [parse]), a single standalone offer or the last card in a stacked list
  // has its segment run all the way through that trailing chrome, so this
  // exclusion silently discarded a genuine, fully-actionable job every
  // time (confirmed via a real device: a job with a real fare, address, and
  // distances — everything [jobCardDetected] otherwise requires — got
  // marked not-detected purely because "Go offline" happened to be swept
  // into its segment). This is exactly what made single/last-in-stack jobs
  // look like a swipe-mechanism failure when the swipe was never even
  // attempted. The original dashboard-phantom-job bug this guarded against
  // is still covered by `distances.isNotEmpty` above (see that comment) —
  // the idle dashboard has no distance figure to spuriously match, so no
  // replacement exclusion is needed here.

  // Exclude the earnings/dashboard summary screen — it shows "Today's
  // earnings" with a fare-like figure and "Available trips" keyword, but
  // no actual pickup/trip distances. Without this exclusion, the dashboard
  // summary gets misread as a live job offer because it has a fare-like
  // figure and the "available trips" keyword.
  static const _dashboardExclusionPhrases = [
    'today\'s earning',
    'today\'s earnings',
    'this week\'s earning',
    'this week\'s earnings',
    'total earning',
    'total earnings',
  ];

  // Bolt's driver home screen always shows the daily earnings summary in
  // the top-centre as exactly "£X.XX Today" (e.g. "£0.00 Today" before the
  // driver starts, "£44.00 Today" after). Confirmed constant — Bolt never
  // shows "Yesterday" or any other day label there, so only "Today" is
  // matched. This persistent top chrome carries a fare-shaped figure, and
  // the rest of the home screen can loosely match a card keyword and even a
  // distance token, so without this exclusion the summary alone sometimes
  // passed every [jobCardDetected] check and was treated as a live job
  // (rejected/accepted) when no card was on screen at all.
  static final RegExp _dailyEarningsSummary =
      RegExp(r'£\s?\d+(?:[.,]\d{1,2})?\s+Today\b', caseSensitive: false);

  // Real device screens showed multiple simultaneous offers ("Available
  // trips" listing more than one card at once). Each card starts with this
  // ride-type badge on its own line, so splitting here is what lets every
  // card be parsed and later acted on independently — critically, so the
  // accept/reject action can target the exact card that was evaluated
  // instead of "whichever offer happens to be first on screen" (see
  // docs/parser-design.md for the incident that made this necessary).
  static final RegExp _cardStart = RegExp(r'^Instant$', multiLine: true);

  @override
  List<ParsedJobData> parse(String rawText) {
    final starts = _cardStart.allMatches(rawText).map((m) => m.start).toList();
    if (starts.isEmpty) {
      return [_parseSegment(rawText)];
    }

    final segments = <String>[];
    for (var i = 0; i < starts.length; i++) {
      final end = i + 1 < starts.length ? starts[i + 1] : rawText.length;
      segments.add(rawText.substring(starts[i], end));
    }
    return segments.map(_parseSegment).toList();
  }

  ParsedJobData _parseSegment(String segment) {
    final lower = segment.toLowerCase();
    final fare = ParsedTextUtils.extractFare(segment);
    final distances = ParsedTextUtils.extractAllDistances(segment);
    // Keyword-only matching false-positives on ordinary dashboard chrome —
    // a real device showed Bolt's home dashboard ("£13.12 Today · Available
    // trips", the day's earnings summary + nav label, no job on screen at
    // all) getting misread as a live offer, because "available trips" is
    // also one of these keywords and the dashboard legitimately has a
    // non-zero fare-shaped figure next to it. A genuine job card always
    // shows at least one route distance (pickup or trip) alongside the
    // fare; the dashboard summary never does, so requiring that too is what
    // actually distinguishes the two — the £/mile: null on every phantom
    // detection was the giveaway this was missing.
    final others = ParsedTextUtils.extractAllFares(segment);
    final jobCardDetected = fare != null &&
        fare > 0 &&
        distances.isNotEmpty &&
        _jobCardKeywords.any(lower.contains) &&
        !_historyScreenExclusionPhrases.any(lower.contains) &&
        !_expiredCardExclusionPhrases.any(lower.contains) &&
        !_dashboardExclusionPhrases.any(lower.contains) &&
        // The dashboard's "£X.XX Today" summary is only excluded when it is
        // the segment's *sole* fare. A [parse] fallback can sweep the summary
        // into the same segment as a genuine single card that lacks an
        // "Instant" badge (no split point), leaving two fares side by side —
        // in that case the summary check must not nuke the real card.
        !(_dailyEarningsSummary.hasMatch(segment) && others.length == 1);
    // Not `extractDurationMinutes` (single first-match) — Bolt's card shows
    // pickup duration before trip duration the same way Uber's does, so
    // taking the first match alone fed only the pickup leg's minutes into
    // the £/hour calculation instead of the real total (see
    // UberVisualUnderstandingEngine's identical fix for the real-device
    // evidence: £77-85/hour computed from pickup-only time, vs. £17-23/hour
    // from the correct pickup+trip total).
    final durations = ParsedTextUtils.extractAllDurations(segment);
    final resolvedDurations = ParsedTextUtils.resolvePickupAndTripDurations(
      segment,
      durations,
      pickupKeywords: _pickupKeywords,
      tripKeywords: _tripKeywords,
    );
    final displayedPoundsPerMile = ParsedTextUtils.extractPerDistanceRate(segment);

    double? pickup;
    double? trip;
    String? pickupAddress;
    String? destinationAddress;
    final unlabeledDistances = <double>[];
    final unlabeledAddresses = <String?>[];

    for (final d in distances) {
      final address = _addressAfter(segment, d.end);
      final isPickup = ParsedTextUtils.hasNearbyKeyword(segment, d.start, _pickupKeywords);
      final isTrip = ParsedTextUtils.hasNearbyKeyword(segment, d.start, _tripKeywords);
      if (isPickup && !isTrip) {
        pickup = d.miles;
        pickupAddress = address;
      } else if (isTrip && !isPickup) {
        trip = d.miles;
        destinationAddress = address;
      } else {
        unlabeledDistances.add(d.miles);
        unlabeledAddresses.add(address);
      }
    }

    // Same fragile single/double-unlabeled fallback as UberJobParser; kept
    // duplicated (not shared) so the two platforms can diverge safely if a
    // future device sample shows Bolt orders them differently. The address
    // captured alongside each distance rides along with the same fallback
    // so pickup/destination stay paired with the right figure.
    if (trip == null && unlabeledDistances.isNotEmpty) {
      if (unlabeledDistances.length == 1) {
        trip = unlabeledDistances.first;
        destinationAddress ??= unlabeledAddresses.first;
      } else {
        pickup ??= unlabeledDistances[0];
        pickupAddress ??= unlabeledAddresses[0];
        trip = unlabeledDistances[1];
        destinationAddress ??= unlabeledAddresses[1];
      }
    }

    // Extracted directly from the already-resolved destination address
    // string, not positionally from the whole segment — more precise than
    // guessing since [destinationAddress] is already known to be the trip
    // leg's own address, not the pickup's.
    final destinationAddressPostcodes =
        destinationAddress != null ? ParsedTextUtils.extractAllPostcodes(destinationAddress) : const [];
    final destinationPostcode =
        destinationAddressPostcodes.isEmpty ? null : destinationAddressPostcodes.first.outwardCode;

    return ParsedJobData(
      fare: fare,
      tripDistanceMiles: trip,
      pickupDistanceMiles: pickup,
      estimatedDurationMinutes: resolvedDurations.totalMinutes,
      pickupAddress: pickupAddress,
      destinationAddress: destinationAddress,
      destinationPostcode: destinationPostcode,
      displayedPoundsPerMile: displayedPoundsPerMile,
      rawText: segment,
      jobCardDetected: jobCardDetected,
    );
  }

  /// The first non-blank line after a distance token's end position — Bolt
  /// always follows "<time> • <distance>" with the corresponding address on
  /// the next line. Used both as the human-readable address and as the
  /// unique anchor text the native side swipes/taps on, since a fare or
  /// distance figure alone is not guaranteed unique across simultaneous
  /// offers but a street address effectively always is.
  String? _addressAfter(String text, int matchEnd) {
    final rest = text.substring(matchEnd);
    for (final line in rest.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}
