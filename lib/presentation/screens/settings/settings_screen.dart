import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/state/job_history_controller.dart';
import '../../../application/state/settings_controller.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/enums/distance_unit.dart';
import '../../../domain/enums/platform_type.dart';
import '../../widgets/section_card.dart';
import '../debug/debug_screen.dart';
import '../permissions/permissions_screen.dart';
import '../simulation/simulation_screen.dart';

/// Driver Settings (spec section 5) plus the app-wide preferences (name,
/// platform selection, distance unit) and links to the guided permissions
/// setup, Simulation Mode, and the debug screen (debug builds only).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _quickPresets = [1.50, 1.75, 2.00, 2.25, 2.50, 3.00];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final minRule = settings.rules.minimumPoundsPerMile;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Minimum £ per mile',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '£${minRule.value.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
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
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _showCustomValueDialog(
                      context, controller, minRule.value),
                  child: const Text('Enter a custom amount'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text('Platform', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final selection in PlatformSelection.values)
                  RadioListTile<PlatformSelection>(
                    title: Text(switch (selection) {
                      PlatformSelection.uber => 'Uber only',
                      PlatformSelection.bolt => 'Bolt only',
                      PlatformSelection.both => 'Both Uber and Bolt',
                    }),
                    value: selection,
                    groupValue: settings.platformSelection,
                    selected: settings.platformSelection == selection,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.07),
                    activeColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    onChanged: (v) => controller
                        .update((s) => s.copyWith(platformSelection: v)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text('Distance unit', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: RadioListTile<DistanceUnit>(
                    title: const Text('Miles'),
                    value: DistanceUnit.miles,
                    groupValue: settings.distanceUnit,
                    selected: settings.distanceUnit == DistanceUnit.miles,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.07),
                    activeColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    onChanged: (v) =>
                        controller.update((s) => s.copyWith(distanceUnit: v)),
                  ),
                ),
                Expanded(
                  child: RadioListTile<DistanceUnit>(
                    title: const Text('Kilometres'),
                    value: DistanceUnit.kilometres,
                    groupValue: settings.distanceUnit,
                    selected: settings.distanceUnit == DistanceUnit.kilometres,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.07),
                    activeColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    onChanged: (v) =>
                        controller.update((s) => s.copyWith(distanceUnit: v)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text('App name', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SectionCard(
            child: TextFormField(
              initialValue: settings.appName,
              onFieldSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isNotEmpty) {
                  controller.update((s) => s.copyWith(appName: trimmed));
                }
              },
            ),
          ),
          const SizedBox(height: 28),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                _SettingsLinkTile(
                  icon: Icons.rule_folder_outlined,
                  title: 'Advanced rules',
                  subtitle:
                      'Pickup distance, minimum fare, hourly rate, and more',
                  onTap:
                      () {}, // Rules tab is reachable from bottom navigation.
                ),
                const Divider(height: 1, indent: 68),
                _SettingsLinkTile(
                  icon: Icons.security_outlined,
                  title: 'Permissions & setup',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const PermissionsScreen()),
                  ),
                ),
                const Divider(height: 1, indent: 68),
                _SettingsLinkTile(
                  icon: Icons.science_outlined,
                  title: 'Simulation / test mode',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SimulationScreen()),
                  ),
                ),
                if (kDebugMode) ...[
                  const Divider(height: 1, indent: 68),
                  _SettingsLinkTile(
                    icon: Icons.bug_report_outlined,
                    title: 'Developer debug screen',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DebugScreen()),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            onPressed: () => _confirmClearHistory(context, ref),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Clear job history'),
          ),
        ],
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
