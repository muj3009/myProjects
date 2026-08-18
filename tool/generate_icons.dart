// One-off script (not shipped, not part of the app) — composites the
// driver-supplied artwork onto properly padded/backgrounded square canvases
// for the Android app icon (legacy + adaptive layers) and the floating
// "online" bubble.
//
// The source photo is a complete pre-rendered app icon (funnel + "Jobs"
// wordmark + its own white rounded-square card), not a transparent sticker
// of just the funnel. Compositing that whole card as "the artwork" doubles
// up backgrounds badly: OneUI's own icon mask around an already-square
// white card left a visible white margin on the home screen, and the
// card's own rounded corners showed up as a visible square poking out of
// the bubble's green circle. This strips that near-white card background
// to transparent first (a soft luminance threshold, since it's a subtle
// gradient rather than one flat color) and trims to the funnel's own
// bounding box, so only the funnel + wordmark ever gets composited.
//
// Run with: dart run tool/generate_icons.dart
import 'dart:io';

import 'package:image/image.dart' as img;

const _background = 0xFFFFFFFF;

void main() {
  final sourcePath =
      r'C:\Users\muj20\Downloads\Gemini_Generated_Image_lesmp9lesmp9lesm-removebg-preview.png';
  final raw = img.decodePng(File(sourcePath).readAsBytesSync())!;
  final stripped = _trim(_stripNearWhiteBackground(raw));

  // --- App icon: legacy (flat, self-contained) ---
  _composite(
    source: stripped,
    canvasSize: 1024,
    contentFraction: 0.92,
    background: _background,
    outPath: 'assets/icons/app_icon_legacy.png',
  );

  // --- App icon: adaptive foreground (transparent; kept inside the ~75%
  // safe zone so circular/squircle/rounded-square launcher masks don't
  // clip it) ---
  _composite(
    source: stripped,
    canvasSize: 1024,
    contentFraction: 0.78,
    background: null,
    outPath: 'assets/icons/app_icon_foreground.png',
  );

  // --- Floating bubble: transparent, with visible padding around the
  // artwork — a real device showed 0.94 leaving almost no margin, making
  // the bubble look cramped against its circular background. ---
  _composite(
    source: stripped,
    canvasSize: 256,
    contentFraction: 0.7,
    background: null,
    outPath: 'assets/icons/bubble_icon.png',
  );

  print('Done.');
}

/// Turns near-white/light-gray pixels transparent, with a smooth ramp
/// (not a hard cutoff) so the edge doesn't come out jagged. Luminance-based
/// rather than a single "is it white" check, since the card's background is
/// a soft gradient, not a flat fill.
img.Image _stripNearWhiteBackground(img.Image source) {
  final out = source.convert(numChannels: 4);
  const whiteFloor = 232; // fully transparent at/above this luminance
  const colorCeiling = 200; // fully opaque at/below this luminance
  for (final pixel in out) {
    final luminance = (pixel.r + pixel.g + pixel.b) / 3;
    double alphaScale;
    if (luminance >= whiteFloor) {
      alphaScale = 0;
    } else if (luminance <= colorCeiling) {
      alphaScale = 1;
    } else {
      alphaScale = (whiteFloor - luminance) / (whiteFloor - colorCeiling);
    }
    pixel.a = (pixel.a * alphaScale).round();
  }
  return out;
}

/// Crops to the bounding box of non-transparent pixels, so the fraction-of-
/// canvas sizing below is relative to the funnel's own size, not the empty
/// space the original card's padding left around it.
img.Image _trim(img.Image source) {
  var minX = source.width, minY = source.height, maxX = 0, maxY = 0;
  const alphaThreshold = 12;
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      if (source.getPixel(x, y).a > alphaThreshold) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < minX || maxY < minY) return source;
  return img.copyCrop(source, x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
}

void _composite({
  required img.Image source,
  required int canvasSize,
  required double contentFraction,
  required int? background,
  required String outPath,
}) {
  final canvas = img.Image(width: canvasSize, height: canvasSize, numChannels: 4);
  if (background != null) {
    img.fill(canvas, color: img.ColorRgba8(
      (background >> 16) & 0xFF,
      (background >> 8) & 0xFF,
      background & 0xFF,
      (background >> 24) & 0xFF,
    ));
  }

  final maxContentSize = (canvasSize * contentFraction).round();
  final scale = maxContentSize / (source.width > source.height ? source.width : source.height);
  final targetWidth = (source.width * scale).round();
  final targetHeight = (source.height * scale).round();
  final resized = img.copyResize(source, width: targetWidth, height: targetHeight, interpolation: img.Interpolation.cubic);

  final offsetX = (canvasSize - targetWidth) ~/ 2;
  final offsetY = (canvasSize - targetHeight) ~/ 2;
  img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsBytesSync(img.encodePng(canvas));
  print('Wrote $outPath (${canvas.width}x${canvas.height})');
}
