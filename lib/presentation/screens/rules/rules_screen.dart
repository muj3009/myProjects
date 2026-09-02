import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/state/settings_controller.dart';
import '../../../domain/entities/rule_config.dart';
import '../../../domain/enums/distance_unit.dart';
import '../../../domain/enums/platform_type.dart';
import '../../widgets/hero_header.dart';
import '../../widgets/hero_pill.dart';
import '../../widgets/section_card.dart';
import '../../widgets/section_header.dart';
import 'widgets/high_value_job_tile.dart';
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            HeroHeader(
              child: _RulesHeroBody(rules: rules, distanceUnitLabel: distanceUnitLabel),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                children: [
          const SectionHeader('CORE RULE'),
          _FeaturedRuleCard(
            child: ThresholdRuleTile(
              title: 'Minimum £ per mile',
              subtitle: 'Core filter — always active. Rejects any job paying less than this rate.',
              unitPrefix: '£',
              unitSuffix: '/mi',
              icon: Icons.attach_money,
              rule: rules.minimumPoundsPerMile,
              emphasized: true,
              color: const Color(0xFF4C6EF5),
              forceEnabled: true,
              onChanged: (r) =>
                  updateRules((c) => c.copyWith(minimumPoundsPerMile: r)),
            ),
          ),
          const SizedBox(height: 6),
          const SectionHeader('ADDITIONAL FILTERS'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Column(
              children: [
                ThresholdRuleTile(
                  title: 'Maximum pickup distance',
                  subtitle: 'Reject jobs where the drive to the passenger is too far. Long pickups waste time and fuel before you even start earning.',
                  unitSuffix: ' $distanceUnitLabel',
                  icon: Icons.social_distance,
                  rule: rules.maximumPickupDistanceMiles,
                  color: const Color(0xFFA855F7),
                  onChanged: (r) => updateRules(
                      (c) => c.copyWith(maximumPickupDistanceMiles: r)),
                ),
                const _RowDivider(),
                ThresholdRuleTile(
                  title: 'Minimum fare',
                  subtitle: 'Reject jobs below this flat fare amount, regardless of distance or £/mile. Useful for filtering out very short trips that pay poorly.',
                  unitPrefix: '£',
                  icon: Icons.payments_outlined,
                  rule: rules.minimumFare,
                  color: const Color(0xFF2FA968),
                  onChanged: (r) => updateRules((c) => c.copyWith(minimumFare: r)),
                ),
                const _RowDivider(),
                ThresholdRuleTile(
                  title: 'Maximum trip distance',
                  subtitle: 'Reject unusually long trips. Long trips can tie you up far from home with no guarantee of a return fare.',
                  unitSuffix: ' $distanceUnitLabel',
                  icon: Icons.route_outlined,
                  rule: rules.maximumTripDistanceMiles,
                  color: const Color(0xFF14B8A6),
                  onChanged: (r) =>
                      updateRules((c) => c.copyWith(maximumTripDistanceMiles: r)),
                ),
                const _RowDivider(),
                ThresholdRuleTile(
                  title: 'Minimum hourly rate',
                  subtitle: 'Only applies when the app provides a duration estimate. Reject jobs where estimated earnings per hour fall below this rate.',
                  unitPrefix: '£',
                  unitSuffix: '/hr',
                  icon: Icons.schedule_outlined,
                  rule: rules.minimumHourlyRate,
                  color: const Color(0xFFEC4899),
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
                  title: 'Counter-offer near-miss (Bolt only)',
                  subtitle: 'Jobs within this percentage of your minimum £/mile will get a counter-offer instead of being rejected. E.g. 85% of £2.00 = £1.70/mi and above gets a counter.',
                  unitSuffix: '%',
                  icon: Icons.swap_horiz,
                  rule: rules.counterOfferBandPercent,
                  color: const Color(0xFFD4A72C),
                  onChanged: (r) =>
                      updateRules((c) => c.copyWith(counterOfferBandPercent: r)),
                ),
                const _RowDivider(),
                ThresholdRuleTile(
                  title: 'Auto counter-offer low fares (Bolt only)',
                  subtitle: 'Any Bolt job below this fare amount automatically gets your maximum counter-offer instead of being rejected. Useful for very cheap jobs worth trying for more.',
                  unitPrefix: '£',
                  icon: Icons.local_offer_outlined,
                  rule: rules.lowFareCounterOfferThreshold,
                  color: const Color(0xFF84CC16),
                  onChanged: (r) =>
                      updateRules((c) => c.copyWith(lowFareCounterOfferThreshold: r)),
                ),
                const _RowDivider(),
                HighValueJobTile(
                  config: rules.highValueJob,
                  onChanged: (v) => updateRules((c) => c.copyWith(highValueJob: v)),
                ),
                const _RowDivider(),
                ThresholdRuleTile(
                  title: 'Relax £/mile when quiet',
                  subtitle: 'When fewer than 8 jobs appear in 5 minutes (quiet period), temporarily lower your minimum £/mile to this value. Never raises above your normal minimum.',
                  unitPrefix: '£',
                  unitSuffix: '/mi',
                  icon: Icons.nightlight_outlined,
                  rule: rules.quietTimeMinimumPoundsPerMile,
                  color: const Color(0xFFB45309),
                  onChanged: (r) =>
                      updateRules((c) => c.copyWith(quietTimeMinimumPoundsPerMile: r)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const SectionHeader('£/MI CALCULATION'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Column(
              children: [
                RadioListTile<DistanceCalculationMode>(
                  title: const Text('Trip distance'),
                  subtitle: const Text('fare ÷ trip (default)'),
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
                  title: const Text('Total driving'),
                  subtitle: const Text('fare ÷ (pickup + trip)'),
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
          const SizedBox(height: 6),
          const SectionHeader('PLATFORM OVERRIDES'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 1),
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
            ),
          ],
        ),
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
        indent: 58,
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: child,
    );
  }
}

/// The hero's content: screen title plus "did I actually set this up
/// right" at a glance — previously verifying the driver's own rule setup
/// meant scrolling and reading every card. Empty when no filters are active
/// so the fallback behavior (every job passes through) is stated plainly
/// rather than just... absent.
class _RulesHeroBody extends StatelessWidget {
  const _RulesHeroBody({required this.rules, required this.distanceUnitLabel});

  final RuleConfig rules;
  final String distanceUnitLabel;

  @override
  Widget build(BuildContext context) {
    final active = <String>[
      if (rules.minimumPoundsPerMile.enabled)
        'Min £/mi: £${rules.minimumPoundsPerMile.value.toStringAsFixed(2)}',
      if (rules.maximumPickupDistanceMiles.enabled)
        'Max pickup: ${rules.maximumPickupDistanceMiles.value.toStringAsFixed(1)} $distanceUnitLabel',
      if (rules.minimumFare.enabled)
        'Min fare: £${rules.minimumFare.value.toStringAsFixed(2)}',
      if (rules.maximumTripDistanceMiles.enabled)
        'Max trip: ${rules.maximumTripDistanceMiles.value.toStringAsFixed(1)} $distanceUnitLabel',
      if (rules.minimumHourlyRate.enabled)
        'Min hourly: £${rules.minimumHourlyRate.value.toStringAsFixed(2)}/hr',
      if (rules.postcodeBlocklist.enabled && rules.postcodeBlocklist.blockedPrefixes.isNotEmpty)
        '${rules.postcodeBlocklist.blockedPrefixes.length} area'
            '${rules.postcodeBlocklist.blockedPrefixes.length == 1 ? '' : 's'} blocked',
      if (rules.counterOfferBandPercent.enabled)
        'Counter near-miss: ${rules.counterOfferBandPercent.value.toStringAsFixed(0)}%',
      if (rules.lowFareCounterOfferThreshold.enabled)
        'Auto counter under £${rules.lowFareCounterOfferThreshold.value.toStringAsFixed(2)}',
      if (rules.highValueJob.enabled)
        'High-value: £${rules.highValueJob.fareFloor.toStringAsFixed(0)}+ @ £${rules.highValueJob.acceptRateFloor.toStringAsFixed(2)}/mi',
      if (rules.quietTimeMinimumPoundsPerMile.enabled)
        'Quiet min: £${rules.quietTimeMinimumPoundsPerMile.value.toStringAsFixed(2)}/mi',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Rules',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.3)),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.fact_check_outlined, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Text(
              active.isEmpty ? 'No filters active' : '${active.length} rule${active.length == 1 ? '' : 's'} active',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ],
        ),
        if (active.isEmpty) ...[
          const SizedBox(height: 3),
          const Text(
            'Every job passes through unless you turn a rule on below.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ] else ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [for (final label in active) HeroPill(label: label)],
          ),
        ],
      ],
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
      // Uber's own near-black brand tone doesn't survive the muted/low-alpha
      // "off" treatment — a very dark color at 14% alpha is just gray, the
      // same as no color at all, so it looked identical to an uncolored
      // row. Cyan instead, kept distinct from the other rule-row colors so
      // all seven rows on this screen read as genuinely different.
      color: platform == PlatformType.uber
          ? const Color(0xFF06B6D4)
          : const Color(0xFFF2994A),
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
