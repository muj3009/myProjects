import 'package:flutter/material.dart';

/// Uppercase section label ("TODAY", "AVERAGES", "LAST JOB") shown above a
/// [SectionCard] — was independently reimplemented per-screen with slightly
/// different padding/letter-spacing; this is the single shared version.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key, this.trailing});

  final String label;

  /// Optional trailing action (e.g. "Full breakdown →") — kept optional
  /// rather than a separate widget so every section header still shares one
  /// visual treatment instead of two subtly different ones.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final labelWidget = Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 1.2,
          ),
    );
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: trailing == null
          ? labelWidget
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [labelWidget, trailing!],
            ),
    );
  }
}
