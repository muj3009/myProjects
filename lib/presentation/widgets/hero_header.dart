import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The full-bleed dark header zone every top-level tab screen opens with —
/// replaces a plain AppBar plus whatever card used to sit below it.
/// Extracted from the Dashboard's hero (the first screen to get this
/// treatment) so Jobs, Statistics, Rules, and Settings all share the exact
/// same shape/colour mechanics instead of four near-identical copies. Each
/// screen supplies its own [child] content (title, stats, pickers, whatever
/// that screen's hero needs to say).
///
/// The panel is deliberately *architectural*, not decorative: it runs
/// full-width and flush with the top of the screen, has square (not curved)
/// bottom corners so the content below sits snug against it, and is capped
/// by a slim [accentColor] underline. That reads as one solid, well-defined
/// zone rather than a floating rounded card — a driver glancing at the phone
/// should see a clear, closed header, not an open gap where it meets the
/// page.
class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key, required this.child, this.accentColor});

  final Widget child;

  /// The colour of the hairline at the panel's bottom edge — null uses the
  /// brand blue. Pass a state colour (e.g. green when something is actively
  /// running) to tie the boldest signal on the screen to that state, the way
  /// the Dashboard's hero does.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppTheme.accentBlue;
    return Container(
      width: double.infinity,
      color: AppTheme.ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + 8,
                16,
                14),
            child: child,
          ),
          // A crisp accent underline that "closes" the panel and gives it a
          // defined bottom boundary — without it the header would fade into
          // the page and read as open/unfinished.
          Container(height: 3, color: accent),
        ],
      ),
    );
  }
}
