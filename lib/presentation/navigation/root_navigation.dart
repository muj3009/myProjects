import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/state/navigation_controller.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/jobs/job_history_screen.dart';
import '../screens/rules/rules_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/statistics/statistics_screen.dart';

/// Top-level navigation shell (spec section 30): Dashboard, Jobs,
/// Statistics, Rules, Settings. Kept as a simple IndexedStack so switching
/// tabs never reloads a screen's state or triggers extra animation.
class RootNavigation extends ConsumerWidget {
  const RootNavigation({super.key});

  static const _screens = [
    DashboardScreen(),
    JobHistoryScreen(),
    StatisticsScreen(),
    RulesScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(rootNavigationIndexProvider);
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: index, children: _screens)),
      // A pill-shaped bar floating above the screen edge (margin + rounded
      // corners + shadow) instead of a bar flush with the bottom reads as
      // deliberately designed rather than default Material chrome.
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) =>
                  ref.read(rootNavigationIndexProvider.notifier).state = i,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
                NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: 'Jobs'),
                NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Stats'),
                NavigationDestination(icon: Icon(Icons.rule_outlined), selectedIcon: Icon(Icons.rule), label: 'Rules'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
