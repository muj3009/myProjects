import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/enums/job_decision.dart';

class DecisionBadge extends StatelessWidget {
  const DecisionBadge({super.key, required this.decision});

  final JobDecision decision;

  Color _color() => switch (decision) {
        JobDecision.accepted => StatusColors.accepted,
        JobDecision.rejected => StatusColors.rejected,
        JobDecision.pending => StatusColors.pendingOrUnknown,
        JobDecision.ignored => StatusColors.pendingOrUnknown,
        JobDecision.error => StatusColors.error,
        JobDecision.counterOffered => StatusColors.counterOffered,
      };

  IconData _icon() => switch (decision) {
        JobDecision.accepted => Icons.check_circle,
        JobDecision.rejected => Icons.cancel,
        JobDecision.pending => Icons.hourglass_top,
        JobDecision.ignored => Icons.visibility_off,
        JobDecision.error => Icons.error,
        JobDecision.counterOffered => Icons.swap_horiz,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon(), size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            decision.label,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                fontSize: 13),
          ),
        ],
      ),
    );
  }
}
