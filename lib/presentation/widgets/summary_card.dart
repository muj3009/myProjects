import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A dark "ink" card summarizing the current state of a screen in one
/// glance — a headline plus a row of pill chips, or a plain empty message
/// when there's nothing to summarize yet. Shared between the Rules screen
/// ("is my setup actually what I think it is") and the Jobs screen ("how's
/// my day going") rather than reimplemented per screen — the same "verify
/// at a glance" job-to-be-done shows up on both.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.icon,
    required this.headline,
    this.emptyMessage,
    this.chips = const [],
  });

  final IconData icon;
  final String headline;
  final String? emptyMessage;
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ],
          ),
          if (chips.isEmpty && emptyMessage != null) ...[
            const SizedBox(height: 6),
            Text(emptyMessage!, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
          ] else if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
