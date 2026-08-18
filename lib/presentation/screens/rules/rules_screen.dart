import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/state/settings_controller.dart';
import '../../../domain/entities/rule_config.dart';
import '../../../domain/enums/distance_unit.dart';
import '../../../domain/enums/platform_type.dart';
import '../../widgets/section_card.dart';
import 'widgets/postcode_blocklist_tile.dart';
import 'widgets/threshold_rule_tile.dart';

/// Rule Builder (spec section 6/11/32) — every rule is independently
/// enable-able, and the list is driven by data rather than one hard-coded
/// screen per rule, so a new rule only needs a new [ThresholdRuleTile] entry.
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
        settings.distanceUnit == DistanceUnit.miles ? 'miles' : 'km';

    return Scaffold(
      appBar: AppBar(title: const Text('Rules')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ThresholdRuleTile(
            title: 'Minimum £/mile',
            subtitle: 'The core rule — reject anything below this rate.',
            unitPrefix: '£',
            unitSuffix: '/mile',
            icon: Icons.attach_money,
            rule: rules.minimumPoundsPerMile,
            onChanged: (r) =>
                updateRules((c) => c.copyWith(minimumPoundsPerMile: r)),
          ),
          const SizedBox(height: 12),
          ThresholdRuleTile(
            title: 'Maximum pickup distance',
            subtitle:
                'Reject jobs that need a long drive just to reach the passenger.',
            unitSuffix: ' $distanceUnitLabel',
            icon: Icons.social_distance,
            rule: rules.maximumPickupDistanceMiles,
            onChanged: (r) =>
                updateRules((c) => c.copyWith(maximumPickupDistanceMiles: r)),
          ),
          const SizedBox(height: 12),
          ThresholdRuleTile(
            title: 'Minimum fare',
            subtitle: 'Reject jobs below a flat fare, regardless of £/mile.',
            unitPrefix: '£',
            icon: Icons.payments_outlined,
            rule: rules.minimumFare,
            onChanged: (r) => updateRules((c) => c.copyWith(minimumFare: r)),
          ),
          const SizedBox(height: 12),
          ThresholdRuleTile(
            title: 'Maximum trip distance',
            subtitle: 'Reject unusually long trips.',
            unitSuffix: ' $distanceUnitLabel',
            icon: Icons.route_outlined,
            rule: rules.maximumTripDistanceMiles,
            onChanged: (r) =>
                updateRules((c) => c.copyWith(maximumTripDistanceMiles: r)),
          ),
          const SizedBox(height: 12),
          ThresholdRuleTile(
            title: 'Minimum estimated hourly rate',
            subtitle:
                'Only applied when a reliable duration estimate is available.',
            unitPrefix: '£',
            unitSuffix: '/hour',
            icon: Icons.schedule_outlined,
            rule: rules.minimumHourlyRate,
            onChanged: (r) =>
                updateRules((c) => c.copyWith(minimumHourlyRate: r)),
          ),
          const SizedBox(height: 12),
          PostcodeBlocklistTile(
            config: rules.postcodeBlocklist,
            onChanged: (c) =>
                updateRules((r) => r.copyWith(postcodeBlocklist: c)),
          ),
          const SizedBox(height: 12),
          ThresholdRuleTile(
            title: 'Counter-offer near-miss jobs (Bolt only)',
            subtitle:
                'A Bolt job at this % or more of your minimum £/mile gets a '
                'counter-offer (via "Change price", highest suggested amount) '
                'instead of a straight reject.',
            unitSuffix: '%',
            icon: Icons.swap_horiz,
            rule: rules.counterOfferBandPercent,
            onChanged: (r) =>
                updateRules((c) => c.copyWith(counterOfferBandPercent: r)),
          ),
          const SizedBox(height: 28),
          Text('£/mile calculation',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
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
          const SizedBox(height: 28),
          Text('Platform-specific overrides',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Set a different minimum £/mile per platform. Leave off to use the rules above.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          for (final platform in [PlatformType.uber, PlatformType.bolt])
            _PlatformOverrideTile(platform: platform),
        ],
      ),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ThresholdRuleTile(
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
      ),
    );
  }
}
