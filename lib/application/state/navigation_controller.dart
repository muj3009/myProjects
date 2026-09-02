import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tab index constants for the bottom navigation. Centralised so screens that
/// deep-link to another tab (Dashboard -> Jobs/Stats, Settings -> Rules) use
/// a named constant rather than a bare magic number.
abstract final class RootTabs {
  static const int dashboard = 0;
  static const int jobs = 1;
  static const int stats = 2;
  static const int rules = 3;
  static const int settings = 4;
}

/// Which bottom-navigation tab is currently showing (see [RootTabs]).
/// Lifted out of RootNavigation's own State
/// into a provider so other screens can deep-link to a tab (e.g. the
/// Dashboard's "View all jobs" / "Full breakdown" links) without
/// RootNavigation needing to know anything about the screens that jump to it.
final rootNavigationIndexProvider = StateProvider<int>((ref) => 0);
