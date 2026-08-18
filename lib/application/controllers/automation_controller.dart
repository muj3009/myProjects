import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/app_logger.dart';
import '../../domain/entities/driver_settings.dart';
import '../../domain/entities/taxi_job.dart';
import '../../domain/enums/job_decision.dart';
import '../../domain/enums/platform_type.dart';
import '../../domain/enums/rule_result.dart';
import '../../domain/parsers/job_parser.dart';
import '../../domain/parsers/parsed_job_data.dart';
import '../../domain/rules/postcode_blocklist_rule.dart';
import '../../domain/services/job_decision_engine.dart';
import '../../domain/services/job_fingerprint_service.dart';
import '../../domain/repositories/job_repository.dart';
import '../../platform/accessibility/accessibility_status.dart';
import '../../platform/automation/automation_method_channel.dart';
import '../../platform/automation/platform_action_executor.dart';
import '../../platform/ocr/ocr_text_provider.dart';
import '../../platform/vision/uber_visual_understanding_engine.dart';
import '../state/providers.dart';
import '../state/settings_controller.dart';
import 'automation_state.dart';

/// Orchestrates the full detect -> parse -> decide -> act -> record loop
/// (spec section 13). Contains no UI code and never touches native APIs
/// directly — those responsibilities are delegated to
/// [AutomationMethodChannel] and [PlatformActionExecutor] respectively, so
/// this class is the same on Android and iOS; only *what it's allowed to do*
/// differs, via [PlatformActionExecutor.canPerformActions].
class AutomationController extends StateNotifier<AutomationState> {
  AutomationController(this._ref)
      : _channel = _ref.read(automationMethodChannelProvider),
        _executor = _ref.read(platformActionExecutorProvider),
        _parsers = _ref.read(jobParsersProvider),
        _engine = _ref.read(decisionEngineProvider),
        _fingerprints = _ref.read(fingerprintServiceProvider),
        _jobRepository = _ref.read(jobRepositoryProvider),
        _ocr = _ref.read(ocrTextProviderProvider),
        _visualEngine = _ref.read(uberVisualUnderstandingEngineProvider),
        super(
          AutomationState(
            unsupportedReason:
                _ref.read(platformActionExecutorProvider).isAutomationSupportedOnThisPlatform
                    ? null
                    : 'Automatic job monitoring is not available on this platform. Use '
                        'Simulation Mode to analyze jobs manually.',
          ),
        );

  final Ref _ref;
  final AutomationMethodChannel _channel;
  final PlatformActionExecutor _executor;
  final Map<PlatformType, JobParser> _parsers;
  final JobDecisionEngine _engine;
  final JobFingerprintService _fingerprints;
  final JobRepository _jobRepository;
  final OcrTextProvider _ocr;
  final UberVisualUnderstandingEngine _visualEngine;
  final Uuid _uuid = const Uuid();

  StreamSubscription<String>? _subscription;
  StreamSubscription<void>? _stopRequestSubscription;
  Timer? _uberPollTimer;
  static const _tag = 'AutomationController';

  /// Fingerprints currently mid-processing in [_processCard] — a real device
  /// showed the same still-unresolved job (its card often includes a live
  /// countdown, so the extracted text never repeats exactly, defeating the
  /// native side's own text-level dedup) get picked up by 2-3 overlapping
  /// poll ticks before the first attempt's accept/reject/counter-offer call
  /// even returned, each one independently swiping the same card. Since
  /// [_fingerprints] is deliberately no longer recorded until an action
  /// succeeds (so a genuinely failed attempt can retry), this is the
  /// narrower guard that actually needs to prevent: two attempts running
  /// *at the same time*, not a failed one being retried on a *later* tick.
  final Set<String> _inFlightFingerprints = {};

  /// Backstop for Uber only — a real device proved the event-driven path
  /// alone (accessibility events) can go 20+ seconds with no event firing
  /// at all even while the driver is actively looking at Uber, and a job
  /// offer that appears and disappears entirely inside one of those silent
  /// gaps is never even attempted, let alone missed after a slow capture.
  /// This runs [_processUberVisual] on a fixed interval regardless of
  /// events, so a gap in Android's own event delivery can no longer hide an
  /// offer completely. Bolt doesn't need this — its native-click automation
  /// already works reliably off the event-driven path alone.
  static const _uberPollInterval = Duration(milliseconds: 400);

  // Phase 0 (this project's earlier investigation) proved Uber's job card
  // exposes no usable accessibility tree content — [_processCard]'s
  // keyword-click path can never work for it. Visual detection is used
  // instead — but, unlike Bolt, JobFilter never dispatches a gesture at
  // Uber's own accept/reject controls; see [_processUberVisual]'s doc
  // comment for why (real-device evidence of what looks like deliberate
  // anti-automation protection on those specific controls). Uber instead
  // gets a small on-screen badge telling the driver ACCEPT/REJECT so they
  // can tap Uber's own button themselves, entirely separately from Bolt's
  // (working, untouched) native-click automation below.

  /// Section 24: only high-confidence detections may ever drive a shown
  /// decision. [UberOfferVisualModel.confidence] is an aggregate of
  /// independent signals (fare present, distance present, accept/reject
  /// control found) — every real job detected this session that had both
  /// controls found also scored the maximum, so requiring near-maximum
  /// confidence here doesn't meaningfully cost real jobs while still
  /// refusing to show a decision on a partial/uncertain read.
  static const _minConfidenceForAutomation = 0.75;

  /// Set by the debug screen's visual-diagnostics "Watch for offer" mode
  /// (see [_VisualDiagnosticsSectionState]) — a real device showed its
  /// `captureScreenFrame` calls intermittently failing with
  /// `ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT` because this loop's own
  /// `takeScreenshot()` calls (fired on every accessibility event, ~every
  /// 800ms) were competing for the same rate-limited native API. Pausing
  /// this loop's captures while a manual diagnostic capture is in flight
  /// eliminates that race; it does not affect production automation, since
  /// nothing else ever sets this.
  bool _diagnosticsPaused = false;

  void pauseForVisualDiagnostics() => _diagnosticsPaused = true;

  void resumeFromVisualDiagnostics() => _diagnosticsPaused = false;

  /// Spec section 4/19 — starts monitoring. No-op (not an error) if already
  /// active, or if this platform doesn't support automation at all.
  Future<void> start() async {
    if (state.isActive || !state.isSupported) return;

    final accessibilityStatus = await _channel.getAccessibilityStatus();
    if (accessibilityStatus != AccessibilityStatus.enabled) {
      state = state.copyWith(
        statusMessage: 'Accessibility Service is not enabled — open Permissions to set up.',
        debug: state.debug.copyWith(accessibilityConnected: false),
      );
      return;
    }

    await _channel.startForegroundMonitoring();
    await _channel.showOnlineBubble();
    await _ref.read(settingsControllerProvider.notifier).setAutomationEnabled(true);

    _subscription = _channel.detectedTextEvents().listen(
          _handleDetectedText,
          onError: (Object e) => AppLogger.instance.error(_tag, 'Event stream error: $e'),
        );

    // Spec section 25: the persistent notification's STOP action must be as
    // effective as the in-app emergency stop button.
    _stopRequestSubscription = _channel.stopRequestedFromNotificationEvents().listen(
          (_) => stop(),
          onError: (Object e) => AppLogger.instance.error(_tag, 'Control event stream error: $e'),
        );

    _uberPollTimer = Timer.periodic(_uberPollInterval, (_) => _pollUberOffer());

    state = AutomationState(
      isActive: true,
      statusMessage: 'Monitoring...',
      debug: state.debug.copyWith(accessibilityConnected: true),
    );
    AppLogger.instance.info(_tag, 'Automation started');
  }

  /// Spec section 19 — emergency stop. Cancels the event subscription
  /// immediately so no further detected text can trigger an action, then
  /// tells the native side to stop the foreground service.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _stopRequestSubscription?.cancel();
    _stopRequestSubscription = null;
    _uberPollTimer?.cancel();
    _uberPollTimer = null;
    await _channel.stopForegroundMonitoring();
    await _channel.hideOnlineBubble();
    await _ref.read(settingsControllerProvider.notifier).setAutomationEnabled(false);

    state = state.copyWith(isActive: false, statusMessage: 'Automation is off');
    AppLogger.instance.info(_tag, 'Automation stopped');
  }

  /// Fixed-interval tick — see [_uberPollInterval]'s doc comment for why
  /// this exists alongside the event-driven path. Reuses
  /// [_processUberVisual] exactly as the event-driven path does, so a job
  /// this tick happens to catch gets identical treatment (confidence gate,
  /// dedup, badge) either way; the native capture layer's own
  /// `isMonitoredPackageForeground` check keeps this cheap when Uber isn't
  /// around at all, rather than needing a foreground check here first.
  Future<void> _pollUberOffer() async {
    if (!state.isActive || _diagnosticsPaused) return;
    final settings = _ref.read(settingsControllerProvider);
    await _processUberVisual(settings);
  }

  Future<void> _handleDetectedText(String rawText) async {
    // Safety check 8 (spec section 15): automation may have been switched
    // off between the event firing and this handler running.
    if (!state.isActive) return;
    if (_diagnosticsPaused) {
      // This was previously silent — a real device showed a driver
      // confused why "many jobs came" produced no automatic action at all,
      // which turned out to be the debug screen's own "Watch for offer"
      // leaving this set for the duration of its own capture. Now visible
      // in logs instead of a silent no-op.
      AppLogger.instance.warning(
        _tag,
        'Detected text event skipped — automatic loop paused for visual diagnostics '
        '(debug screen "Watch for offer" is active)',
      );
      return;
    }

    try {
      final foregroundPackage = await _channel.getForegroundPackageName();
      final platform = _resolvePlatform(foregroundPackage);

      state = state.copyWith(
        debug: state.debug.copyWith(
          foregroundPackage: foregroundPackage,
          lastDetectedText: rawText,
        ),
      );

      // Safety check 1: correct platform detected.
      if (platform == PlatformType.unknown) return;

      final settings = _ref.read(settingsControllerProvider);
      if (!settings.platformSelection.allows(platform)) return;

      // Uber goes through visual detection + swipe entirely — see
      // [_processUberVisual] and the class-level comment on
      // [_uberSwipeY]. Never falls through to the keyword/native-click path
      // below, which Phase 0 proved cannot work for Uber.
      if (platform == PlatformType.uber) {
        await _processUberVisual(settings);
        return;
      }

      final parser = _parsers[platform];
      if (parser == null) return;

      // A single screen can show more than one simultaneous offer — observed
      // on a real device, Bolt's "Available trips" list. Each is parsed and
      // processed independently below so an accept/reject action always
      // targets the exact card it was decided about, never just "whichever
      // offer happens to be first on screen" (see docs/parser-design.md for
      // the incident — a real job got swiped the wrong way — that made this
      // necessary).
      final parsedCards = parser.parse(rawText);
      state = state.copyWith(debug: state.debug.copyWith(parserUsed: parser.runtimeType.toString()));

      // A real device showed processing these one at a time (awaiting each
      // card's full accept/reject/counter-offer round trip, retries
      // included, before even starting the next) let a later card in the
      // same stack sit untouched for hundreds of milliseconds — long enough
      // for another driver to take it first. Reject/counter-offer never
      // commit the driver to anything, so there's no reason those need to
      // be serialized; only accept does (see [_BatchAcceptGuard]), which is
      // enforced independently of ordering here.
      final acceptGuard = _BatchAcceptGuard();
      await Future.wait(
        parsedCards.map((card) => _processCard(card, platform, settings, acceptGuard)),
      );
    } catch (e, stackTrace) {
      // Spec section 35: never crash on a bad job. Record an error job and
      // keep monitoring.
      AppLogger.instance.error(_tag, 'Failed to process detected text: $e\n$stackTrace');
      state = state.copyWith(statusMessage: 'Monitoring... (last job failed to process)');
    }
  }

  /// Uber-only: detect via [_visualEngine] (screenshot + OCR + control
  /// bounds — see docs/android-automation.md and this session's Phase 0
  /// finding), decide, and show a small ACCEPT/REJECT badge for the driver
  /// to act on themselves. JobFilter never dispatches a gesture at Uber's
  /// own controls — real-device testing this session proved
  /// `AccessibilityService.dispatchGesture()` is silently ignored by them
  /// (a static tap did nothing; a small drag got captured by the map
  /// underneath instead), while the button clearly does respond to a real
  /// touch (`adb shell input tap` accepted a live job at the identical
  /// coordinate). That gap looks like deliberate, targeted anti-automation
  /// protection on this specific control — plausibly against job-sniping
  /// bots, a known problem in rideshare — not a bug in our dispatch code,
  /// and defeating it would risk the driver's account being flagged. Uber
  /// automation was deliberately scoped back to "detect + tell the driver"
  /// for this reason; Bolt's native click-based automation (unaffected by
  /// any of this) is untouched below in [_processCard].
  ///
  /// Runs once per detection event rather than looping internally: each
  /// stacked card only becomes visible when the driver manually swipes to
  /// it, which itself fires a fresh accessibility event that re-enters this
  /// method — so every card in a stack gets its own badge in turn, without
  /// this method needing to guess when to re-check.
  ///
  /// [_processingUberVisual] guards against two calls overlapping — the
  /// poll timer (see [_pollUberOffer]) and a genuine accessibility event
  /// can land within milliseconds of each other. Without this, both would
  /// call [_visualEngine.analyzeCurrentScreen]; the surface provider's own
  /// single-flight guard makes the second one fail fast with no frame,
  /// which then hid the badge the *first* call was about to show — a real
  /// device showed exactly this: the badge added and removed again within
  /// ~20ms, too fast to ever be seen. Skipping the second call entirely
  /// (touching neither show nor hide) instead of racing it removes that.
  bool _processingUberVisual = false;

  Future<void> _processUberVisual(DriverSettings settings) async {
    if (!state.isActive) return;
    if (_processingUberVisual) return;
    _processingUberVisual = true;
    try {
      await _processUberVisualLocked(settings);
    } finally {
      _processingUberVisual = false;
    }
  }

  Future<void> _processUberVisualLocked(DriverSettings settings) async {
    final result = await _visualEngine.analyzeCurrentScreen(includeRejectControl: false, cropped: true);
    final analysis = result.valueOrNull;
    if (analysis == null || !analysis.model.detected) {
      await _channel.hideUberDecisionOverlay();
      return;
    }

    final model = analysis.model;
    if (model.confidence < _minConfidenceForAutomation) {
      AppLogger.instance.debug(
        _tag,
        'Uber visual detection below confidence threshold '
        '(${model.confidence.toStringAsFixed(2)}) — not showing a decision',
      );
      await _channel.hideUberDecisionOverlay();
      return;
    }

    AppLogger.instance.debug(_tag, 'Uber job card detected (visual), raw text:\n${model.rawText}');

    final provisional = TaxiJob(
      id: _uuid.v4(),
      platform: PlatformType.uber,
      detectedAt: DateTime.now(),
      decision: JobDecision.pending,
      fare: model.fare,
      tripDistanceMiles: model.tripDistanceMiles,
      pickupDistanceMiles: model.pickupDistanceMiles,
      estimatedDurationMinutes: model.durationMinutes,
      destinationPostcode: model.destinationPostcode,
      rawDetectedText: model.rawText,
    );

    final outcome = _engine.evaluate(provisional, settings);

    if (outcome.decision != JobDecision.accepted && outcome.decision != JobDecision.rejected) {
      // Insufficient information — never guess (spec section 8/24): no
      // confident badge to show, and any previous one is now stale. Logged
      // unconditionally (not just a silent hide) — a real device showed a
      // job visually detected (fare + accept keyword both found,
      // confidence 1.0) still end up here because a distance value failed
      // to parse on that specific OCR pass, which is indistinguishable from
      // a genuine miss to the driver (no badge either way) without this.
      AppLogger.instance.debug(
        _tag,
        'Uber visual detection insufficient for a decision: fare=${model.fare} '
        'trip=${model.tripDistanceMiles} pickup=${model.pickupDistanceMiles} '
        'duration=${model.durationMinutes} reason=${outcome.reason}',
      );
      await _channel.hideUberDecisionOverlay();
      return;
    }

    // A blocked destination postcode overrides the usual £/mile · £/hour
    // badge entirely — the driver asked for this to say the postcode itself
    // then REJECTED, "regardless of the £ per miles", since the whole point
    // is that no fare/rate makes that destination worth it.
    final postcodeBlocked = outcome.evaluations.any(
      (e) => e.ruleName == const PostcodeBlocklistRule().name && e.result == RuleResult.fail,
    );

    final String badgeText;
    if (postcodeBlocked) {
      badgeText = provisional.destinationPostcode ?? 'Blocked postcode';
    } else {
      // The hourly rate is the "time factor" alongside £/mile — a short
      // pickup-heavy trip can clear a £/mile threshold while still being a
      // poor use of time if it's slow-going or the wait is long, and
      // estimatedHourlyRate already accounts for duration. Only appended
      // when a real duration was actually parsed (never guess — spec
      // section 8).
      final poundsPerMileText =
          outcome.poundsPerMile != null ? '£${outcome.poundsPerMile!.toStringAsFixed(2)}/mi' : '£?.??/mi';
      final hourlyRateSuffix =
          outcome.estimatedHourlyRate != null ? ' · £${outcome.estimatedHourlyRate!.toStringAsFixed(2)}/hr' : '';
      badgeText = '$poundsPerMileText$hourlyRateSuffix';
    }
    await _channel.showUberDecisionOverlay(
      poundsPerMileText: badgeText,
      isAccept: outcome.decision == JobDecision.accepted,
    );

    final fingerprint = JobFingerprintService.buildFingerprint(provisional);

    // Safety check 9: the job has not already been recorded. The badge
    // above is shown/refreshed unconditionally (harmless to repeat while
    // the same card is still on screen), but stats/history must not
    // double-count the same job across repeated detection events.
    if (_fingerprints.isDuplicate(fingerprint)) {
      AppLogger.instance.debug(_tag, 'Duplicate Uber job skipped ($fingerprint)');
      return;
    }
    _fingerprints.record(fingerprint);

    final job = provisional.copyWith(
      decision: outcome.decision,
      poundsPerMile: outcome.poundsPerMile,
      estimatedHourlyRate: outcome.estimatedHourlyRate,
      decisionReason: outcome.reason,
      fingerprint: fingerprint,
    );

    await _jobRepository.save(job);

    state = state.copyWith(
      jobsProcessed: state.jobsProcessed + 1,
      accepted: outcome.decision == JobDecision.accepted ? state.accepted + 1 : state.accepted,
      rejected: outcome.decision == JobDecision.rejected ? state.rejected + 1 : state.rejected,
      lastJob: job,
      lastEvaluations: outcome.evaluations,
      debug: state.debug.copyWith(
        parserUsed: 'UberVisualUnderstandingEngine',
        lastAction: outcome.decision == JobDecision.accepted
            ? 'Shown: ACCEPT (driver taps Uber\'s own button)'
            : 'Shown: REJECT (driver taps Uber\'s own button)',
      ),
    );

    // Trip/pickup distance included so a same-fare-different-£/mile
    // discrepancy across two detections of what looks like the same job
    // (real device evidence: identical fare, decision flipped ACCEPT<->
    // REJECT seconds apart) can be diagnosed directly from this one line
    // instead of needing a special repro — the fare alone can't reveal
    // which distance value actually changed between reads.
    AppLogger.instance.info(
      _tag,
      'Platform: Uber | Fare: ${job.fare} | Trip: ${job.tripDistanceMiles} | '
      'Pickup: ${job.pickupDistanceMiles} | Duration: ${job.estimatedDurationMinutes} | '
      'Postcode: ${job.destinationPostcode} | £/mile: ${job.poundsPerMile} | '
      '£/hr: ${job.estimatedHourlyRate} | Decision: ${job.decision.label} (shown only)',
    );
  }

  /// Returns true only when this specific card was actually, successfully
  /// accepted (the action confirmed, not just decided). [acceptGuard] is
  /// shared across every card in the same detected batch — see
  /// [_BatchAcceptGuard] for why accepting still can't happen more than
  /// once per batch even though cards are now processed concurrently.
  Future<bool> _processCard(
    ParsedJobData parsed,
    PlatformType platform,
    DriverSettings settings,
    _BatchAcceptGuard acceptGuard,
  ) async {
    // Declared outside the try block so the `finally` below can always
    // clear the in-flight guard, no matter which path (success, failure, or
    // exception) this call exits through — see [_inFlightFingerprints].
    String? fingerprint;
    try {
      // Safety check 2: a job is currently visible.
      if (!parsed.jobCardDetected) {
        // Diagnostic for a real-device question still open tonight: does
        // BoltJobParser's "request expired" exclusion (added deliberately —
        // see its doc comment — to stop retrying a card that's genuinely
        // unactionable) ever fire on a card that's actually still live? A
        // single, non-stacked offer has no "Instant" line to split on
        // (BoltJobParser.parse's fallback treats the whole screen as one
        // segment), so if Bolt's layout reserves a "Request expired" label
        // area even on a fresh single card, this exclusion could suppress a
        // genuinely actionable job with zero visible signal — previously
        // this whole branch logged nothing at all, indistinguishable from
        // "nothing was on screen". Logging the raw segment here (only on
        // the miss, not every successful detection, to avoid duplicating
        // the existing log below) is what would make that visible instead
        // of guessed.
        AppLogger.instance.debug(
          _tag,
          'Job card NOT detected (excluded or incomplete) for $platform — raw text:\n${parsed.rawText}',
        );
        return false;
      }

      // Logged (not just stored in debug.lastDetectedText) because the
      // dashboard's own frequent update events would otherwise overwrite
      // that field before a developer can inspect it — the append-only log
      // survives long enough to diagnose parser misses against real devices.
      AppLogger.instance.debug(_tag, 'Job card detected, raw text:\n${parsed.rawText}');

      final provisional = TaxiJob(
        id: _uuid.v4(),
        platform: platform,
        detectedAt: DateTime.now(),
        decision: JobDecision.pending,
        fare: parsed.fare,
        tripDistanceMiles: parsed.tripDistanceMiles,
        pickupDistanceMiles: parsed.pickupDistanceMiles,
        estimatedDurationMinutes: parsed.estimatedDurationMinutes,
        pickupAddress: parsed.pickupAddress,
        destinationAddress: parsed.destinationAddress,
        destinationPostcode: parsed.destinationPostcode,
        displayedPoundsPerMile: parsed.displayedPoundsPerMile,
        rawDetectedText: parsed.rawText,
      );

      fingerprint = JobFingerprintService.buildFingerprint(provisional);

      // Safety check 9: the job has not already been processed.
      if (_fingerprints.isDuplicate(fingerprint)) {
        AppLogger.instance.debug(_tag, 'Duplicate job skipped ($fingerprint)');
        return false;
      }
      if (_inFlightFingerprints.contains(fingerprint)) {
        AppLogger.instance.debug(_tag, 'Job already being processed, skipping overlap ($fingerprint)');
        return false;
      }
      _inFlightFingerprints.add(fingerprint);

      final outcome = _engine.evaluate(provisional, settings);
      final job = provisional.copyWith(
        decision: outcome.decision,
        poundsPerMile: outcome.poundsPerMile,
        estimatedHourlyRate: outcome.estimatedHourlyRate,
        decisionReason: outcome.reason,
        fingerprint: fingerprint,
      );

      String actionSummary = 'No action';
      var acceptedSuccessfully = false;

      // A real device showed a job card whose text only had ONE
      // distance/address line instead of the usual two (pickup leg + trip
      // leg) — BoltJobParser's single-unlabeled-distance fallback assigns
      // that one pair to the *destination*, leaving pickupAddress null.
      // Every action call below used pickupAddress specifically as the
      // native card anchor, so a null pickupAddress meant NO anchor text at
      // all — the native side's own null/blank check returns failure
      // immediately, before attempting anything or logging a single line
      // (see AutomationMethodChannelHandler.counterOfferJob's early return),
      // which made this failure mode silent and looked identical to "did
      // nothing" from the driver's side. Either address is an equally valid
      // anchor for locating the card (the native search just needs *some*
      // stable, unique text inside it) — falling back to destinationAddress
      // means this job shape still has something to search for.
      final cardAnchor = parsed.pickupAddress ?? parsed.destinationAddress;

      // A real device proved this matters: the fingerprint used to be
      // recorded unconditionally the moment a job card was read, before any
      // accept/reject/counter-offer was even attempted. When that action
      // then failed — e.g. the card wasn't quite settled yet, or a tap
      // landed a beat too early — the job was already marked "handled" for
      // the next 5 minutes, so it silently sat on screen fully actionable
      // with JobFilter never trying again. Only recording once an attempted
      // action actually succeeds (or none was needed) means a failed first
      // try gets picked back up on the very next poll tick instead.
      var shouldRecordFingerprint = true;

      // Safety checks 3-7: fare/distance parsed, decision is final, still
      // the same job, correct control identified — all enforced inside the
      // engine (unknown data -> pending) and the native accept/reject path
      // (re-verifies the visible job before tapping anything).
      //
      // Both platforms now go through the accessibility tree directly, not
      // OCR-derived coordinates: Bolt's card must be opened via
      // [parsed.pickupAddress] as the card anchor (more than one offer can
      // be visible at once) before its button can be tapped; Uber's whole
      // card, accept button included, is a real clickable node with no card
      // to open first (confirmed on a real device via `uiautomator dump`),
      // so it ignores the anchor and finds its button by keyword instead —
      // see AutomationMethodChannelHandler.acceptJob/rejectJob (Kotlin).
      if (outcome.decision == JobDecision.accepted) {
        if (!state.isActive) {
          actionSummary = 'Skipped — automation stopped before action executed';
          shouldRecordFingerprint = false;
        } else if (!acceptGuard.claim()) {
          // Another card in this same batch already claimed the accept —
          // see [_BatchAcceptGuard]. Not recorded as handled: this job is
          // genuinely still sitting there untouched, so it should be free
          // to be picked up again (e.g. rejected, if that's still correct)
          // on its next sighting rather than silently locked out.
          actionSummary = 'Skipped — another job in this batch was already accepted';
          shouldRecordFingerprint = false;
        } else {
          final result = await _executor.acceptJob(platform: platform, cardAnchor: cardAnchor);
          actionSummary = result.when(
            ok: (_) => 'Accepted',
            err: (f) => 'Accept failed: $f',
          );
          acceptedSuccessfully = result.when(ok: (_) => true, err: (_) => false);
          shouldRecordFingerprint = acceptedSuccessfully;

          // Only Bolt ever reaches this fully-automated accept path (Uber's
          // early-returns to _processUberVisual before here, which only
          // ever shows a badge for the driver to tap themselves) — and
          // Bolt's own offer is a small overlay/notification-style panel,
          // not something that keeps the app in front, so the driver can
          // genuinely be looking at something else entirely when this
          // fires. Without an audible alert here, they'd have no way to
          // know a job was just committed on their behalf until they
          // happened to check.
          if (acceptedSuccessfully && platform == PlatformType.bolt) {
            final fareText = parsed.fare != null ? '£${parsed.fare!.toStringAsFixed(2)}' : 'Fare unknown';
            final rateText = outcome.poundsPerMile != null
                ? ' · £${outcome.poundsPerMile!.toStringAsFixed(2)}/mile'
                : '';
            final addressText = parsed.pickupAddress != null ? ' — ${parsed.pickupAddress}' : '';
            await _channel.showJobAcceptedNotification(
              contentText: '$fareText$rateText$addressText',
            );
          }
        }
      } else if (outcome.decision == JobDecision.rejected) {
        if (!state.isActive) {
          actionSummary = 'Skipped — automation stopped before action executed';
          shouldRecordFingerprint = false;
        } else {
          final result = await _executor.rejectJob(platform: platform, cardAnchor: cardAnchor);
          actionSummary = result.when(
            ok: (_) => 'Rejected',
            err: (f) => 'Reject failed: $f',
          );
          shouldRecordFingerprint = result.when(ok: (_) => true, err: (_) => false);
        }
      } else if (outcome.decision == JobDecision.counterOffered) {
        if (!state.isActive) {
          actionSummary = 'Skipped — automation stopped before action executed';
          shouldRecordFingerprint = false;
        } else {
          final result = await _executor.counterOfferJob(platform: platform, cardAnchor: cardAnchor);
          actionSummary = result.when(
            ok: (_) => 'Counter-offered',
            err: (f) => 'Counter-offer failed: $f',
          );
          shouldRecordFingerprint = result.when(ok: (_) => true, err: (_) => false);
        }
      } else {
        actionSummary = 'No action — insufficient information';
      }

      // Spec/driver-facing correctness: the decision recorded and shown to
      // the driver must reflect what actually happened on screen, not just
      // what the rules engine decided. A real device showed the dashboard
      // claiming "REJECTED" for a job whose swipe/tap action had genuinely
      // failed (the card never moved) — `job.decision` above only ever
      // holds the *intended* verdict (`outcome.decision`), so persisting it
      // unconditionally silently overclaimed success. shouldRecordFingerprint
      // is already exactly "the attempted action truly succeeded (or none
      // was needed)" — reused here rather than introducing a second,
      // possibly-diverging flag.
      final actionFailedOrSkipped = outcome.decision.isFinal && !shouldRecordFingerprint;
      final recordedJob = actionFailedOrSkipped
          ? job.copyWith(decision: JobDecision.error, decisionReason: actionSummary)
          : job;

      if (shouldRecordFingerprint) {
        _fingerprints.record(fingerprint);
      }

      await _jobRepository.save(recordedJob);

      state = state.copyWith(
        jobsProcessed: state.jobsProcessed + 1,
        accepted: recordedJob.decision == JobDecision.accepted ? state.accepted + 1 : state.accepted,
        rejected: recordedJob.decision == JobDecision.rejected ? state.rejected + 1 : state.rejected,
        lastJob: recordedJob,
        lastEvaluations: outcome.evaluations,
        debug: state.debug.copyWith(lastAction: actionSummary),
      );

      AppLogger.instance.info(
        _tag,
        'Platform: ${platform.displayName} | Fare: ${recordedJob.fare} | '
        '£/mile: ${recordedJob.poundsPerMile} | Decision: ${recordedJob.decision.label}',
      );
      return acceptedSuccessfully;
    } catch (e, stackTrace) {
      // Spec section 35: never crash on a bad job. Record an error job and
      // keep monitoring the rest of this screen's cards / future events.
      AppLogger.instance.error(_tag, 'Failed to process job card: $e\n$stackTrace');
      state = state.copyWith(statusMessage: 'Monitoring... (last job failed to process)');
      return false;
    } finally {
      if (fingerprint != null) _inFlightFingerprints.remove(fingerprint);
    }
  }

  PlatformType _resolvePlatform(String? foregroundPackage) {
    if (foregroundPackage == null) return PlatformType.unknown;
    for (final type in [PlatformType.uber, PlatformType.bolt]) {
      if (type.androidPackageName == foregroundPackage) return type;
    }
    return PlatformType.unknown;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _stopRequestSubscription?.cancel();
    _uberPollTimer?.cancel();
    _ocr.dispose();
    super.dispose();
  }
}

final automationControllerProvider =
    StateNotifierProvider<AutomationController, AutomationState>((ref) {
  return AutomationController(ref);
});

/// One instance shared across every card in a single detected batch (see
/// the `Future.wait` call in [AutomationController]'s detected-text
/// handler) — accepting commits the driver to that job, so even though
/// reject/counter-offer are now safe to run concurrently across a stacked
/// batch, at most one card may ever actually accept. Whichever card's
/// synchronous evaluation reaches [claim] first wins; every other card
/// (even another one that also decided ACCEPT) backs off instead of
/// attempting a second accept action from what's now a stale batch.
/// Deliberately claimed *before* the native action is attempted, not after
/// it succeeds — since Dart runs each `_processCard` call synchronously up
/// to its first `await`, claiming here (still synchronous, before the
/// `await _executor.acceptJob(...)` call) is what actually closes the race
/// between two cards that both decided ACCEPT; claiming only after success
/// would leave that same window open.
class _BatchAcceptGuard {
  bool _claimed = false;

  bool claim() {
    if (_claimed) return false;
    _claimed = true;
    return true;
  }
}
