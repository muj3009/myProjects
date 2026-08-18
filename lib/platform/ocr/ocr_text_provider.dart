import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/errors/failures.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/result.dart';
import '../automation/automation_method_channel.dart';
import '../screen_text_provider.dart';

const _tag = 'OcrTextProvider';

/// Fallback [ScreenTextProvider] (spec section 9) used to *read* a job's
/// fare/route details when the Accessibility Service's text extraction
/// doesn't carry them — confirmed on a real device for Uber via
/// `uiautomator dump`: its job card's buttons are real clickable
/// accessibility nodes (tapped directly, the same way as Bolt's — see
/// JobAccessibilityService.findAndClickButtonByKeywords /
/// findAndClickDeclineButton), but the fare/distance/route text alongside
/// them isn't exposed as node text or content-description at all. OCR is
/// only ever used here to *read* that text for the decision engine, never
/// to compute where to tap — accept/reject always goes through the
/// accessibility tree.
///
/// Captures a single screenshot via the native side and runs on-device text
/// recognition on it. ML Kit's `InputImage.fromBytes` expects raw camera
/// pixel planes (NV21/YUV), not a compressed image, so the screenshot is
/// written to a temp file and loaded via `fromFilePath` instead, which lets
/// the platform decode it itself. The native side encodes as JPEG rather
/// than PNG — a real device measured PNG's lossless compression taking
/// several seconds for one screenshot, long enough that Uber's job offer
/// was routinely gone before OCR finished reading it; JPEG is built for
/// fast encoding and easily legible enough for OCR at quality 90.
class OcrTextProvider implements ScreenTextProvider {
  OcrTextProvider({AutomationMethodChannel? channel, TextRecognizer? recognizer})
      : _channel = channel ?? AutomationMethodChannel(),
        _recognizer = recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final AutomationMethodChannel _channel;
  final TextRecognizer _recognizer;

  /// True while a capture is already running. [AutomationController]
  /// throttles how often it *starts* a capture, but a screenshot +
  /// compression + on-device recognition pass can take longer than that
  /// throttle window on a mid-range phone — without this guard, a slow
  /// capture and the next scheduled one would run concurrently, both hitting
  /// the native screenshot pipeline and this app's own cache directory at
  /// the same time. A real device showed exactly that: several
  /// FileNotFoundExceptions for different temp files landing within the
  /// same few milliseconds, consistent with concurrent capture passes
  /// contending over shared native/file-system resources rather than any
  /// single call being broken on its own. Refusing to overlap is correct
  /// regardless of what the underlying resource contention turns out to be.
  bool _capturing = false;

  @override
  String get name => 'OcrTextProvider';

  @override
  Future<Result<String>> getScreenText() async {
    if (_capturing) {
      AppLogger.instance.debug(_tag, 'getScreenText: skipped — previous capture still in progress');
      return const Result.err(AutomationFailure('OCR capture already in progress'));
    }
    _capturing = true;
    final callStart = DateTime.now();
    // Temporary, verbose on purpose — tracing a real device's intermittent
    // "temp file not found" failure that only ever showed up as the final
    // exception, with nothing to say whether the file was ever written, how
    // big it was, or whether it still existed by the time ML Kit tried to
    // open it. Safe to trim once that's root-caused.
    AppLogger.instance.debug(_tag, 'getScreenText: start');

    try {
      final bytes = await _channel.captureScreenshotForOcr();
      AppLogger.instance.debug(
        _tag,
        'getScreenText: native screenshot returned ${bytes?.length ?? 'null'} bytes '
        '(+${DateTime.now().difference(callStart).inMilliseconds}ms)',
      );
      if (bytes == null) {
        return const Result.err(AutomationFailure('Screenshot unavailable for OCR'));
      }

      File? tempFile;
      try {
        final tempDir = await getTemporaryDirectory();
        // Unique per call defends against a *different* filename collision
        // than the single-flight guard above — this remains in place as a
        // second, independent layer of protection either way.
        final uniqueName = 'jobfilter_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg';
        tempFile = File('${tempDir.path}/$uniqueName');
        await tempFile.writeAsBytes(bytes, flush: true);
        AppLogger.instance.debug(
          _tag,
          'getScreenText: wrote ${tempFile.path} '
          '(+${DateTime.now().difference(callStart).inMilliseconds}ms)',
        );

        // Checked immediately before handing the path to ML Kit's native
        // side — if this ever logs missing/0 bytes, the file was lost
        // between being written and being read, not merely slow to write.
        final existsNow = await tempFile.exists();
        final sizeNow = existsNow ? await tempFile.length() : -1;
        AppLogger.instance.debug(
          _tag,
          'getScreenText: pre-recognition check exists=$existsNow size=$sizeNow '
          '(+${DateTime.now().difference(callStart).inMilliseconds}ms)',
        );

        final inputImage = InputImage.fromFilePath(tempFile.path);
        final recognizedText = await _recognizer.processImage(inputImage);
        AppLogger.instance.debug(
          _tag,
          'getScreenText: recognition complete, ${recognizedText.text.length} chars '
          '(+${DateTime.now().difference(callStart).inMilliseconds}ms)',
        );
        if (recognizedText.text.trim().isEmpty) {
          return const Result.err(AutomationFailure('OCR produced no text'));
        }
        return Result.ok(recognizedText.text);
      } catch (e) {
        AppLogger.instance.error(_tag, 'OCR processing failed: $e');
        return Result.err(AutomationFailure('OCR processing failed: $e'));
      } finally {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    } finally {
      _capturing = false;
    }
  }

  Future<void> dispose() => _recognizer.close();
}
