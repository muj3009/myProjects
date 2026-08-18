import 'dart:typed_data';

/// One full, uncropped capture of the display — the input to
/// [UberVisualSurfaceProvider.captureFrame]. Deliberately carries its own
/// exact pixel dimensions rather than letting callers assume a resolution;
/// every consumer downstream (the visual understanding engine, and
/// eventually the coordinate mapper for gesture dispatch) must read [width]/
/// [height] off the frame it actually has, not off a constant.
class ScreenFrame {
  const ScreenFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.densityPixelRatio,
    required this.rotation,
    required this.timestamp,
    this.displayId = 0,
  });

  /// JPEG-encoded bytes of the full display, exactly as captured — see
  /// JobAccessibilityService.captureScreenFrame for why JPEG (a real device
  /// measured PNG's lossless compression taking multiple seconds per frame).
  final Uint8List bytes;

  /// Exact pixel width/height of [bytes] once decoded — never assumed.
  final int width;
  final int height;

  /// Device pixel ratio at capture time (dp -> px), for any caller that
  /// needs to reconcile this frame's pixel geometry with Flutter's own
  /// logical coordinate space. Not needed for gesture dispatch itself: the
  /// accessibility gesture API and the screenshot API operate in the same
  /// raw pixel space by construction, independent of density.
  final double densityPixelRatio;

  /// `Surface.ROTATION_*` value (0/1/2/3) at capture time.
  final int rotation;

  final DateTime timestamp;

  /// Reserved for multi-display devices; always 0 (default display) today.
  final int displayId;
}
