import 'package:flutter/material.dart';

import 'tinted_icon_circle.dart';

class StatTile extends StatelessWidget {
  const StatTile(
      {super.key,
      required this.label,
      required this.value,
      this.color,
      this.icon});

  final String label;
  final String value;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          TintedIconCircle(icon: icon!, color: tint, diameter: 34, iconSize: 18),
          const SizedBox(height: 10),
        ],
        Text(
          value,
          style: theme.textTheme.headlineMedium
              ?.copyWith(color: color, fontSize: 24),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
