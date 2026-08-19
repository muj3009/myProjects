import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which bottom-navigation tab is currently showing: Dashboard=0, Jobs=1,
/// Stats=2, Rules=3, Settings=4. Lifted out of RootNavigation's own State
/// into a provider so other screens can deep-link to a tab (e.g. the
/// Dashboard's "View all jobs" / "Full breakdown" links) without
/// RootNavigation needing to know anything about the screens that jump to it.
final rootNavigationIndexProvider = StateProvider<int>((ref) => 0);
