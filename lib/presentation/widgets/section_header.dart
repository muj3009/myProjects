import 'package:flutter/material.dart';

/// Uppercase section label ("TODAY", "AVERAGES", "LAST JOB") shown above a
/// [SectionCard] — was independently reimplemented per-screen with slightly
/// different padding/letter-spacing; this is the single shared version.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}
