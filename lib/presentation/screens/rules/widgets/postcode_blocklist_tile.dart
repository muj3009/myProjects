import 'package:flutter/material.dart';

import '../../../../domain/entities/rule_config.dart';
import '../../../widgets/section_card.dart';
import 'threshold_rule_tile.dart' show RuleIcon;

/// Rule Builder row for [PostcodeBlocklistConfig] — same on/off switch
/// pattern as [ThresholdRuleTile], but the value is a list of postcode
/// prefixes (e.g. "LE4", "LE5") instead of a single number, entered one at a
/// time and shown as removable chips.
class PostcodeBlocklistTile extends StatefulWidget {
  const PostcodeBlocklistTile({
    super.key,
    required this.config,
    required this.onChanged,
  });

  final PostcodeBlocklistConfig config;
  final ValueChanged<PostcodeBlocklistConfig> onChanged;

  @override
  State<PostcodeBlocklistTile> createState() => _PostcodeBlocklistTileState();
}

class _PostcodeBlocklistTileState extends State<PostcodeBlocklistTile> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addPrefix(String raw) {
    final prefix = raw.trim().toUpperCase();
    if (prefix.isEmpty) return;
    // Loose validation only — a real UK outward code is 2-4 characters
    // (1-2 letters, 1-2 digits, optional trailing letter — e.g. "LE4",
    // "SW1A", "EC1A"), but this never needs to be exact since it's just
    // compared as a case-insensitive string prefix at decision time, not
    // parsed into a structured postcode. Mirrors the shape
    // ParsedTextUtils._postcodeToken's outward group actually extracts, so
    // a driver can never add a prefix real destination text could never
    // match in the first place.
    if (!RegExp(r'^[A-Z]{1,2}[0-9]{1,2}[A-Z]?$').hasMatch(prefix)) {
      setState(() => _error = 'Enter an outward code like "LE4" or "SW1A"');
      return;
    }
    if (widget.config.blockedPrefixes.contains(prefix)) {
      setState(() => _error = 'Already on the list');
      return;
    }
    setState(() => _error = null);
    _controller.clear();
    widget.onChanged(
      widget.config.copyWith(
          blockedPrefixes: [...widget.config.blockedPrefixes, prefix]),
    );
  }

  void _removePrefix(String prefix) {
    widget.onChanged(
      widget.config.copyWith(
        blockedPrefixes:
            widget.config.blockedPrefixes.where((p) => p != prefix).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RuleIcon(icon: Icons.block, active: config.enabled),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Destination postcode blocklist',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      'Always reject jobs going to these areas, regardless of £/mile or any other rule.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(
                value: config.enabled,
                onChanged: (enabled) =>
                    widget.onChanged(config.copyWith(enabled: enabled)),
              ),
            ],
          ),
          if (config.enabled) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Add postcode area (e.g. LE4)',
                errorText: _error,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _addPrefix(_controller.text),
                ),
              ),
              onSubmitted: _addPrefix,
            ),
            if (config.blockedPrefixes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final prefix in config.blockedPrefixes)
                    Chip(
                      label: Text(prefix),
                      onDeleted: () => _removePrefix(prefix),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
