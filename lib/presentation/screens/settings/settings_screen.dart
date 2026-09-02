import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/state/job_history_controller.dart';
import '../../../application/state/navigation_controller.dart';
import '../../../application/state/settings_controller.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/enums/distance_unit.dart';
import '../../../domain/enums/platform_type.dart';
import '../../widgets/hero_header.dart';
import '../../widgets/section_card.dart';
import '../../widgets/tinted_icon_circle.dart';
import '../permissions/permissions_screen.dart';
import '../simulation/simulation_screen.dart';

/// Driver Settings (spec section 5) plus the app-wide preferences (name,
/// platform selection, distance unit) and links to the guided permissions
/// setup, Simulation Mode.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _quickPresets = [1.50, 1.75, 2.00, 2.25, 2.50, 3.00];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final minRule = settings.rules.minimumPoundsPerMile;

    Color _colorForPlatform(PlatformSelection p) => switch (p) {
      PlatformSelection.uber => const Color(0xFFD4A72C),
      PlatformSelection.bolt => const Color(0xFFF2994A),
      PlatformSelection.both => const Color(0xFF4C6EF5),
    };

    IconData _iconForPlatform(PlatformSelection p) => switch (p) {
      PlatformSelection.uber => Icons.directions_car_filled_outlined,
      PlatformSelection.bolt => Icons.electric_car_outlined,
      PlatformSelection.both => Icons.apps,
    };

    String _labelForPlatform(PlatformSelection p) => switch (p) {
      PlatformSelection.uber => 'Uber',
      PlatformSelection.bolt => 'Bolt',
      PlatformSelection.both => 'Both',
    };

    String _labelForDistance(DistanceUnit d) => switch (d) {
      DistanceUnit.miles => 'Miles',
      DistanceUnit.kilometres => 'Kilometres',
    };

    String _labelForTheme(ThemeMode m) => switch (m) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            HeroHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Settings',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: -0.3)),
                  const SizedBox(height: 2),
                  Text(
                    '£${minRule.value.toStringAsFixed(2)}/mile · '
                    '${_labelForPlatform(settings.platformSelection)} · '
                    '${_labelForDistance(settings.distanceUnit)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        children: [
          Text('Minimum £/mi', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          SectionCard(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '£${minRule.value.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  children: [
                    for (final preset in _quickPresets)
                      ChoiceChip(
                        label: Text('£${preset.toStringAsFixed(2)}'),
                        selected: (minRule.value - preset).abs() < 0.001,
                        onSelected: (_) => controller.update(
                          (s) => s.copyWith(
                            rules: s.rules.copyWith(
                              minimumPoundsPerMile: minRule.copyWith(
                                  value: preset, enabled: true),
                            ),
                          ),
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  ),
                  onPressed: () => _showCustomValueDialog(
                      context, controller, minRule.value),
                  child: const Text('Custom'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('Platform', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final platform in [
                PlatformSelection.uber,
                PlatformSelection.bolt,
                PlatformSelection.both
              ]) ...[
                ChoiceChip(
                  avatar: TintedIconCircle(
                    icon: _iconForPlatform(platform),
                    color: _colorForPlatform(platform),
                    diameter: 18,
                    iconSize: 10,
                  ),
                  showCheckmark: true,
                  checkmarkColor: Colors.white,
                  selectedColor: _colorForPlatform(platform),
                  label: Text(_labelForPlatform(platform)),
                  selected: settings.platformSelection == platform,
                  onSelected: (_) => controller.update(
                    (s) => s.copyWith(platformSelection: platform),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text('Distance', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final unit in [
                DistanceUnit.miles,
                DistanceUnit.kilometres,
              ]) ...[
                ChoiceChip(
                  label: Text(_labelForDistance(unit)),
                  selected: settings.distanceUnit == unit,
                  selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                  onSelected: (_) => controller.update(
                    (s) => s.copyWith(distanceUnit: unit),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text('Theme', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final mode in [
                ThemeMode.system,
                ThemeMode.light,
                ThemeMode.dark
              ]) ...[
                ChoiceChip(
                  label: Text(_labelForTheme(mode)),
                  selected: settings.themeMode == mode,
                  selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                  onSelected: (_) => controller.update(
                    (s) => s.copyWith(themeMode: mode),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Column(
              children: [
                _SettingsLinkTile(
                  icon: Icons.rule_folder_outlined,
                  title: 'Advanced rules',
                  subtitle: 'Pickup, min fare, hourly rate, etc.',
                  onTap: () =>
                      ref.read(rootNavigationIndexProvider.notifier).state = 3,
                ),
                const Divider(height: 1, indent: 44),
                _SettingsLinkTile(
                  icon: Icons.security_outlined,
                  title: 'Permissions & setup',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PermissionsScreen())),
                ),
                const Divider(height: 1, indent: 44),
                _SettingsLinkTile(
                  icon: Icons.science_outlined,
                  title: 'Simulation / test mode',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SimulationScreen())),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
            onPressed: () => _confirmClearHistory(context, ref),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Clear job history'),
          ),
        ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCustomValueDialog(
    BuildContext context,
    SettingsController controller,
    double current,
  ) async {
    final textController =
        TextEditingController(text: current.toStringAsFixed(2));
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom minimum £/mile'),
        content: TextField(
          controller: textController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '£'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(textController.text);
              Navigator.pop(context, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null ||
        result < AppConstants.minAllowedPoundsPerMile ||
        result > AppConstants.maxAllowedPoundsPerMile) {
      return;
    }

    await controller.update(
      (s) => s.copyWith(
        rules: s.rules.copyWith(
          minimumPoundsPerMile: s.rules.minimumPoundsPerMile
              .copyWith(value: result, enabled: true),
        ),
      ),
    );
  }

  Future<void> _confirmClearHistory(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear job history?'),
        content: const Text(
            'This permanently deletes all locally stored job history.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(jobHistoryControllerProvider.notifier).clearHistory();
    }
  }
}

/// A ListTile with a tinted-circle leading icon — matches [RuleIcon]'s
/// treatment on the Rules screen so both settings-style lists in the app
/// read as one consistent visual language rather than two different ones.
class _SettingsLinkTile extends StatelessWidget {
  const _SettingsLinkTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: TintedIconCircle(icon: icon, color: primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
