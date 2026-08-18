import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/utils/app_logger.dart';

const _tag = 'CardIconLocator';

/// Locates a small icon-like glyph (Uber's reject "X" has no text or
/// content-description of its own — confirmed via a real device's
/// `uiautomator dump` — so OCR can never find it directly) by scanning the
/// frame's actual decoded pixels within a known row, instead of guessing a
/// fixed offset from a nearby OCR'd text line. Computed fresh from each
/// frame's own pixels every time — nothing here is a remembered constant.
class CardIconLocator {
  const CardIconLocator._();

  /// [rowTop]/[rowBottom] are real pixel Y-coordinates (not normalized) —
  /// typically the bounding box of an OCR'd text line known to share its
  /// row with the icon (e.g. the vehicle-type badge for Uber's reject "X").
  /// Scans right-to-left for the icon's actual left/right edges: Uber's
  /// icon renders as a visibly darker glyph on a light card background, so
  /// the boundary between "icon" and "background" columns is a real,
  /// measurable signal rather than an assumption. Returns null if no clear
  /// icon-like region is found — callers must not guess a fallback position
  /// (spec section 24: never guess).
  static Future<({double left, double right})?> findIconRightOfRow({
    required Uint8List jpegBytes,
    required int frameWidth,
    required int frameHeight,
    required double rowTop,
    required double rowBottom,
  }) async {
    ui.Image? image;
    try {
      final codec = await ui.instantiateImageCodec(jpegBytes);
      final decoded = await codec.getNextFrame();
      image = decoded.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        AppLogger.instance.warning(_tag, 'findIconRightOfRow: could not read raw pixels');
        return null;
      }

      final width = image.width;
      final height = image.height;
      final bytes = byteData.buffer.asUint8List();
      final top = rowTop.clamp(0, height - 1).toInt();
      final bottom = rowBottom.clamp(0, height - 1).toInt();
      if (bottom <= top) return null;

      // Per-column "darkness": how far each column's average luminance
      // across the row sits below a light-card-background baseline. Uber's
      // card background is consistently light in every real sample this
      // session, and its icon glyph (a dark X stroke) stands out clearly
      // against it — this is a measured contrast, not an assumed color.
      final darkness = List<double>.filled(width, 0);
      for (var x = 0; x < width; x++) {
        double sum = 0;
        var count = 0;
        for (var y = top; y <= bottom; y += 2) {
          final idx = (y * width + x) * 4;
          if (idx + 2 >= bytes.length) continue;
          final r = bytes[idx];
          final g = bytes[idx + 1];
          final b = bytes[idx + 2];
          final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
          sum += (255 - luminance);
          count++;
        }
        if (count > 0) darkness[x] = sum / count;
      }

      // A background column is near-white (low darkness); an icon/text
      // column is meaningfully darker. Threshold picked well above normal
      // JPEG compression noise on a light background (empirically ~5-15
      // in real samples) without being so high it misses a lightly-tinted
      // icon glyph.
      const backgroundThreshold = 40.0;
      const minIconColumns = 8;
      const maxIconColumns = 140;

      // Scan from the frame's right edge inward for the first run of
      // "content" columns — Uber's icon sits close to the card's right
      // edge in every real sample this session — then continue left until
      // a run of background columns confirms the icon's actual left edge,
      // rather than assuming any fixed width.
      var x = width - 1;
      while (x >= 0 && darkness[x] < backgroundThreshold) {
        x--;
      }
      if (x < 0) {
        AppLogger.instance.debug(_tag, 'findIconRightOfRow: no content found scanning from right edge');
        return null;
      }
      final right = x;

      var backgroundRun = 0;
      var left = right;
      var foundLeftEdge = false;
      while (left > 0 && (right - left) < maxIconColumns) {
        left--;
        if (darkness[left] < backgroundThreshold) {
          backgroundRun++;
          // A confirmed gap (several consecutive background columns) means
          // we've moved past the icon into empty margin — the icon's real
          // left edge was the last content column before this run started.
          if (backgroundRun >= 6) {
            left += backgroundRun;
            foundLeftEdge = true;
            break;
          }
        } else {
          backgroundRun = 0;
        }
      }

      // Hitting the width cap (or x=0) without ever finding a real
      // background gap means the scan swept into unrelated dark content —
      // a real device showed this happen and land on something else
      // entirely (likely the vehicle-type badge itself), not the icon.
      // Trusting that result caused a wrong tap, so it's treated as a
      // failed detection instead (spec section 24: never guess).
      if (!foundLeftEdge) {
        AppLogger.instance.debug(
          _tag,
          'findIconRightOfRow: scan hit its width limit without finding a clean left edge '
          '(x=$left..$right) — discarding rather than trust a possibly-wrong region',
        );
        return null;
      }

      final iconWidth = right - left;
      if (iconWidth < minIconColumns) {
        AppLogger.instance.debug(
          _tag,
          'findIconRightOfRow: detected region too narrow ($iconWidth px) to trust as a real icon',
        );
        return null;
      }

      AppLogger.instance.debug(
        _tag,
        'findIconRightOfRow: icon at x=$left..$right (${iconWidth}px wide), row y=$top..$bottom',
      );
      return (left: left.toDouble(), right: right.toDouble());
    } catch (e) {
      AppLogger.instance.warning(_tag, 'findIconRightOfRow failed: $e');
      return null;
    } finally {
      image?.dispose();
    }
  }
}
