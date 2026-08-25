import 'package:flutter/material.dart';

/// Consistent card wrapper used across screens so the dashboard, rules, and
/// settings all share the same rounded, low-clutter container (spec section 30).
///
/// Built on a plain [Container] rather than [Card] so a soft drop shadow can
/// sit alongside the theme's hairline border — [CardTheme]'s own elevation
/// system doesn't produce this kind of low, wide, barely-there shadow (it
/// either renders nothing at elevation 0 or a much harder Material shadow at
/// elevation 1+), and a real device showed the hairline border alone still
/// reads as flat against a similarly-toned scaffold background.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final cardTheme = Theme.of(context).cardTheme;
    final shape = cardTheme.shape as RoundedRectangleBorder?;
    return Container(
      decoration: BoxDecoration(
        color: cardTheme.color,
        borderRadius:
            shape?.borderRadius as BorderRadius? ?? BorderRadius.circular(16),
        border: shape?.side != null ? Border.fromBorderSide(shape!.side) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}
