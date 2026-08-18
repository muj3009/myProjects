import 'package:equatable/equatable.dart';

/// A rectangle expressed as fractions (0.0–1.0) of the FULL display's width
/// and height — never pixels. The same detected control on a 1080x2340
/// Samsung and a 1440x3120 Pixel produces (approximately) the same
/// normalized values, which is what lets the visual model stay device-
/// independent; conversion to real device pixels happens only at the moment
/// a gesture is actually dispatched, against the display metrics current at
/// that moment (spec: production visual architecture, sections 5–6).
class NormalizedRect extends Equatable {
  const NormalizedRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  /// Smallest rect containing both this and [other].
  NormalizedRect union(NormalizedRect other) => NormalizedRect(
        left: left < other.left ? left : other.left,
        top: top < other.top ? top : other.top,
        right: right > other.right ? right : other.right,
        bottom: bottom > other.bottom ? bottom : other.bottom,
      );

  @override
  String toString() =>
      'NormalizedRect(${left.toStringAsFixed(3)}, ${top.toStringAsFixed(3)}, '
      '${right.toStringAsFixed(3)}, ${bottom.toStringAsFixed(3)})';

  @override
  List<Object?> get props => [left, top, right, bottom];
}

/// What a detected control *means*, independent of where it is or what it
/// says. The automation layer acts on roles, never on raw coordinates or
/// exact label text (Uber's accept wording alone already varies between
/// "Confirm" and "Match" on real devices).
enum SemanticRole { accept, reject }

/// One actionable control the visual engine believes exists on screen.
/// [evidence] records *why* the engine believes it (e.g. which OCR line
/// matched, or which layout relationship the estimate came from) so a wrong
/// detection can be diagnosed from logs instead of reverse-engineered.
class VisualControl extends Equatable {
  const VisualControl({
    required this.semanticRole,
    required this.bounds,
    required this.confidence,
    required this.evidence,
  });

  final SemanticRole semanticRole;
  final NormalizedRect bounds;
  final double confidence;
  final String evidence;

  @override
  List<Object?> get props => [semanticRole, bounds, confidence, evidence];
}

/// The visual engine's complete understanding of one screen frame: whether
/// an Uber offer is present, what it says, where its controls are, and how
/// sure the engine is. Everything downstream (parser normalization, decision
/// engine, and eventually the action executor) consumes this — no other
/// component re-interprets pixels.
class UberOfferVisualModel extends Equatable {
  const UberOfferVisualModel({
    required this.detected,
    required this.confidence,
    required this.timestamp,
    this.fare,
    this.tripDistanceMiles,
    this.pickupDistanceMiles,
    this.durationMinutes,
    this.destinationPostcode,
    this.offerRegion,
    this.acceptControl,
    this.rejectControl,
    this.rawText = '',
  });

  /// A frame where nothing offer-like was found. Distinct from a capture
  /// failure — the caller knows the screen WAS seen and contained no offer.
  factory UberOfferVisualModel.nothingDetected({required String rawText}) =>
      UberOfferVisualModel(
        detected: false,
        confidence: 0,
        timestamp: DateTime.now(),
        rawText: rawText,
      );

  final bool detected;

  /// 0.0–1.0 aggregate of the independent signals that contributed to
  /// [detected] (fare present, distance present, accept control found,
  /// vehicle row found). Section 24 of the architecture: only high
  /// confidence may ever drive automation; medium is log-only.
  final double confidence;

  final DateTime timestamp;
  final double? fare;
  final double? tripDistanceMiles;
  final double? pickupDistanceMiles;
  final int? durationMinutes;

  /// Outward code only (e.g. "LE4") — see PostcodeBlocklistRule, the only
  /// thing that reads this.
  final String? destinationPostcode;

  /// Bounding region of the offer card itself, when estimable.
  final NormalizedRect? offerRegion;

  final VisualControl? acceptControl;
  final VisualControl? rejectControl;

  /// Full recognized text of the frame — fed to the existing parser layer
  /// so fare/distance normalization stays in one place (JobNormalizer role).
  final String rawText;

  @override
  List<Object?> get props => [
        detected,
        confidence,
        timestamp,
        fare,
        tripDistanceMiles,
        pickupDistanceMiles,
        durationMinutes,
        destinationPostcode,
        offerRegion,
        acceptControl,
        rejectControl,
        rawText,
      ];
}
