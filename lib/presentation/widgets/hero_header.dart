import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The full-bleed, rounded-bottom dark gradient zone every top-level tab
/// screen opens with — replaces a plain AppBar plus whatever card used to
/// sit below it. Extracted from the Dashboard's hero (the first screen to
/// get this treatment) so Jobs, Statistics, Rules, and Settings all share
/// the exact same shape/gradient mechanics instead of four near-identical
/// copies. Each screen supplies its own [child] content (title, stats,
/// pickers, whatever that screen's hero needs to say).
class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key, required this.child, this.accentColor});

  final Widget child;

  /// The color the gradient shifts toward — null keeps the header a plain
  /// ink-to-brand-blue wash; pass a state color (e.g. green when something
  /// is actively running) to tie the boldest visual signal on the screen to
  /// that state, the way the Dashboard's hero does.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.ink,
            Color.lerp(AppTheme.ink, accentColor ?? AppTheme.accentBlue, accentColor != null ? 0.5 : 0.35)!,
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: child,
    );
  }
}
