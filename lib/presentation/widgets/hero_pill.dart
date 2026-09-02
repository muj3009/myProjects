import 'package:flutter/material.dart';

/// A small translucent-white pill for a short fact inside a [HeroHeader]
/// (e.g. "£2.00/mile min", "3 accepted") — the dark-hero equivalent of a
/// [Chip], since Chip's theme assumes a light surface behind it.
class HeroPill extends StatelessWidget {
  const HeroPill({super.key, required this.label, this.color});

  final String label;

  /// Optional identity colour (e.g. a rule's colour on the Rules screen).
  /// When null the pill stays translucent white; when provided the background
  /// and border are tinted with this colour so a pill can read as belonging
  /// to the same rule as its counterpart elsewhere in the app.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color;
    final hasColor = c != null;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: hasColor
            ? c.withValues(alpha: 0.20)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: hasColor
            ? Border.all(color: c.withValues(alpha: 0.55))
            : null,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
