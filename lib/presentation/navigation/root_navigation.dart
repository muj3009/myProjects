import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/state/navigation_controller.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/jobs/job_history_screen.dart';
import '../screens/rules/rules_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/statistics/statistics_screen.dart';

class _NavTab {
  const _NavTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// This tab's own identity color — shown as a solid pill behind the icon
  /// once selected. Matches the color-per-category language already used
  /// for the Jobs filter chips and every Rules row, rather than every tab
  /// sharing one generic indicator tint.
  final Color color;
}

const _tabs = [
  _NavTab(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: 'Dashboard',
      color: Color(0xFF4C6EF5)),
  _NavTab(
      icon: Icons.history_outlined,
      selectedIcon: Icons.history,
      label: 'Jobs',
      color: Color(0xFF14B8A6)),
  _NavTab(
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
      label: 'Stats',
      color: Color(0xFFA855F7)),
  _NavTab(
      icon: Icons.rule_outlined,
      selectedIcon: Icons.rule,
      label: 'Rules',
      color: Color(0xFFD4A72C)),
  _NavTab(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
      color: Color(0xFF64748B)),
];

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            color: isDark ? const Color(0xFF141519) : Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: _NavTabButton(
                    tab: _tabs[i],
                    selected: index == i,
                    onTap: () => ref.read(rootNavigationIndexProvider.notifier).state = i,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTabButton extends StatelessWidget {
  const _NavTabButton({required this.tab, required this.selected, required this.onTap});

  final _NavTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? tab.color : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: tab.color.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                selected ? tab.selectedIcon : tab.icon,
                color: selected ? Colors.white : muted,
                size: 22,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? tab.color : muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
