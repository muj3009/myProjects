import 'dart:ui' show Offset;

import '../../core/utils/app_logger.dart';
import '../../domain/vision/uber_offer_visual_model.dart';
import 'screen_frame.dart';

const _tag = 'CoordinateMapper';

/// Maps a [NormalizedRect] (0.0-1.0 fractions of one specific [ScreenFrame])
/// to a real gesture-dispatch coordinate (spec: production visual
/// architecture, Phase 4).
///
/// The mapping is a plain scale by that frame's own pixel width/height —
/// never a fixed resolution, density table, or remembered constant from a
/// previous device or previous capture. This is deliberately simple rather
/// than compensating for status bar / navigation bar / cutout insets,
/// because a real device's own evidence (this session's earlier
/// investigation) proved screenshot pixels and gesture-dispatch pixels
/// share the *same* coordinate space by construction: both
/// `AccessibilityService.takeScreenshot()` and
/// `AccessibilityService.dispatchGesture()` operate on the same underlying
/// display surface, in raw display pixels, regardless of density, insets,
/// or navigation mode — there is nothing separate to reconcile. Rotation is
/// handled the same way: a screenshot always reflects the display's
/// *current* rotation, and a gesture dispatched immediately after is
/// interpreted in that same current orientation, so no explicit rotation
/// transform is needed as long as the two happen close together — which
/// [rotationMatches] exists to verify rather than assume.
class CoordinateMapper {
  const CoordinateMapper._();

  /// Center point of [rect] within [frame], in raw gesture-dispatch pixels.
  static Offset centerOf(NormalizedRect rect, ScreenFrame frame) {
    final point = Offset(
      rect.centerX * frame.width,
      rect.centerY * frame.height,
    );
    AppLogger.instance.debug(
      _tag,
      'centerOf: rect=$rect frame=${frame.width}x${frame.height} rotation=${frame.rotation} -> point=$point',
    );
    return point;
  }

  /// True if [currentRotation] (`Surface.ROTATION_*`, read fresh at the
  /// moment of acting) still matches the rotation [frame] was captured
  /// under. A mismatch means the device rotated between capture and action
  /// — the normalized rect can no longer be trusted to mean the same thing,
  /// so the caller must re-capture rather than map stale coordinates.
  static bool rotationMatches(ScreenFrame frame, int currentRotation) {
    final matches = frame.rotation == currentRotation;
    if (!matches) {
      AppLogger.instance.warning(
        _tag,
        'rotationMatches: frame captured at rotation=${frame.rotation}, '
        'now rotation=$currentRotation — refusing to map stale coordinates',
      );
    }
    return matches;
  }
}
