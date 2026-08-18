import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/entities/rule_config.dart';
import '../../../widgets/section_card.dart';
import '../../../widgets/tinted_icon_circle.dart';

/// One rule row in the Rule Builder (spec section 32): an on/off switch plus
/// a numeric value, validated against sensible bounds. Reused for every
/// [ThresholdRule] in [RuleConfig] so adding a new rule to the domain layer
/// only requires one more of these in the screen, not a bespoke widget.
class ThresholdRuleTile extends StatefulWidget {
  const ThresholdRuleTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rule,
    required this.onChanged,
    this.unitPrefix = '',
    this.unitSuffix = '',
    this.icon = Icons.tune,
  });

  final String title;
  final String subtitle;
  final ThresholdRule rule;
  final ValueChanged<ThresholdRule> onChanged;
  final String unitPrefix;
  final String unitSuffix;
  final IconData icon;

  @override
  State<ThresholdRuleTile> createState() => _ThresholdRuleTileState();
}

class _ThresholdRuleTileState extends State<ThresholdRuleTile> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.rule.value.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(covariant ThresholdRuleTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rule.value != widget.rule.value &&
        !_controller.selection.isValid) {
      _controller.text = widget.rule.value.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const double _sensibleMaximum = 1000.0;

  void _commit(String raw) {
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      setState(() => _error = 'Enter a value greater than 0');
      return;
    }
    if (parsed > _sensibleMaximum) {
      setState(() => _error = 'Value is too large');
      return;
    }
    setState(() => _error = null);
    widget.onChanged(widget.rule.copyWith(value: parsed));
  }

  @override
  Widget build(BuildContext context) {
    final rule = widget.rule;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RuleIcon(icon: widget.icon, active: rule.enabled),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(
                value: rule.enabled,
                onChanged: (enabled) =>
                    widget.onChanged(rule.copyWith(enabled: enabled)),
              ),
            ],
          ),
          if (rule.enabled) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              enabled: rule.enabled,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
              ],
              decoration: InputDecoration(
                prefixText: widget.unitPrefix,
                suffixText: widget.unitSuffix,
                errorText: _error,
              ),
              onChanged: _commit,
            ),
          ],
        ],
      ),
    );
  }
}

/// Small tinted-circle icon used to give each rule row a distinct,
/// scannable identity at a glance instead of an undifferentiated list of
/// text rows — dims to a neutral gray when the rule is off so the eye is
/// drawn to whichever rules are actually active. Public (not `_`-prefixed)
/// so [PostcodeBlocklistTile] can reuse the exact same treatment.
class RuleIcon extends StatelessWidget {
  const RuleIcon({super.key, required this.icon, required this.active});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return TintedIconCircle(icon: icon, color: color);
  }
}
