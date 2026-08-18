import 'package:flutter/material.dart';

/// A small gradient-filled icon badge — the same treatment was independently
/// reimplemented three times (rule rows, settings links, stat tiles) with
/// slightly different sizes/alphas; this is the single shared version so all
/// three read as one consistent visual language instead of three subtly
/// different ones.
///
/// Filled solid (with a white icon and a soft matching shadow) rather than a
/// pale alpha tint — a saturated badge reads as a deliberate design choice
/// from across the car, where a faint 12%-alpha wash was barely visible.
class TintedIconCircle extends StatelessWidget {
  const TintedIconCircle({
    super.key,
    required this.icon,
    required this.color,
    this.diameter = 40,
    this.iconSize,
  });

  final IconData icon;
  final Color color;
  final double diameter;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.28)!],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, size: iconSize ?? diameter * 0.5, color: Colors.white),
    );
  }
}
