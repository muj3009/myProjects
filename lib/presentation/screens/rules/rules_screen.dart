import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/state/settings_controller.dart';
import '../../../domain/entities/rule_config.dart';
import '../../../domain/enums/distance_unit.dart';
import '../../../domain/enums/platform_type.dart';
import '../../widgets/section_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/summary_card.dart';
import 'widgets/postcode_blocklist_tile.dart';
import 'widgets/threshold_rule_tile.dart';

/// Rule Builder (spec section 6/11/32) — every rule is independently
/// enable-able, and the list is driven by data rather than one hard-coded
/// screen per rule, so a new rule only needs a new [ThresholdRuleTile] entry.
///
/// Structured in three tiers rather than one flat stack of equal-weight
/// cards: a live summary of what's actually active (so a driver can verify
/// their setup without reading every row), the one rule that matters most
/// (minimum £/mile) featured on its own, and everything else grouped into a
/// single divided list — a disabled rule now costs one line, not a full card.
class RulesScreen extends ConsumerWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final rules = settings.rules;

    void updateRules(RuleConfig Function(RuleConfig) transform) {
      controller.update((s) => s.copyWith(rules: transform(s.rules)));
    }

    final distanceUnitLabel =
        settings.distanceUnit == DistanceUnit.miles ? 'mi' : 'km';

    return Scaffold(
      appBar: AppBar(title: const Text('Rules')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _RulesSummaryCard(rules: rules, distanceUnitLabel: distanceUnitLabel),
          const SizedBox(height: 24),
          const SectionHeader('CORE RULE'),
          _FeaturedRuleCard(
            child: ThresholdRuleTile(
              title: 'Minimum £/mile',
              subtitle: 'The core rule — reject anything below this rate.',
              unitPrefix: '£',
              unitSuffix: '/mile',
              icon: Icons.attach_money,
              rule: rules.minimumPoundsPerMile,
              emphasized: true,
              onChanged: (r) =>
                  updateRules((c) => c.copyWith(minimumPoundsPerMile: r)),
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader('ADDITIONAL FILTERS'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                ThresholdRuleTile(
                  title: 'Maximum pickup distance',
                  subtitle: 'Long drives just to reach the passenger.',
                  unitSuffix: ' $distanceUnitLabel',
                  icon: Icons.social_distance,
                  rule: rules.maximumPickupDistanceMiles,
                  onChanged: (r) => updateRules(
                      (c) => c.copyWith(maximumPickupDistanceMiles: r)),
                ),
                const _RowDivider(),
                ThresholdRuleTile(
                  title: 'Minimum fare',
                  subtitle: 'A flat fare floor, regardless of £/mile.',
                  unitPrefix: '£',
                  icon: Icons.payments_outlined,
                  rule: rules.minimumFare,
                  onChanged: (r) => updateRules((c) => c.copyWith(minimumFare: r)),
                ),
                const _RowDivider(),
                ThresholdRuleTile(
                  title: 'Maximum trip distance',
                  subtitle: 'Reject unusually long trips.',
                  unitSuffix: ' $distanceUnitLabel',
                  icon: Icons.route_outlined,
                  rule: rules.maximumTripDistanceMiles,
                  onChanged: (r) =>
                      updateRules((c) => c.copyWith(maximumTripDistanceMiles: r)),
                ),
                const _RowDivider(),
                ThresholdRuleTile(
                  title: 'Minimum estimated hourly rate',
                  subtitle: 'Only when a duration estimate is available.',
                  unitPrefix: '£',
                  unitSuffix: '/hour',
                  icon: Icons.schedule_outlined,
                  rule: rules.minimumHourlyRate,
                  onChanged: (r) =>
                      updateRules((c) => c.copyWith(minimumHourlyRate: r)),
                ),
                const _RowDivider(),
                PostcodeBlocklistTile(
                  config: rules.postcodeBlocklist,
                  onChanged: (c) =>
                      updateRules((r) => r.copyWith(postcodeBlocklist: c)),
                ),
                const _RowDivider(),
                ThresholdRuleTile(
                  title: 'Counter-offer near-miss jobs (Bolt)',
                  subtitle: '% of your minimum £/mile that still gets a counter.',
                  unitSuffix: '%',
                  icon: Icons.swap_horiz,
                  rule: rules.counterOfferBandPercent,
                  onChanged: (r) =>
                      updateRules((c) => c.copyWith(counterOfferBandPercent: r)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader('£/MILE CALCULATION'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                RadioListTile<DistanceCalculationMode>(
                  title: const Text('Trip distance'),
                  subtitle:
                      const Text('fare ÷ passenger trip distance (default)'),
                  value: DistanceCalculationMode.tripDistance,
                  groupValue: settings.distanceCalculationMode,
                  selected: settings.distanceCalculationMode ==
                      DistanceCalculationMode.tripDistance,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.07),
                  activeColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  onChanged: (mode) => controller.update(
                    (s) => s.copyWith(distanceCalculationMode: mode),
                  ),
                ),
                RadioListTile<DistanceCalculationMode>(
                  title: const Text('Total driving distance'),
                  subtitle: const Text('fare ÷ (pickup + trip distance)'),
                  value: DistanceCalculationMode.totalDrivingDistance,
                  groupValue: settings.distanceCalculationMode,
                  selected: settings.distanceCalculationMode ==
                      DistanceCalculationMode.totalDrivingDistance,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.07),
                  activeColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  onChanged: (mode) => controller.update(
                    (s) => s.copyWith(distanceCalculationMode: mode),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader('PLATFORM OVERRIDES'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final platform in [PlatformType.uber, PlatformType.bolt]) ...[
                  if (platform == PlatformType.bolt) const _RowDivider(),
                  _PlatformOverrideTile(platform: platform),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Divider aligned to sit under each row's title (past the 38px icon + 12px
/// gap + 16px row padding), not flush against the card edge — matches the
/// grouped-list pattern already used on the Settings screen.
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        indent: 66,
        endIndent: 8,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
      );
}

/// A soft primary-tinted wash around the one rule that matters most — the
/// same "featured card" language the Dashboard's automation status card
/// uses — so it visually anchors the page instead of reading as one row
/// among seven.
class _FeaturedRuleCard extends StatelessWidget {
  const _FeaturedRuleCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary.withValues(alpha: 0.14), primary.withValues(alpha: 0.03)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primary.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: child,
    );
  }
}

/// "Did I actually set this up right?" at a glance — the single highest-value
/// addition to this screen: previously verifying the driver's own rule setup
/// meant scrolling and reading every card. Empty when no filters are active
/// so the fallback behavior (every job passes through) is stated plainly
/// rather than just... absent.
class _RulesSummaryCard extends StatelessWidget {
  const _RulesSummaryCard({required this.rules, required this.distanceUnitLabel});

  final RuleConfig rules;
  final String distanceUnitLabel;

  @override
  Widget build(BuildContext context) {
    final active = <String>[
      if (rules.minimumPoundsPerMile.enabled)
        '£${rules.minimumPoundsPerMile.value.toStringAsFixed(2)}/mile min',
      if (rules.maximumPickupDistanceMiles.enabled)
        'Max ${rules.maximumPickupDistanceMiles.value.toStringAsFixed(1)} $distanceUnitLabel pickup',
      if (rules.minimumFare.enabled)
        '£${rules.minimumFare.value.toStringAsFixed(2)} min fare',
      if (rules.maximumTripDistanceMiles.enabled)
        'Max ${rules.maximumTripDistanceMiles.value.toStringAsFixed(1)} $distanceUnitLabel trip',
      if (rules.minimumHourlyRate.enabled)
        '£${rules.minimumHourlyRate.value.toStringAsFixed(2)}/hr min',
      if (rules.postcodeBlocklist.enabled && rules.postcodeBlocklist.blockedPrefixes.isNotEmpty)
        '${rules.postcodeBlocklist.blockedPrefixes.length} area'
            '${rules.postcodeBlocklist.blockedPrefixes.length == 1 ? '' : 's'} blocked',
      if (rules.counterOfferBandPercent.enabled)
        'Counter-offer at ${rules.counterOfferBandPercent.value.toStringAsFixed(0)}%',
    ];

    return SummaryCard(
      icon: Icons.fact_check_outlined,
      headline: active.isEmpty ? 'No filters active' : '${active.length} rule${active.length == 1 ? '' : 's'} active',
      emptyMessage: active.isEmpty
          ? 'Every job passes straight through unless you turn a rule on below.'
          : null,
      chips: active,
    );
  }
}

class _PlatformOverrideTile extends ConsumerWidget {
  const _PlatformOverrideTile({required this.platform});

  final PlatformType platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final override = settings.platformOverrides[platform];

    return ThresholdRuleTile(
      title: platform.displayName,
      subtitle: 'Overrides minimum £/mile for ${platform.displayName} only.',
      unitPrefix: '£',
      unitSuffix: '/mile',
      icon: platform == PlatformType.uber
          ? Icons.directions_car_filled_outlined
          : Icons.electric_car_outlined,
      rule: override?.minimumPoundsPerMile ??
          const ThresholdRule(enabled: false, value: 2.00),
      onChanged: (r) {
        final overrides =
            Map<PlatformType, RuleConfig>.from(settings.platformOverrides);
        // Turning the switch off must mean "no override — use the rules
        // above" (this section's own subtitle promises exactly that), not
        // "override present but disabled". Those are different in
        // driver_settings.dart's rulesFor(): an entry in this map replaces
        // the *entire* rule set for that platform, not just this one
        // field, so leaving a disabled override behind silently skipped
        // Uber's minimum £/mile check on a real device — jobs kept being
        // accepted below the driver's configured minimum with no warning
        // anywhere, since the Dashboard reads the global rule, not the
        // per-platform effective one. Removing the entry outright is what
        // actually restores "use the rules above".
        if (!r.enabled) {
          overrides.remove(platform);
        } else {
          final base = overrides[platform] ?? settings.rules;
          overrides[platform] = base.copyWith(minimumPoundsPerMile: r);
        }
        controller.update((s) => s.copyWith(platformOverrides: overrides));
      },
    );
  }
}
