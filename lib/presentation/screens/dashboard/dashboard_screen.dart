import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/controllers/automation_controller.dart';
import '../../../application/controllers/automation_state.dart';
import '../../../application/state/navigation_controller.dart';
import '../../../application/state/settings_controller.dart';
import '../../../application/state/statistics_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/driver_settings.dart';
import '../../../domain/entities/rule_config.dart';
import '../../../domain/enums/distance_unit.dart';
import '../../../domain/enums/platform_type.dart';
import '../../widgets/decision_badge.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/hero_pill.dart';
import '../../widgets/section_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/tinted_icon_circle.dart';
import '../permissions/permissions_screen.dart';
import '../simulation/simulation_screen.dart';

/// Main screen (spec sections 4/31) — automation status, quick stats, and
/// the two most important controls a driver needs: start and emergency stop.
///
/// Built around one real edge-to-edge hero zone rather than a card that
/// merely *looks* like one floating on a flat scaffold — the previous
/// version kept every element in individually-bordered white/gray cards, so
/// no matter how each card was decorated the page still read as generic
/// Material chrome. The hero's own gradient shifts from ink toward green
/// when automation is active — the single boldest visual signal on the
/// screen is now tied directly to the thing a driver actually glances down
/// to check, not decoration for its own sake.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> with WidgetsBindingObserver {
  bool _showSetupHighlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initial check on first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(automationControllerProvider.notifier).refreshAccessibilityStatus();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check accessibility when app resumes (e.g., after returning from settings)
      ref.read(automationControllerProvider.notifier).refreshAccessibilityStatus();
    }
  }

  void _handleStartAutomation(AutomationController controller) {
    final automation = ref.read(automationControllerProvider);
    if (!automation.debug.accessibilityConnected) {
      setState(() => _showSetupHighlight = true);
    } else {
      controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final automation = ref.watch(automationControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(automationControllerProvider.notifier);
    final stats = ref.watch(statisticsControllerProvider).statistics;

    ref.listen<int>(
      automationControllerProvider.select((s) => s.jobsProcessed),
      (previous, next) {
        if (previous != next) {
          ref.read(statisticsControllerProvider.notifier).refresh();
        }
      },
    );

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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            _DashboardHero(
                automation: automation, settings: settings, minRule: minRule),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                children: [
                  if (!automation.isSupported)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SimulationScreen()),
                      ),
                      icon: const Icon(Icons.science_outlined),
                      label: const Text('Open Simulation Mode'),
                    )
                  else if (automation.isActive)
                    GradientButton(
                      icon: Icons.stop_circle_outlined,
                      label: 'STOP AUTOMATION',
                      baseColor: const Color(0xFF4E030C),
                      onPressed: controller.stop,
                    )
                  else
                    GradientButton(
                      icon: Icons.play_circle_outline,
                      label: 'START AUTOMATION',
                      baseColor: StatusColors.accepted,
                      borderRadius: 16,
                      onPressed: () => _handleStartAutomation(controller),
                    ),
                  if (automation.isSupported && !automation.isActive) ...[
                    const SizedBox(height: 6),
                    // Highlight when user tried to start but accessibility isn't connected
                    Builder(builder: (context) {
                      final needsSetup = _showSetupHighlight;
                      return Container(
                        decoration: BoxDecoration(
                          color: needsSetup
                              ? Theme.of(context).colorScheme.errorContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: needsSetup
                              ? Border.all(color: Theme.of(context).colorScheme.error, width: 2)
                              : null,
                        ),
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            foregroundColor: needsSetup
                                ? Theme.of(context).colorScheme.onErrorContainer
                                : null,
                          ),
                          onPressed: () {
                            setState(() => _showSetupHighlight = false);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const PermissionsScreen()),
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (needsSetup) ...[
                                Icon(Icons.warning_amber_rounded,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.onErrorContainer),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                needsSetup
                                    ? 'Press here to enable permissions'
                                    : 'Check permissions / setup',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 12),
                  if (automation.lastJob != null) ...[
                    _LastJobCard(automation: automation),
                    const SizedBox(height: 12),
                  ],
                  SectionHeader(
                    'TODAY',
                    trailing: _HeaderLink(
                      label: 'Full breakdown',
                      onTap: () => ref
                          .read(rootNavigationIndexProvider.notifier)
                          .state = RootTabs.stats,
                    ),
                  ),
                  SectionCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: StatTile(
                              label: 'Jobs seen',
                              value: '${stats.jobsDetected}',
                              icon: Icons.list_alt),
                        ),
                        Expanded(
                          child: StatTile(
                            label: 'Accepted',
                            value: '${stats.jobsAccepted}',
                            color: StatusColors.accepted,
                            icon: Icons.check_circle,
                          ),
                        ),
                        Expanded(
                          child: StatTile(
                            label: 'Rejected',
                            value: '${stats.jobsRejected}',
                            color: StatusColors.rejected,
                            icon: Icons.cancel,
                          ),
                        ),
                        Expanded(
                          child: StatTile(
                            label: 'Avg £/mile',
                            value:
                                '£${stats.averagePoundsPerMile.toStringAsFixed(2)}',
                            icon: Icons.attach_money,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!automation.isSupported)
                    _IosNotSupportedCard(reason: automation.unsupportedReason!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The full-bleed status header — replaces both the old AppBar and the
/// bordered "hero card" with one continuous colored zone that extends
/// behind the status bar. Rounded only at the bottom, so it reads as a
/// distinct region the rest of the page sits below rather than a card
/// floating on the scaffold.
class _DashboardHero extends StatefulWidget {
  const _DashboardHero(
      {required this.automation,
      required this.settings,
      required this.minRule});

  final AutomationState automation;
  final DriverSettings settings;
  final ThresholdRule minRule;

  @override
  State<_DashboardHero> createState() => _DashboardHeroState();
}

class _DashboardHeroState extends State<_DashboardHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _accentCtrl;
  late Animation<Color?> _accentColor;

  Color get _inactiveAccent => AppTheme.accentBlue;
  Color get _activeAccent => StatusColors.accepted;

  @override
  void initState() {
    super.initState();
    final isActive = widget.automation.isActive;
    _accentCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _accentColor = ColorTween(
      begin: isActive ? _activeAccent : _inactiveAccent,
      end: isActive ? _activeAccent : _inactiveAccent,
    ).animate(CurvedAnimation(parent: _accentCtrl, curve: Curves.easeInOut));
    if (isActive) _accentCtrl.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant _DashboardHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasActive = oldWidget.automation.isActive;
    final isActive = widget.automation.isActive;
    if (wasActive != isActive) {
      _accentColor = ColorTween(
        begin: wasActive ? _activeAccent : _inactiveAccent,
        end: isActive ? _activeAccent : _inactiveAccent,
      ).animate(CurvedAnimation(parent: _accentCtrl, curve: Curves.easeInOut));
      _accentCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _accentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.automation.isActive;
    final settings = widget.settings;
    final minRule = widget.minRule;
    return AnimatedBuilder(
      animation: _accentCtrl,
      builder: (context, _) {
        final accent = _accentColor.value!;
        return Container(
          width: double.infinity,
          color: AppTheme.ink,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                    16, MediaQuery.of(context).padding.top + 10, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.appName,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.3),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _PulsingStatusDot(
                            active: isActive,
                            color:
                                isActive ? StatusColors.accepted : Colors.white70),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isActive ? 'AUTOMATION ACTIVE' : 'AUTOMATION OFF',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                                letterSpacing: 0.2),
                          ),
                        ),
                        TintedIconCircle(
                          icon: Icons.bolt,
                          color:
                              isActive ? StatusColors.accepted : AppTheme.accentBlue,
                          diameter: 38,
                          iconSize: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.automation.statusMessage,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _HeroStatChip(
                            icon: Icons.speed,
                            label: 'Minimum / mile',
                            value: minRule.enabled
                                ? '£${minRule.value.toStringAsFixed(2)}'
                                : 'Off',
                            active: isActive,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _HeroStatChip(
                            icon: Icons.local_taxi_outlined,
                            label: 'Platform',
                            value: settings.platformSelection.name,
                            active: isActive,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _ActiveFiltersPills(rules: settings.rules,
                        distanceUnitLabel: _distanceUnitLabel(settings)),
                  ],
                ),
              ),
              // The animated accent underline — blue when idle, animating to
              // green when automation is running. Ties the state signal to a
              // crisp, closed boundary at the panel's edge (matching the
              // shared HeroHeader) instead of a floating gradient.
              Container(height: 3, color: accent),
            ],
          ),
        );
      },
    );
  }
}

String _distanceUnitLabel(DriverSettings settings) =>
    settings.distanceUnit == DistanceUnit.miles ? 'mi' : 'km';

/// The full list of filters that are actually active right now, shown on the
/// dark hero as flowing [HeroPill]s — the same "everything I switched on at a
/// glance" summary the Rules screen's hero gives, so a driver doesn't have to
/// jump to Rules to confirm what their current job-filters are doing. Built
/// from the exact same threshold objects the decision engine reads, so the
/// summary can never drift from what automation actually applies.
class _ActiveFiltersPills extends StatelessWidget {
  const _ActiveFiltersPills({
    required this.rules,
    required this.distanceUnitLabel,
  });

  final RuleConfig rules;
  final String distanceUnitLabel;

  @override
  Widget build(BuildContext context) {
    // One (label, colour) per active filter. The colours deliberately mirror
    // each rule row's colour in the Rules screen (rules_screen.dart /
    // widgets/*_tile.dart) so a driver can match a dashboard pill to the
    // same filter in Rules at a glance.
    final active = <(String, Color)>[
      if (rules.maximumPickupDistanceMiles.enabled)
        ('Pickup ≤ ${rules.maximumPickupDistanceMiles.value.toStringAsFixed(1)} $distanceUnitLabel',
            const Color(0xFFA855F7)),
      if (rules.minimumFare.enabled)
        ('Fare ≥ £${rules.minimumFare.value.toStringAsFixed(2)}',
            const Color(0xFF2FA968)),
      if (rules.maximumTripDistanceMiles.enabled)
        ('Trip ≤ ${rules.maximumTripDistanceMiles.value.toStringAsFixed(1)} $distanceUnitLabel',
            const Color(0xFF14B8A6)),
      if (rules.minimumHourlyRate.enabled)
        ('£${rules.minimumHourlyRate.value.toStringAsFixed(2)}/hr min',
            const Color(0xFFEC4899)),
      if (rules.postcodeBlocklist.enabled &&
          rules.postcodeBlocklist.blockedPrefixes.isNotEmpty)
        ('${rules.postcodeBlocklist.blockedPrefixes.length} area'
                '${rules.postcodeBlocklist.blockedPrefixes.length == 1 ? '' : 's'} blocked',
            const Color(0xFFE5484D)),
      if (rules.counterOfferBandPercent.enabled)
        ('Counter near-miss ${rules.counterOfferBandPercent.value.toStringAsFixed(0)}%',
            const Color(0xFFD4A72C)),
      if (rules.lowFareCounterOfferThreshold.enabled)
        ('Auto counter < £${rules.lowFareCounterOfferThreshold.value.toStringAsFixed(2)}',
            const Color(0xFF84CC16)),
      if (rules.highValueJob.enabled)
        ('High-value £${rules.highValueJob.fareFloor.toStringAsFixed(0)}+'
                ' @ £${rules.highValueJob.acceptRateFloor.toStringAsFixed(2)}/mi',
            const Color(0xFF4338CA)),
      if (rules.quietTimeMinimumPoundsPerMile.enabled)
        ('Quiet min £${rules.quietTimeMinimumPoundsPerMile.value.toStringAsFixed(2)}/mi',
            const Color(0xFFB45309)),
    ];

    if (active.isEmpty) {
      return Text(
        'No extra filters — every job below is passed through.',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (label, color) in active) HeroPill(label: label, color: color),
      ],
    );
  }
}

/// A "glass" stat panel for use on the dark hero — deliberately hardcoded
/// white/white70 text rather than pulling from the ambient [Theme], because
/// this panel is always dark regardless of the app's light/dark theme mode
/// (matching the app bar's own fixed-ink precedent), unlike [StatTile] which
/// assumes a light card background.
class _HeroStatChip extends StatelessWidget {
  const _HeroStatChip({
    required this.icon,
    required this.label,
    required this.value,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final String value;

  /// When true (automation running), the panel gets a green-tinted background
  /// so it reads as "live/active"; when false it falls back to a muted grey
  /// that reads as inactive.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final fill = active
        ? StatusColors.accepted.withValues(alpha: 0.16)
        : Colors.white.withValues(alpha: 0.06);
    final border = active
        ? StatusColors.accepted.withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.10);
    final iconColor =
        active ? StatusColors.accepted : Colors.white54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: active ? Colors.white : Colors.white54, fontSize: 11)),
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
                style: TextStyle(
                    color: primary, fontWeight: FontWeight.w700, fontSize: 13)),
            Icon(Icons.chevron_right, color: primary, size: 16),
          ],
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
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
              DecisionBadge(decision: job.decision),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: _HeaderLink(
              label: 'View all jobs',
              onTap: () =>
                  ref.read(rootNavigationIndexProvider.notifier).state =
                      RootTabs.jobs,
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

/// A ring-and-dot status indicator instead of a plain filled circle — the
/// extra ring reads as a "live" signal (echoing the pulsing dot pattern
/// drivers already recognise from Uber/Bolt's own "online" indicators) when
/// automation is active, and collapses to a flat gray dot when it's off so
/// the two states are unmistakable even at a glance.
class _PulsingStatusDot extends StatefulWidget {
  const _PulsingStatusDot({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  State<_PulsingStatusDot> createState() => _PulsingStatusDotState();
}

class _PulsingStatusDotState extends State<_PulsingStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _pulse = Tween<double>(begin: 1.0, end: 1.55).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.active) _startPulse();
  }

  void _startPulse() {
    _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulsingStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_ctrl.isAnimating) {
      _startPulse();
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final scale = widget.active ? _pulse.value : 1.0;
        final outerAlpha = widget.active ? 0.22 : 0.0;
        return SizedBox(
          width: 16,
          height: 16,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.active)
                Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withValues(alpha: outerAlpha),
                    ),
                  ),
                ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
