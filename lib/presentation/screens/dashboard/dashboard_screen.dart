import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/controllers/automation_controller.dart';
import '../../../application/controllers/automation_state.dart';
import '../../../application/state/navigation_controller.dart';
import '../../../application/state/settings_controller.dart';
import '../../../application/state/statistics_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/enums/platform_type.dart';
import '../../widgets/decision_badge.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/section_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/tinted_icon_circle.dart';
import '../permissions/permissions_screen.dart';
import '../simulation/simulation_screen.dart';

/// Main screen (spec sections 4/31) — automation status, quick stats, and
/// the two most important controls a driver needs: start and emergency stop.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final automation = ref.watch(automationControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final stats = ref.watch(statisticsControllerProvider).statistics;

    ref.listen<int>(
      automationControllerProvider.select((s) => s.jobsProcessed),
      (previous, next) {
        if (previous != next) {
          ref.read(statisticsControllerProvider.notifier).refresh();
        }
      },
    );

    return Scaffold(
      // The app bar title already identifies the screen — a generic,
      // unpersonalized "Good morning" underneath it repeated that without
      // adding any information, so the automation status card (the thing a
      // driver actually opens this screen to check) is now the first thing
      // on the page instead of the third.
      appBar: AppBar(title: Text(settings.appName), centerTitle: false),
      // A soft ambient glow behind the top of the page instead of a flat
      // scaffold background — sits behind the ListView (painted first in the
      // Stack), showing through the gaps around and behind the hero card's
      // rounded corners rather than a hard cut from the app bar's ink to a
      // plain neutral background.
      body: Stack(
        children: [
          Positioned(
            top: -90,
            right: -70,
            child: Container(
              width: 280,
              height: 280,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x1A11141C), Colors.transparent],
                ),
              ),
            ),
          ),
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _AutomationStatusCard(automation: automation),
              const SizedBox(height: 16),
              if (automation.lastJob != null) ...[
                _LastJobCard(automation: automation),
                const SizedBox(height: 16),
              ],
              SectionHeader(
                'TODAY',
                trailing: _HeaderLink(
                  label: 'Full breakdown',
                  onTap: () => ref.read(rootNavigationIndexProvider.notifier).state = 2,
                ),
              ),
              SectionCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatTile(
                        label: 'Jobs seen',
                        value: '${stats.jobsDetected}',
                        icon: Icons.list_alt),
                    StatTile(
                      label: 'Accepted',
                      value: '${stats.jobsAccepted}',
                      color: StatusColors.accepted,
                      icon: Icons.check_circle,
                    ),
                    StatTile(
                      label: 'Rejected',
                      value: '${stats.jobsRejected}',
                      color: StatusColors.rejected,
                      icon: Icons.cancel,
                    ),
                    StatTile(
                      label: 'Avg £/mile',
                      value: '£${stats.averagePoundsPerMile.toStringAsFixed(2)}',
                      icon: Icons.attach_money,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (!automation.isSupported)
                _IosNotSupportedCard(reason: automation.unsupportedReason!),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small "go look at the full picture" link — used to send the driver from
/// a Dashboard summary to the screen that actually owns that data (Jobs
/// History, Statistics) instead of the Dashboard trying to also be those
/// screens. Two call sites; kept as one widget so both read identically.
class _HeaderLink extends StatelessWidget {
  const _HeaderLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 13)),
            Icon(Icons.chevron_right, color: primary, size: 16),
          ],
        ),
      ),
    );
  }
}

class _AutomationStatusCard extends ConsumerWidget {
  const _AutomationStatusCard({required this.automation});

  final AutomationState automation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(automationControllerProvider.notifier);
    // The *effective* rule for whichever single platform is selected, not
    // just the global default — a platform-specific override (Rules screen)
    // can silently diverge from it. Showing the global rule here regardless
    // let a disabled Uber-only override go completely unnoticed on a real
    // device: the Dashboard kept saying "£2.00 Minimum/mile" while Uber jobs
    // were actually being accepted with no £/mile check applied at all.
    // "Both" platforms selected can't be collapsed into one number if they
    // genuinely differ, so that case still shows the global rule.
    final singlePlatform = switch (settings.platformSelection) {
      PlatformSelection.uber => PlatformType.uber,
      PlatformSelection.bolt => PlatformType.bolt,
      PlatformSelection.both => null,
    };
    final minRule = singlePlatform != null
        ? settings.rulesFor(singlePlatform).minimumPoundsPerMile
        : settings.rules.minimumPoundsPerMile;

    final statusColor = automation.isActive
        ? StatusColors.accepted
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: (automation.isActive ? StatusColors.accepted : Colors.black)
                .withValues(
              alpha: automation.isActive ? 0.16 : 0.05,
            ),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: automation.isActive
                ? StatusColors.accepted.withValues(alpha: 0.4)
                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            width: automation.isActive ? 1.5 : 1.5,
          ),
        ),
        child: Container(
          // A richer, saturated wash on *both* states (not just when active)
          // is what keeps the card from looking flat/unfinished the moment
          // automation is off — the color just shifts from green to the
          // brand blue instead of disappearing entirely. Boosted to roughly
          // the same visual weight as the active state's wash (was ~half as
          // strong) — "off" was reading as an unstyled fallback rather than
          // a deliberate second state of the same card.
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: automation.isActive
                  ? [
                      StatusColors.accepted.withValues(alpha: 0.22),
                      StatusColors.accepted.withValues(alpha: 0.04),
                    ]
                  : [
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.03),
                    ],
            ),
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        _StatusDot(active: automation.isActive, color: statusColor),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            automation.isActive
                                ? 'AUTOMATION ACTIVE'
                                : 'AUTOMATION OFF',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: automation.isActive
                                      ? StatusColors.accepted
                                      : null,
                                  letterSpacing: 0.3,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TintedIconCircle(
                    icon: Icons.bolt,
                    color: automation.isActive
                        ? StatusColors.accepted
                        : Theme.of(context).colorScheme.primary,
                    diameter: 44,
                    iconSize: 24,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                automation.statusMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StatChip(
                      child: StatTile(
                        label: 'Minimum / mile',
                        value: minRule.enabled
                            ? '£${minRule.value.toStringAsFixed(2)}'
                            : 'Off',
                        icon: Icons.speed,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatChip(
                      child: StatTile(
                        label: 'Platform',
                        value: settings.platformSelection.name,
                        icon: Icons.local_taxi_outlined,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (!automation.isSupported)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SimulationScreen()),
                  ),
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Open Simulation Mode'),
                )
              else if (automation.isActive)
                GradientButton(
                  icon: Icons.stop_circle_outlined,
                  label: 'STOP AUTOMATION',
                  baseColor: StatusColors.rejected,
                  onPressed: controller.stop,
                )
              else
                GradientButton(
                  icon: Icons.play_circle_outline,
                  label: 'START AUTOMATION',
                  baseColor: StatusColors.accepted,
                  onPressed: controller.start,
                ),
              if (automation.isSupported && !automation.isActive) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const PermissionsScreen()),
                  ),
                  child: const Text('Check permissions / setup'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LastJobCard extends ConsumerWidget {
  const _LastJobCard({required this.automation});

  final AutomationState automation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = automation.lastJob!;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LAST JOB',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          letterSpacing: 1.0,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    job.fare != null
                        ? '£${job.fare!.toStringAsFixed(2)}'
                        : 'Fare unknown',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  if (job.tripDistanceMiles != null)
                    Text(
                      '${job.tripDistanceMiles!.toStringAsFixed(1)} miles'
                      '${job.poundsPerMile != null ? ' · £${job.poundsPerMile!.toStringAsFixed(2)}/mile' : ''}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
              DecisionBadge(decision: job.decision),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _HeaderLink(
              label: 'View all jobs',
              onTap: () => ref.read(rootNavigationIndexProvider.notifier).state = 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _IosNotSupportedCard extends StatelessWidget {
  const _IosNotSupportedCard({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        children: [
          Icon(Icons.info_outline,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(reason)),
        ],
      ),
    );
  }
}

/// Wraps a [StatTile] in a translucent rounded chip — on its own, a
/// StatTile floating directly on the hero card's colored gradient wash had
/// nothing separating it from the background, especially once that wash
/// was strengthened for the "off" state. A soft surface-tinted panel gives
/// each mini-stat a real edge without competing with the card's own border.
class _StatChip extends StatelessWidget {
  const _StatChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

/// A ring-and-dot status indicator instead of a plain filled circle — the
/// extra ring reads as a "live" signal (echoing the pulsing dot pattern
/// drivers already recognise from Uber/Bolt's own "online" indicators) when
/// automation is active, and collapses to a flat gray dot when it's off so
/// the two states are unmistakable even at a glance.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (active)
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: color.withValues(alpha: 0.25)),
            ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ],
      ),
    );
  }
}
