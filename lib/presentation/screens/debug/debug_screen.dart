import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/controllers/automation_controller.dart';
import '../../../application/state/providers.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/result.dart';
import '../../../domain/enums/job_decision.dart';
import '../../../domain/vision/uber_offer_visual_model.dart';
import '../../../platform/vision/uber_visual_understanding_engine.dart' show UberVisualAnalysis;
import '../../widgets/section_card.dart';

/// Developer-only debug screen (spec section 34). Only reachable from
/// Settings when running a debug build (see settings_screen.dart's
/// `kDebugMode` guard) — release builds never surface this navigation entry.
class DebugScreen extends ConsumerWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final automation = ref.watch(automationControllerProvider);
    final debug = automation.debug;
    final logs = AppLogger.instance.recentEntries.reversed.take(50).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Developer debug')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Accessibility service', debug.accessibilityConnected ? 'CONNECTED' : 'NOT CONNECTED'),
                _row('Foreground package', debug.foregroundPackage ?? '—'),
                _row('Parser', debug.parserUsed ?? '—'),
                _row(
                  'Fare',
                  automation.lastJob?.fare != null
                      ? '£${automation.lastJob!.fare!.toStringAsFixed(2)}'
                      : '—',
                ),
                _row(
                  'Distance',
                  automation.lastJob?.tripDistanceMiles != null
                      ? '${automation.lastJob!.tripDistanceMiles!.toStringAsFixed(1)} mi'
                      : '—',
                ),
                _row(
                  '£/mile',
                  automation.lastJob?.poundsPerMile != null
                      ? '£${automation.lastJob!.poundsPerMile!.toStringAsFixed(2)}'
                      : '—',
                ),
                _row('Decision', automation.lastJob?.decision.label ?? '—'),
                _row('Last action', debug.lastAction ?? '—'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _VisualDiagnosticsSection(),
          const SizedBox(height: 16),
          if (debug.lastDetectedText != null) ...[
            Text('Last detected text', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SectionCard(child: SelectableText(debug.lastDetectedText!)),
            const SizedBox(height: 16),
          ],
          Text('Recent logs', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in logs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      entry.toString(),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                if (logs.isEmpty) const Text('No logs yet'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Flexible(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

/// Read-only visual-pipeline inspector: proves capture and detection work
/// against whatever's currently on screen — fare, distance, and the
/// accept/reject bounds the decision is based on. Uber's real automation
/// (see [AutomationController._processUberVisual]) never dispatches a
/// gesture — it shows a small ACCEPT/REJECT badge and the driver taps
/// Uber's own button themselves — so nothing here affects it beyond the
/// brief capture pause below.
class _VisualDiagnosticsSection extends ConsumerStatefulWidget {
  const _VisualDiagnosticsSection();

  @override
  ConsumerState<_VisualDiagnosticsSection> createState() => _VisualDiagnosticsSectionState();
}

class _VisualDiagnosticsSectionState extends ConsumerState<_VisualDiagnosticsSection> {
  static const _countdownSeconds = 3;
  static const _maxWatchSeconds = 120;
  static const _pollInterval = Duration(seconds: 2);
  static const _tag = 'VisualDiagnostics';

  int? _secondsLeft;
  bool _watching = false;
  int _watchedSeconds = 0;
  int _pollAttempts = 0;
  bool _cancelRequested = false;
  Result<UberVisualAnalysis>? _lastResult;

  /// Ground-truth calibration: where the developer says the real button
  /// actually is, tapped directly on the captured screenshot image (not on
  /// live Uber) — lets us check the OCR-based heuristics' estimated
  /// [VisualControl.bounds] against reality, especially the reject control,
  /// which has no text to OCR and is currently pure geometric estimate. This
  /// is diagnostic only — nothing here is ever fed into the coordinate
  /// mapper or wired into automation; hardcoded/remembered coordinates are
  /// explicitly excluded from production per the architecture spec.
  Offset? _calibrationTapNormalized;
  String? _calibrationNote;

  /// A capture fired the instant this button is pressed would just capture
  /// THIS debug screen, not Uber — the developer is necessarily looking at
  /// JobFilter, not Uber, at that exact moment. Native side correctly
  /// refuses that (the same self-capture guard that stopped JobFilter's own
  /// dashboard from once being OCR'd as a fake job), which is why a direct
  /// button press only ever produced "Screen frame unavailable" on a real
  /// device. The countdown gives the developer time to switch back to Uber
  /// before capturing starts.
  ///
  /// Uber offers arrive at unpredictable times, not the instant a developer
  /// presses a button, so a single capture right after the countdown mostly
  /// just caught the dashboard — this instead keeps capturing every
  /// [_pollInterval] until a real offer is actually detected (or
  /// [_maxWatchSeconds] runs out / the developer cancels), so timing the
  /// button press against a random job offer is no longer necessary.
  Future<void> _watchForOffer() async {
    setState(() {
      _secondsLeft = _countdownSeconds;
      _cancelRequested = false;
    });
    // The always-on live monitoring loop (AutomationController) fires its
    // own takeScreenshot() on nearly every accessibility event (~every
    // 800ms) — a real device proved that competing with it for the same
    // rate-limited native screenshot API made this diagnostic capture fail
    // intermittently with ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT even
    // while Uber was genuinely in the foreground. Pausing it for the
    // duration of this watch (never touched by production automation)
    // removes that race. Captured once, before any `await`, so it's safe to
    // use from `finally` even if this State is disposed by the time we get
    // there — `ref.read` after disposal would throw.
    final controller = ref.read(automationControllerProvider.notifier);
    controller.pauseForVisualDiagnostics();
    try {
      for (var remaining = _countdownSeconds; remaining > 0; remaining--) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted || _cancelRequested) return _stopWatching();
        setState(() => _secondsLeft = remaining - 1);
      }
      if (!mounted) return;
      setState(() {
        _secondsLeft = null;
        _watching = true;
        _watchedSeconds = 0;
        _pollAttempts = 0;
      });

      final engine = ref.read(uberVisualUnderstandingEngineProvider);
      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsed.inSeconds < _maxWatchSeconds) {
        if (!mounted || _cancelRequested) return _stopWatching();

        final result = await engine.analyzeCurrentScreen();
        if (!mounted || _cancelRequested) return _stopWatching();
        _pollAttempts++;

        final foundOffer = result.valueOrNull?.model.detected ?? false;
        if (foundOffer) {
          setState(() {
            _watching = false;
            _lastResult = result;
          });
          return;
        }

        // Keep the most recent result visible even on a miss (e.g. capture
        // failed because the driver briefly switched away) so "what did it
        // last see" is never a total blank while still watching.
        setState(() {
          _lastResult = result;
          _watchedSeconds = stopwatch.elapsed.inSeconds;
        });
        await Future<void>.delayed(_pollInterval);
      }

      if (!mounted) return;
      setState(() => _watching = false);
    } finally {
      controller.resumeFromVisualDiagnostics();
    }
  }

  void _stopWatching() {
    if (!mounted) return;
    setState(() {
      _secondsLeft = null;
      _watching = false;
    });
  }

  void _cancelWatching() {
    setState(() => _cancelRequested = true);
  }

  /// [normalized] is the tap position as a 0.0-1.0 fraction of the displayed
  /// image, which is exactly the same coordinate space [NormalizedRect] uses
  /// — so the distance to a detected control's center is directly
  /// comparable without any further conversion.
  void _onCalibrationTap(Offset normalized, UberVisualAnalysis analysis) {
    final model = analysis.model;
    final note = StringBuffer('Marked point: (${normalized.dx.toStringAsFixed(3)}, ${normalized.dy.toStringAsFixed(3)})');
    for (final entry in [
      ('accept', model.acceptControl),
      ('reject', model.rejectControl),
    ]) {
      final control = entry.$2;
      if (control == null) continue;
      final dx = normalized.dx - control.bounds.centerX;
      final dy = normalized.dy - control.bounds.centerY;
      final distance = (dx * dx + dy * dy);
      note.write(' | vs ${entry.$1} center ${control.bounds}: dx=${dx.toStringAsFixed(3)} dy=${dy.toStringAsFixed(3)}');
      if (distance < 0.0025) note.write(' (close match)');
    }
    AppLogger.instance.info(_tag, 'calibration: $note');
    setState(() {
      _calibrationTapNormalized = normalized;
      _calibrationNote = note.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _lastResult;
    final counting = _secondsLeft != null;
    final busy = counting || _watching;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Visual understanding (Uber)', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Read-only: tap the button below, then switch to Uber, to see exactly what the visual '
          'pipeline currently detects (fare, distance, accept/reject bounds, and the decision it '
          'would show as a badge) without affecting automation. After a $_countdownSeconds-second '
          'countdown it keeps watching (capturing every ${_pollInterval.inSeconds}s, up to '
          '${_maxWatchSeconds}s) until a real offer appears, so you don\'t have to time it against a '
          'random job.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : _watchForOffer,
                child: Text(
                  counting
                      ? 'Switch to Uber now… capturing in ${_secondsLeft}s'
                      : _watching
                          ? 'Watching… ${_watchedSeconds}s (attempt $_pollAttempts) — tap to see last frame'
                          : 'Watch for offer ($_countdownSeconds s to switch, up to ${_maxWatchSeconds}s)',
                ),
              ),
            ),
            if (_watching) ...[
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _cancelWatching, child: const Text('Cancel')),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (result != null) SectionCard(child: _buildResult(context, result)),
      ],
    );
  }

  Widget _buildResult(BuildContext context, Result<UberVisualAnalysis> result) {
    return result.when(
      ok: (analysis) {
        final model = analysis.model;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Screenshot captured', 'YES (${analysis.frame.width}x${analysis.frame.height})'),
            const SizedBox(height: 8),
            _buildCalibrationImage(context, analysis),
            if (_calibrationNote != null) ...[
              const SizedBox(height: 4),
              Text(_calibrationNote!, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ],
            const SizedBox(height: 8),
            _row('Offer detected', model.detected ? 'YES' : 'NO'),
            _row('Confidence', '${(model.confidence * 100).toStringAsFixed(0)}%'),
            _row('Fare', model.fare != null ? '£${model.fare!.toStringAsFixed(2)}' : '—'),
            _row(
              'Trip distance',
              model.tripDistanceMiles != null ? '${model.tripDistanceMiles!.toStringAsFixed(1)} mi' : '—',
            ),
            _row('Duration', model.durationMinutes != null ? '${model.durationMinutes} min' : '—'),
            const Divider(),
            _row(
              'Accept control',
              model.acceptControl != null
                  ? '${model.acceptControl!.bounds} (${(model.acceptControl!.confidence * 100).toStringAsFixed(0)}%)'
                  : 'not found',
            ),
            if (model.acceptControl != null)
              Text(model.acceptControl!.evidence, style: Theme.of(context).textTheme.bodySmall),
            _row(
              'Reject control',
              model.rejectControl != null
                  ? '${model.rejectControl!.bounds} (${(model.rejectControl!.confidence * 100).toStringAsFixed(0)}%)'
                  : 'not found',
            ),
            if (model.rejectControl != null)
              Text(model.rejectControl!.evidence, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
      err: (failure) => Text('Analysis failed: $failure'),
    );
  }

  /// Shows the exact frame the visual engine analyzed, with the detected
  /// accept/reject bounds drawn on top (green/red) so a mismatch against the
  /// real button is visible at a glance. Tapping anywhere on the image marks
  /// a ground-truth point (yellow) and logs its offset from each detected
  /// control's center — see [_onCalibrationTap].
  Widget _buildCalibrationImage(BuildContext context, UberVisualAnalysis analysis) {
    final frame = analysis.frame;
    final model = analysis.model;
    // Keyed on the frame's own timestamp: the watch loop swaps in a brand
    // new screenshot roughly every 2s, and letting Flutter try to diff/reuse
    // the previous frame's Image/Stack/AspectRatio subtree in place hit a
    // real-device crash (`'child._parent == this': is not true`, a Flutter
    // render-tree assertion). A fresh key forces a clean replace instead of
    // an in-place update every time the bytes change.
    return KeyedSubtree(
      key: ValueKey(frame.timestamp),
      child: AspectRatio(
        aspectRatio: frame.width / frame.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(frame.bytes, fit: BoxFit.fill),
                  if (model.acceptControl != null)
                    _boundsOverlay(model.acceptControl!.bounds, size, Colors.greenAccent, 'accept'),
                  if (model.rejectControl != null)
                    _boundsOverlay(model.rejectControl!.bounds, size, Colors.redAccent, 'reject'),
                  if (_calibrationTapNormalized != null)
                    Positioned(
                      left: _calibrationTapNormalized!.dx * size.width - 8,
                      top: _calibrationTapNormalized!.dy * size.height - 8,
                      child: const Icon(Icons.add, color: Colors.yellowAccent, size: 16),
                    ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) {
                      final normalized = Offset(
                        (details.localPosition.dx / size.width).clamp(0.0, 1.0),
                        (details.localPosition.dy / size.height).clamp(0.0, 1.0),
                      );
                      _onCalibrationTap(normalized, analysis);
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _boundsOverlay(NormalizedRect bounds, Size size, Color color, String label) {
    return Positioned(
      left: bounds.left * size.width,
      top: bounds.top * size.height,
      width: (bounds.right - bounds.left) * size.width,
      height: (bounds.bottom - bounds.top) * size.height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: color, width: 2)),
          alignment: Alignment.topLeft,
          child: Container(
            color: color.withValues(alpha: 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(label, style: const TextStyle(fontSize: 9, color: Colors.black)),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Flexible(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
