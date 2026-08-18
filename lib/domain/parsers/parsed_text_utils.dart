import '../services/distance_conversion_service.dart';

/// Shared, currency/unit-tolerant text extraction helpers used by every
/// [JobParser] implementation (spec section 8/38). Kept deliberately
/// conservative: every method returns null rather than guessing when the
/// input doesn't clearly match, per the "do not guess" safety rule.
class ParsedTextUtils {
  const ParsedTextUtils._();

  // £12.50 | £12 | £12,50 | 12.50 GBP | GBP 12.50
  static final RegExp _poundPrefixed =
      RegExp(r'£\s?(\d+(?:[.,]\d{1,2})?)');
  static final RegExp _gbpSuffixed =
      RegExp(r'(\d+(?:[.,]\d{1,2})?)\s?GBP', caseSensitive: false);
  static final RegExp _gbpPrefixed =
      RegExp(r'GBP\s?(\d+(?:[.,]\d{1,2})?)', caseSensitive: false);

  // 5.2 mi | 5.2 miles | 5 miles | 8.4 km | 8.4 kilometres
  static final RegExp _distanceToken = RegExp(
    r'(\d+(?:\.\d+)?)\s?(miles|mile|mi|kilometres|kilometers|kilometre|kilometer|km)\b',
    caseSensitive: false,
  );

  // £1.03/mi | £1.03 /mi | £0.85/mile | £0.64/km — a rate already computed
  // and displayed by the platform itself (confirmed on a real device: Bolt
  // shows this on every job card), distinct from a plain fare amount.
  static final RegExp _perDistanceRate = RegExp(
    r'£\s?(\d+(?:[.,]\d{1,2})?)\s?/\s?(miles|mile|mi|kilometres|kilometers|kilometre|kilometer|km)\b',
    caseSensitive: false,
  );

  // 18 min | 18 mins | 18 minutes | 45 minutes
  static final RegExp _durationToken = RegExp(
    r'(\d+)\s?(min|mins|minute|minutes)\b',
    caseSensitive: false,
  );

  // LE2 6BD | SW1A 1AA | M1 1AE | B33 8TH — standard UK postcode format
  // (outward code: 1-2 letters, 1-2 digits, optional trailing letter; inward
  // code: 1 digit + 2 letters). Captures the outward code separately since
  // that's what a driver actually blocks by area/district (e.g. "LE4"), not
  // the full postcode.
  static final RegExp _postcodeToken = RegExp(
    r'\b([A-Z]{1,2}\d[A-Z\d]?)\s?(\d[A-Z]{2})\b',
    caseSensitive: false,
  );

  /// Fares this large are essentially always a dropped decimal point from
  /// OCR (a real device read "£7.07" as "£707" — the "." simply didn't
  /// render/recognize) rather than a genuine single trip; UK taxi/rideshare
  /// fares don't realistically reach this high. Treating them as
  /// unreliable (null) rather than face value follows the same "never
  /// guess" principle as the missing-currency-marker case below — without
  /// this cap, an inflated fare produces an inflated £/mile that clears
  /// almost any threshold, so a corrupted OCR read could silently look
  /// like a great job worth accepting instead of data that can't be
  /// trusted at all.
  static const double _maxPlausibleFare = 200.0;

  /// Extracts the first clearly currency-marked amount (£ or GBP). A bare
  /// number with no currency marker is never treated as a fare — that's how
  /// distance figures like "12.5" would get misread as money.
  static double? extractFare(String text) {
    for (final pattern in [_poundPrefixed, _gbpSuffixed, _gbpPrefixed]) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final value = _parseDecimal(match.group(1)!);
        if (value != null && value > _maxPlausibleFare) return null;
        return value;
      }
    }
    return null;
  }

  /// Finds every distance token in [text] with its match position and
  /// normalized miles value, so callers can use surrounding words (e.g.
  /// "Pickup", "Trip") to tell pickup distance apart from trip distance.
  static List<DistanceMatch> extractAllDistances(String text) {
    final matches = <DistanceMatch>[];
    for (final m in _distanceToken.allMatches(text)) {
      final raw = _parseDecimal(m.group(1)!);
      if (raw == null) continue;
      final unit = m.group(2)!.toLowerCase();
      final isKm = unit.startsWith('k');
      final miles = isKm ? DistanceConversionService.kilometresToMiles(raw) : raw;
      matches.add(DistanceMatch(miles: miles, start: m.start, end: m.end, rawUnit: unit));
    }
    return matches;
  }

  /// The platform's own displayed £/mile (or £/km, normalized to £/mile) —
  /// see [ParsedJobData.displayedPoundsPerMile] for why this is preferred
  /// over deriving one from fare and distance when the platform already
  /// shows it directly. Returns the first match, same "don't guess when
  /// ambiguous" behavior as [extractFare].
  static double? extractPerDistanceRate(String text) {
    final match = _perDistanceRate.firstMatch(text);
    if (match == null) return null;
    final raw = _parseDecimal(match.group(1)!);
    if (raw == null) return null;
    final unit = match.group(2)!.toLowerCase();
    final isKm = unit.startsWith('k');
    // Converting a *rate* (inverse of distance), not a distance, so this is
    // multiplication by km-per-mile, not [DistanceConversionService]'s own
    // distance-to-distance conversion.
    return isKm ? raw * DistanceConversionService.milesToKilometres(1) : raw;
  }

  /// Finds every duration token in [text] with its match position, so
  /// callers can tell a pickup leg's duration apart from the trip leg's the
  /// same way [extractAllDistances] already does — see
  /// [resolvePickupAndTripDurations] for why taking just the first match
  /// (the old behaviour) was a real bug, not just imprecise.
  static List<DurationMatch> extractAllDurations(String text) {
    final matches = <DurationMatch>[];
    for (final m in _durationToken.allMatches(text)) {
      final minutes = int.tryParse(m.group(1)!);
      if (minutes == null) continue;
      matches.add(DurationMatch(minutes: minutes, start: m.start, end: m.end));
    }
    return matches;
  }

  /// Finds every UK postcode in [text] with its match position and outward
  /// code (e.g. "LE2" from "LE2 6BD"). A job card typically shows two full
  /// addresses — pickup and destination — each with its own postcode.
  static List<PostcodeMatch> extractAllPostcodes(String text) {
    final matches = <PostcodeMatch>[];
    for (final m in _postcodeToken.allMatches(text)) {
      final outward = m.group(1)?.toUpperCase();
      if (outward == null) continue;
      matches.add(PostcodeMatch(outwardCode: outward, start: m.start, end: m.end));
    }
    return matches;
  }

  /// The destination's postcode specifically (for [PostcodeBlocklistRule]) —
  /// never the pickup's. Same positional convention as every other
  /// pickup-vs-trip resolution in this file: a card showing exactly one
  /// address is assumed to be the destination (no separate pickup address
  /// shown); a card showing two is assumed [pickup, destination] in that
  /// order, since that's the order every real sample (Uber and Bolt both)
  /// showed this session. Returns null rather than guessing when neither
  /// case clearly applies (more than 2 postcodes found — ambiguous).
  static String? resolveDestinationPostcode(List<PostcodeMatch> postcodes) {
    if (postcodes.isEmpty || postcodes.length > 2) return null;
    return postcodes.last.outwardCode;
  }

  /// Looks up to [window] characters before a distance match for a keyword,
  /// case-insensitively (e.g. "Pickup 1.8 mi" -> keyword "pickup" found).
  static bool hasNearbyKeyword(String text, int matchStart, List<String> keywords, {int window = 20}) {
    final start = (matchStart - window).clamp(0, text.length);
    final context = text.substring(start, matchStart).toLowerCase();
    return keywords.any(context.contains);
  }

  /// Turns every raw [DistanceMatch] a screen produced into (pickup, trip),
  /// using nearby keywords to tell them apart and falling back to position
  /// order when neither is labeled. Shared by every caller that needs this
  /// — [UberVisualUnderstandingEngine] used to instead take
  /// `distances.first` unconditionally, which silently grabbed the pickup
  /// leg's (usually shorter) distance as if it were the trip distance on
  /// every card shaped like Uber's ("5 min (1.3 mi)" pickup listed before
  /// "11 mins (2.7 mi)" trip) — inflating computed £/mile enough to clear
  /// a threshold a driver had deliberately set higher, and directly causing
  /// jobs to be auto-accepted that shouldn't have been.
  ///
  /// Fragile fallback, not a proven rule: exactly one unlabeled distance is
  /// assumed to be the trip distance (the common single-distance card); two
  /// unlabeled distances are assumed to be [pickup, trip] in that order,
  /// since that's the order every real Uber sample this session showed.
  static ResolvedDistances resolvePickupAndTripDistances(
    String text,
    List<DistanceMatch> distances, {
    required List<String> pickupKeywords,
    required List<String> tripKeywords,
  }) {
    if (distances.isEmpty) return const ResolvedDistances(pickup: null, trip: null);

    double? pickup;
    double? trip;
    final unlabeled = <double>[];

    for (final d in distances) {
      final isPickup = hasNearbyKeyword(text, d.start, pickupKeywords);
      final isTrip = hasNearbyKeyword(text, d.start, tripKeywords);
      if (isPickup && !isTrip) {
        pickup = d.miles;
      } else if (isTrip && !isPickup) {
        trip = d.miles;
      } else {
        unlabeled.add(d.miles);
      }
    }

    if (trip == null && unlabeled.isNotEmpty) {
      if (unlabeled.length == 1) {
        trip = unlabeled.first;
      } else {
        pickup ??= unlabeled[0];
        trip = unlabeled[1];
      }
    }

    return ResolvedDistances(pickup: pickup, trip: trip);
  }

  /// Same pickup/trip resolution as [resolvePickupAndTripDistances], for
  /// duration instead of distance — a real device proved this matters just
  /// as much: [extractDurationMinutes] (the single-match method this
  /// replaced) always took the *first* duration in the text, which on
  /// Uber's card layout ("4 min (0.9 mi)" pickup leg listed before "14 mins
  /// (4.1 mi)" trip leg) is the pickup duration, not the trip duration. That
  /// silently fed a 3-4 minute pickup-only duration into the £/hour
  /// calculation instead of the real total, producing wildly inflated rates
  /// (a real device showed £85.40/hour and £77.40/hour computed this way,
  /// for jobs whose correct rate — fare ÷ (pickup+trip time) — was £23 and
  /// £17/hour respectively) that could pass a driver's threshold when the
  /// job was actually not worth accepting.
  static ResolvedDurations resolvePickupAndTripDurations(
    String text,
    List<DurationMatch> durations, {
    required List<String> pickupKeywords,
    required List<String> tripKeywords,
  }) {
    if (durations.isEmpty) return const ResolvedDurations(pickup: null, trip: null);

    int? pickup;
    int? trip;
    final unlabeled = <int>[];

    for (final d in durations) {
      final isPickup = hasNearbyKeyword(text, d.start, pickupKeywords);
      final isTrip = hasNearbyKeyword(text, d.start, tripKeywords);
      if (isPickup && !isTrip) {
        pickup = d.minutes;
      } else if (isTrip && !isPickup) {
        trip = d.minutes;
      } else {
        unlabeled.add(d.minutes);
      }
    }

    if (trip == null && unlabeled.isNotEmpty) {
      if (unlabeled.length == 1) {
        trip = unlabeled.first;
      } else {
        pickup ??= unlabeled[0];
        trip = unlabeled[1];
      }
    }

    return ResolvedDurations(pickup: pickup, trip: trip);
  }

  static double? _parseDecimal(String raw) {
    final normalized = raw.replaceAll(',', '.');
    return double.tryParse(normalized);
  }
}

class ResolvedDistances {
  const ResolvedDistances({required this.pickup, required this.trip});
  final double? pickup;
  final double? trip;
}

class ResolvedDurations {
  const ResolvedDurations({required this.pickup, required this.trip});
  final int? pickup;
  final int? trip;

  /// The figure that actually belongs in [TaxiJob.estimatedDurationMinutes]
  /// — the driver's real total time commitment to this job, pickup leg
  /// included, matching the £/hour worked example a driver would do by
  /// hand: (pickup + trip) minutes, or just trip minutes if pickup was
  /// never found (never guesses a pickup time that wasn't actually read).
  int? get totalMinutes {
    if (trip == null) return null;
    return pickup == null ? trip : pickup! + trip!;
  }
}

class DistanceMatch {
  const DistanceMatch({
    required this.miles,
    required this.start,
    required this.end,
    required this.rawUnit,
  });

  final double miles;
  final int start;
  final int end;
  final String rawUnit;
}

class DurationMatch {
  const DurationMatch({
    required this.minutes,
    required this.start,
    required this.end,
  });

  final int minutes;
  final int start;
  final int end;
}

class PostcodeMatch {
  const PostcodeMatch({
    required this.outwardCode,
    required this.start,
    required this.end,
  });

  final String outwardCode;
  final int start;
  final int end;
}
