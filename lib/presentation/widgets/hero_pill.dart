import 'package:flutter/material.dart';

/// A small translucent-white pill for a short fact inside a [HeroHeader]
/// (e.g. "£2.00/mile min", "3 accepted") — the dark-hero equivalent of a
/// [Chip], since Chip's theme assumes a light surface behind it.
class HeroPill extends StatelessWidget {
  const HeroPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
