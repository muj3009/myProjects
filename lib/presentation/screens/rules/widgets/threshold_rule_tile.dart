import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/entities/rule_config.dart';
import '../../../widgets/tinted_icon_circle.dart';

/// One rule row in the Rule Builder (spec section 32): an on/off switch plus
/// a numeric value, validated against sensible bounds. Reused for every
/// [ThresholdRule] in [RuleConfig] so adding a new rule to the domain layer
/// only requires one more of these in the screen, not a bespoke widget.
///
/// Deliberately card-agnostic — no shadow/border of its own — so
/// [RulesScreen] can group several rows inside one shared [SectionCard]
/// (divided list, like a native settings screen) instead of every rule
/// costing its own floating card. A disabled rule collapses to a single
/// compact line; only an enabled rule spends vertical space on its input.
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
    this.emphasized = false,
    this.color,
  });

  final String title;
  final String subtitle;
  final ThresholdRule rule;
  final ValueChanged<ThresholdRule> onChanged;
  final String unitPrefix;
  final String unitSuffix;
  final IconData icon;

  /// Icon color when the rule is active — null falls back to the theme's
  /// primary. Giving each rule its own color (rather than every active rule
  /// sharing the same blue) is what actually makes a list of seven rows
  /// scannable at a glance instead of visually uniform.
  final Color? color;

  /// The one rule the driver actually cares about most (minimum £/mile) —
  /// bigger icon/title and the caller wraps it in a tinted "featured" card,
  /// so it reads as the anchor of the page rather than one row among seven.
  final bool emphasized;

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
    // Flush a pending edit rather than silently drop it — a driver who types
    // a value then immediately switches screens shouldn't lose that last
    // keystroke just because the debounce timer hadn't fired yet.
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      _commitNow(_controller.text);
    }
    _controller.dispose();
    super.dispose();
  }

  static const double _sensibleMaximum = 1000.0;
  static const _debounceDelay = Duration(milliseconds: 400);

  Timer? _debounce;

  // Every call used to flow straight through to widget.onChanged on every
  // keystroke, which the caller (RulesScreen -> SettingsController.update)
  // turns into a full-screen Riverpod rebuild *and* a JSON-encode + SQLite
  // write of the entire settings object — real, visible typing lag once the
  // rule set grew past a handful of fields. Validation still runs
  // immediately (cheap, local setState only); only the expensive commit is
  // debounced until typing actually pauses.
  void _commit(String raw) {
    if (!_validate(raw)) return;
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => _commitNow(raw));
  }

  bool _validate(String raw) {
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      setState(() => _error = 'Enter a value greater than 0');
      return false;
    }
    if (parsed > _sensibleMaximum) {
      setState(() => _error = 'Value is too large');
      return false;
    }
    setState(() => _error = null);
    return true;
  }

  void _commitNow(String raw) {
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0 || parsed > _sensibleMaximum) return;
    widget.onChanged(widget.rule.copyWith(value: parsed));
  }

  @override
  Widget build(BuildContext context) {
    final rule = widget.rule;
    final theme = Theme.of(context);
    final valueText =
        '${widget.unitPrefix}${rule.value.toStringAsFixed(2)}${widget.unitSuffix}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              RuleIcon(
                icon: widget.icon,
                active: rule.enabled,
                large: widget.emphasized,
                color: widget.color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: (widget.emphasized
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.titleMedium)
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    ScrollableSubtitle(widget.subtitle),
                  ],
                ),
              ),
              // Skipped on the emphasized (featured) tile — its input field
              // is always visible right below, so a badge repeating the same
              // number would just steal the width the title needs to avoid
              // wrapping mid-word.
              if (rule.enabled && !widget.emphasized) ...[
                const SizedBox(width: 8),
                _ValueBadge(text: valueText),
              ],
              const SizedBox(width: 4),
              Switch(
                value: rule.enabled,
                onChanged: (enabled) =>
                    widget.onChanged(rule.copyWith(enabled: enabled)),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: rule.enabled
                ? Padding(
                    padding: const EdgeInsets.only(top: 10, left: 52),
                    child: TextField(
                      controller: _controller,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
                      ],
                      decoration: InputDecoration(
                        isDense: true,
                        prefixText: widget.unitPrefix,
                        suffixText: widget.unitSuffix,
                        errorText: _error,
                      ),
                      onChanged: _commit,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// A single-line description that scrolls horizontally instead of being
/// truncated with an ellipsis — a compact collapsed row only has room for
/// one line, but cutting the description off mid-word made it unreadable
/// (e.g. "Long drives just to reach the p…"). A driver who wants the full
/// text can swipe it into view instead of losing the second half entirely.
/// Public so [PostcodeBlocklistTile] reuses the exact same treatment.
class ScrollableSubtitle extends StatelessWidget {
  const ScrollableSubtitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// A small pill showing the rule's current live value next to the switch —
/// lets a driver confirm "is this set to what I think it's set to" without
/// expanding every row, the way the always-visible input field used to
/// require.
class _ValueBadge extends StatelessWidget {
  const _ValueBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(color: primary, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

/// Icon badge for a rule row. Active rules get the app-wide gradient
/// [TintedIconCircle] treatment; inactive ones collapse to a flat, low-alpha
/// gray disc with no gradient or shadow — genuinely receding rather than
/// rendering as a heavy black-gradient orb, so the eye is drawn straight to
/// whichever rules are actually on. Public (not `_`-prefixed) so
/// [PostcodeBlocklistTile] can reuse the exact same treatment.
class RuleIcon extends StatelessWidget {
  const RuleIcon({
    super.key,
    required this.icon,
    required this.active,
    this.large = false,
    this.color,
  });

  final IconData icon;
  final bool active;
  final bool large;

  /// This rule's own identity color — null falls back to the theme's
  /// primary blue. Most rules are off by default, so if color only showed
  /// up once enabled, a driver opening this screen fresh would see a wall
  /// of identical gray icons and never notice the palette at all; a muted
  /// tint of the same color when off keeps every row visually distinct at
  /// rest, while full saturation still marks which rules are actually on.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final diameter = large ? 46.0 : 38.0;
    if (!active) {
      final muted = color ?? scheme.onSurfaceVariant;
      return Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: muted.withValues(alpha: 0.14),
        ),
        child: Icon(icon, size: diameter * 0.5, color: muted.withValues(alpha: 0.75)),
      );
    }
    return TintedIconCircle(
      icon: icon,
      color: color ?? scheme.primary,
      diameter: diameter,
      iconSize: diameter * 0.5,
    );
  }
}
