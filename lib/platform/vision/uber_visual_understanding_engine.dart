import 'dart:io';
import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/errors/failures.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/result.dart';
import '../../domain/parsers/parsed_text_utils.dart';
import '../../domain/vision/uber_offer_visual_model.dart';
import 'card_icon_locator.dart';
import 'screen_frame.dart';
import 'uber_visual_surface_provider.dart';

const _tag = 'UberVisualUnderstandingEngine';

/// A [UberOfferVisualModel] bundled with the exact [ScreenFrame] it was
/// computed from — the model's [NormalizedRect]s are only meaningful
/// relative to that specific frame's own pixel dimensions, so anything that
/// needs to act on a detected control (see CoordinateMapper) must carry both
/// together, never the model alone.
class UberVisualAnalysis {
  const UberVisualAnalysis({required this.frame, required this.model});

  final ScreenFrame frame;
  final UberOfferVisualModel model;
}

/// Turns one [ScreenFrame] into a [UberOfferVisualModel] (spec: production
/// visual architecture, section 3). This is the ONLY place OCR output gets
/// interpreted into "is there an offer, and where are its controls" — the
/// decision engine downstream never sees pixels, bounding boxes, or raw OCR
/// text, only the normalized model this produces.
///
/// Deliberately does not use fixed screen coordinates anywhere: every
/// detected region is expressed as a fraction (0.0-1.0) of the captured
/// frame's own width/height (see [NormalizedRect]), computed from that
/// frame's actual dimensions, never a remembered constant from a previous
/// device.
class UberVisualUnderstandingEngine {
  UberVisualUnderstandingEngine({
    UberVisualSurfaceProvider? surfaceProvider,
    TextRecognizer? recognizer,
  })  : _surfaceProvider = surfaceProvider ?? UberVisualSurfaceProvider(),
        _recognizer = recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final UberVisualSurfaceProvider _surfaceProvider;
  final TextRecognizer _recognizer;

  // Every real-device sample of Uber's job-offer card showed its accept
  // button worded "Confirm" (Exclusive fares) or "Match" (standard/
  // Priority) — the one thing genuinely unique to a live, actionable offer
  // (see uber_job_parser.dart for the same evidence driving its own keyword
  // list, and why looser words like "trip"/"fare"/"rider" false-positived
  // on the driver app's own stats and receipt screens).
  static const _acceptKeywords = ['confirm', 'match'];

  // The decline "X" carries no text or content-description at all (also
  // confirmed via a real device's `uiautomator dump`), so it can never be
  // found by keyword search the way the accept control can. Every sample
  // showed the same layout: a vehicle-type row (containing "Uber" — UberX,
  // Uber Comfort, etc. — the one word no other card text ever contains)
  // sharing its row with the X near the frame's right edge — used as the
  // row to search for the icon's actual pixels (see [CardIconLocator]),
  // not to guess its position from a fixed offset.
  static const _vehicleRowKeyword = 'uber';

  // Same lists as [UberJobParser] — kept in sync since both read the same
  // card layout ("5 min (1.3 mi)" pickup leg listed before "11 mins (2.7
  // mi)" trip leg) and must resolve pickup vs trip distance identically.
  static const _pickupKeywords = ['pickup', 'pick-up', 'to rider', 'collect'];
  static const _tripKeywords = ['trip', 'drop', 'dropoff', 'to destination', 'journey'];

  // A real driver reported jobs being "detected" and rejected while Uber
  // wasn't even online — real device `uiautomator dump`s of the driver
  // app's own home dashboard (both the offline and the idle-online state)
  // confirmed why: that screen legitimately contains a fare figure (the
  // day's running earnings total, e.g. "£1.55") and can contain a line
  // whose OCR text happens to contain "confirm" or "match" as a substring
  // (promo/gamification cards, e.g. "Unlock Gold" progress content), which
  // is all [_findAcceptControl] and the fare check above require. Every one
  // of ~40 real dumps of the dashboard (in every state: offline, online,
  // idle-online with weekly-summary card) carries at least one of these
  // phrases, and NONE of the real live-offer dumps ever carry any of
  // them — the offer screen is a full takeover with no dashboard chrome
  // behind it. Same "anchor on something unambiguous" fix as
  // BoltJobParser's own history-screen exclusion.
  static const _dashboardExclusionPhrases = [
    "you're online",
    "you're offline",
    'unable to go offline',
    'unlock gold',
  ];

  /// Captures and analyzes in one call, returning the frame alongside the
  /// model — callers that need to act on a detected control (the
  /// [CoordinateMapper] does) need the frame's own width/height to convert
  /// [NormalizedRect] back into real pixels, and re-fetching a NEW frame at
  /// that point would defeat the point of revalidating against what was
  /// actually just analyzed (spec: production visual architecture, section
  /// 9 — act on the frame that was validated, not a fresher one nothing has
  /// looked at yet).
  ///
  /// [includeRejectControl] defaults to true for the debug screen's
  /// calibration display, but production ([AutomationController]) passes
  /// false — see [_findRejectControl]'s doc comment for why locating that
  /// icon's exact pixels is pure latency cost now that nothing taps it.
  /// [cropped] similarly defaults to false (full frame, needed for the
  /// debug screen's real on-screen coordinates) — production passes true to
  /// use [UberVisualSurfaceProvider.captureFrame]'s cropped capture.
  Future<Result<UberVisualAnalysis>> analyzeCurrentScreen({
    bool includeRejectControl = true,
    bool cropped = false,
  }) async {
    final frameResult = await _surfaceProvider.captureFrame(cropped: cropped);
    return frameResult.when(
      ok: (frame) async {
        final modelResult = await analyzeFrame(frame, includeRejectControl: includeRejectControl);
        return modelResult.when(
          ok: (model) => Result.ok(UberVisualAnalysis(frame: frame, model: model)),
          err: (f) => Result.err(f),
        );
      },
      err: (f) async => Result.err(f),
    );
  }

  /// Exposed separately from [analyzeCurrentScreen] so stored test frames
  /// (spec section 19) can be run through the exact same recognition +
  /// scoring logic without needing a live device or a real Uber offer.
  Future<Result<UberOfferVisualModel>> analyzeFrame(ScreenFrame frame, {bool includeRejectControl = true}) async {
    File? tempFile;
    try {
      final tempDir = await getTemporaryDirectory();
      final uniqueName = 'jobfilter_vision_${DateTime.now().microsecondsSinceEpoch}.jpg';
      tempFile = File('${tempDir.path}/$uniqueName');
      await tempFile.writeAsBytes(frame.bytes, flush: true);

      final recognizedText = await _recognizer.processImage(InputImage.fromFilePath(tempFile.path));
      final model = await _buildModel(recognizedText, frame, includeRejectControl: includeRejectControl);
      AppLogger.instance.debug(
        _tag,
        'analyzeFrame: detected=${model.detected} confidence=${model.confidence.toStringAsFixed(2)} '
        'fare=${model.fare} accept=${model.acceptControl != null} reject=${model.rejectControl != null}',
      );
      // A real device showed a fare found with the accept keyword ("confirm"/
      // "match") never found, for the entire lifetime of a real job — but
      // the raw OCR text that would explain *why* (what the button's actual
      // wording was) was only ever logged when detection succeeded, so this
      // exact failure left no evidence to diagnose from. Logged here
      // unconditionally whenever a fare is present but the accept control
      // isn't, so the next occurrence is diagnosable from logs alone.
      if (model.fare != null && model.fare! > 0 && model.acceptControl == null) {
        AppLogger.instance.debug(
          _tag,
          'analyzeFrame: fare present but no accept control found — raw OCR text:\n${model.rawText}',
        );
      }
      return Result.ok(model);
    } catch (e) {
      AppLogger.instance.error(_tag, 'analyzeFrame failed: $e');
      return Result.err(AutomationFailure('Visual analysis failed: $e'));
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<UberOfferVisualModel> _buildModel(
    RecognizedText recognizedText,
    ScreenFrame frame, {
    required bool includeRejectControl,
  }) async {
    final rawText = recognizedText.text;
    final fare = ParsedTextUtils.extractFare(rawText);
    final distances = ParsedTextUtils.extractAllDistances(rawText);
    final durations = ParsedTextUtils.extractAllDurations(rawText);

    // NOT `distances.first` — Uber's card lists the pickup leg before the
    // trip leg ("5 min (1.3 mi)" then "11 mins (2.7 mi)"), so taking the
    // first distance unconditionally silently used the pickup distance as
    // the trip distance on every real job this session, inflating the
    // computed £/mile enough to clear a threshold that should have failed
    // and causing wrong auto-accepts. Same resolution logic as
    // UberJobParser (the plain-text parser this replaced for live
    // detection), which never had this bug.
    final resolvedDistances = ParsedTextUtils.resolvePickupAndTripDistances(
      rawText,
      distances,
      pickupKeywords: _pickupKeywords,
      tripKeywords: _tripKeywords,
    );

    // Same class of bug as the distance one above, for duration instead —
    // a real device's own worked-out math confirmed it exactly: taking the
    // first duration match (the old behaviour) grabbed the 3-4 minute
    // *pickup* leg's duration and fed that alone into the £/hour
    // calculation, producing £85.40/hour and £77.40/hour for jobs whose
    // real rate (fare ÷ total pickup+trip time) was £23 and £17/hour.
    final resolvedDurations = ParsedTextUtils.resolvePickupAndTripDurations(
      rawText,
      durations,
      pickupKeywords: _pickupKeywords,
      tripKeywords: _tripKeywords,
    );

    // For PostcodeBlocklistRule — Uber's card shows a pickup address and a
    // destination address, each with its own postcode, in that order (same
    // layout as the distance/duration figures above), so the last one found
    // is the destination's.
    final postcodes = ParsedTextUtils.extractAllPostcodes(rawText);
    final destinationPostcode = ParsedTextUtils.resolveDestinationPostcode(postcodes);

    final allLines = [
      for (final block in recognizedText.blocks) ...block.lines,
    ];

    final acceptControl = _findAcceptControl(allLines, frame);
    final rejectControl =
        includeRejectControl ? await _findRejectControl(allLines, frame, acceptControl) : null;

    // Weighted, not a simple count: the accept control is the single
    // strongest signal (a real fare or distance figure can plausibly show
    // up on other screens, as uber_job_parser.dart's own comments document
    // from a real device — the driver app's stats/earnings and past-trip
    // receipt screens both legitimately mention a fare). Section 24 of the
    // architecture: only a high-confidence read may ever drive automation;
    // this score is what a future action executor would gate on.
    var confidence = 0.0;
    if (fare != null && fare > 0) confidence += 0.3;
    if (distances.isNotEmpty) confidence += 0.2;
    if (acceptControl != null) confidence += 0.5;

    final lowerText = rawText.toLowerCase();
    final isDashboardScreen = _dashboardExclusionPhrases.any(lowerText.contains);
    final detected = fare != null && fare > 0 && acceptControl != null && !isDashboardScreen;
    if (fare != null && fare > 0 && acceptControl != null && isDashboardScreen) {
      AppLogger.instance.debug(
        _tag,
        '_buildModel: fare + accept keyword matched but rawText looks like the '
        'home dashboard (offline/idle-online), not a live offer — ignoring',
      );
    }

    NormalizedRect? offerRegion;
    if (acceptControl != null) {
      offerRegion = rejectControl != null
          ? acceptControl.bounds.union(rejectControl.bounds)
          : acceptControl.bounds;
    }

    return UberOfferVisualModel(
      detected: detected,
      confidence: confidence.clamp(0.0, 1.0),
      timestamp: frame.timestamp,
      fare: fare,
      tripDistanceMiles: resolvedDistances.trip,
      pickupDistanceMiles: resolvedDistances.pickup,
      durationMinutes: resolvedDurations.totalMinutes,
      destinationPostcode: destinationPostcode,
      offerRegion: offerRegion,
      acceptControl: acceptControl,
      rejectControl: rejectControl,
      rawText: rawText,
    );
  }

  VisualControl? _findAcceptControl(List<TextLine> lines, ScreenFrame frame) {
    for (final line in lines) {
      final lowerText = line.text.toLowerCase();
      final matched = _acceptKeywords.where(lowerText.contains);
      if (matched.isEmpty) continue;
      return VisualControl(
        semanticRole: SemanticRole.accept,
        bounds: _normalize(line.boundingBox, frame),
        confidence: 0.9,
        evidence: 'OCR line "${line.text}" matched keyword "${matched.first}"',
      );
    }
    return null;
  }

  /// The vehicle-type OCR line ("UberX", "Uber Comfort", etc.) anchors
  /// which *row* the reject icon shares, but it carries no text of its own
  /// to OCR — a fixed pixel offset from that row was tried first and proved
  /// unreliable (varied 0.46-0.59 across real jobs this session, and
  /// directly caused wrong actions). This instead reads the icon's actual
  /// left/right edges from the frame's own decoded pixels
  /// ([CardIconLocator]) — real computer vision on top of the OCR anchor,
  /// not a positional guess.
  ///
  /// Only called when a caller actually needs the icon's exact bounds (the
  /// debug screen's calibration overlay). Decoding raw RGBA pixels and
  /// scanning columns for darkness is real added latency on top of OCR — a
  /// real device showed the decision badge (see
  /// [AutomationController._processUberVisual]) appearing noticeably late,
  /// sometimes after the job had already disappeared. Production has no use
  /// for this control's exact position at all: nothing taps it, and neither
  /// [detected] nor [confidence] factor it in — the ACCEPT/REJECT badge is
  /// driven entirely by the £/mile math, not by finding this icon.
  Future<VisualControl?> _findRejectControl(
    List<TextLine> lines,
    ScreenFrame frame,
    VisualControl? acceptControl,
  ) async {
    for (final line in lines) {
      if (!line.text.toLowerCase().contains(_vehicleRowKeyword)) continue;

      final box = line.boundingBox;
      // Padded by half the OCR line's own height on each side: a real
      // device's ground-truth tap location showed the icon isn't
      // necessarily aligned with the vehicle-badge text's own baseline, and
      // a too-narrow scan band risks averaging in enough background pixels
      // per column to wash out the icon's darkness signal entirely.
      final rowPadding = box.height / 2;
      final icon = await CardIconLocator.findIconRightOfRow(
        jpegBytes: frame.bytes,
        frameWidth: frame.width,
        frameHeight: frame.height,
        rowTop: box.top - rowPadding,
        rowBottom: box.bottom + rowPadding,
      );
      if (icon == null) {
        // Never fall back to a fixed-offset guess here (spec section 24) —
        // a real device proved that guess directly caused a wrong swipe.
        AppLogger.instance.debug(
          _tag,
          '_findRejectControl: no icon found by pixel analysis near vehicle-type row "${line.text}"',
        );
        return null;
      }

      final estimate = NormalizedRect(
        left: (icon.left / frame.width).clamp(0.0, 1.0),
        top: (box.top / frame.height).clamp(0.0, 1.0),
        right: (icon.right / frame.width).clamp(0.0, 1.0),
        bottom: (box.bottom / frame.height).clamp(0.0, 1.0),
      );

      // Sanity check, not a guess-avoidance guarantee: the accept control
      // sits far below the vehicle-type row on every real sample, so an
      // estimate landing suspiciously close to it is more likely a bad
      // read than a real second control there.
      if (acceptControl != null &&
          (estimate.centerY - acceptControl.bounds.centerY).abs() < 0.08 &&
          (estimate.centerX - acceptControl.bounds.centerX).abs() < 0.15) {
        AppLogger.instance.warning(
          _tag,
          '_findRejectControl: estimate $estimate too close to accept control '
          '${acceptControl.bounds} — discarding rather than risk confusing the two',
        );
        return null;
      }

      return VisualControl(
        semanticRole: SemanticRole.reject,
        bounds: estimate,
        // Higher than the old fixed-offset guess's — this is measured from
        // the frame's actual pixels, not assumed, though still below the
        // accept control's direct text match.
        confidence: 0.75,
        evidence: 'Icon detected by pixel analysis near vehicle-type row "${line.text}" '
            '(no direct OCR label exists for this icon)',
      );
    }
    return null;
  }

  NormalizedRect _normalize(Rect boundingBox, ScreenFrame frame) {
    return NormalizedRect(
      left: (boundingBox.left / frame.width).clamp(0.0, 1.0),
      top: (boundingBox.top / frame.height).clamp(0.0, 1.0),
      right: (boundingBox.right / frame.width).clamp(0.0, 1.0),
      bottom: (boundingBox.bottom / frame.height).clamp(0.0, 1.0),
    );
  }

  Future<void> dispose() => _recognizer.close();
}
