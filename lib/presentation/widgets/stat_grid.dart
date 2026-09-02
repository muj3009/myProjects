import 'package:flutter/material.dart';

/// Lays out [StatTile]s two per row, each row sized to its own content's
/// natural height instead of a fixed aspect ratio.
///
/// The previous `GridView.count(childAspectRatio: ...)` approach forces cell
/// *height* down as cell *width* shrinks on a narrower screen — but a
/// StatTile's actual content height doesn't shrink to match (text just
/// wraps more), so a fixed ratio is guaranteed to overflow at some screen
/// width or font scale. A driver on a smaller phone hit exactly this
/// ("BOTTOM OVERFLOWED BY 14 PIXELS"). A plain Row/Column per pair has no
/// such ceiling — it always sizes to whatever the content actually needs.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: tiles[i]),
              if (i + 1 < tiles.length) ...[
                const SizedBox(width: 10),
                Expanded(child: tiles[i + 1]),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
