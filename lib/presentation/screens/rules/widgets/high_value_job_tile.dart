import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/entities/rule_config.dart';
import 'threshold_rule_tile.dart' show RuleIcon, ScrollableSubtitle;

/// Rule Builder row for [HighValueJobOverride] — same compact-when-off,
/// expand-when-on pattern as [ThresholdRuleTile], but with two independent
/// values (a fare floor and a £/mile floor) instead of one, so it doesn't
/// fit that widget's single-value shape.
class HighValueJobTile extends StatefulWidget {
  const HighValueJobTile({
    super.key,
    required this.config,
    required this.onChanged,
  });

  final HighValueJobOverride config;
  final ValueChanged<HighValueJobOverride> onChanged;

  @override
  State<HighValueJobTile> createState() => _HighValueJobTileState();
}

class _HighValueJobTileState extends State<HighValueJobTile> {
  late final TextEditingController _fareController;
  late final TextEditingController _rateController;
  late final TextEditingController _counterOfferRateController;

  static const _color = Color(0xFF4338CA);

  @override
  void initState() {
    super.initState();
    _fareController = TextEditingController(text: widget.config.fareFloor.toStringAsFixed(2));
    _rateController = TextEditingController(text: widget.config.acceptRateFloor.toStringAsFixed(2));
    _counterOfferRateController =
        TextEditingController(text: widget.config.counterOfferRateFloor.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(covariant HighValueJobTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.fareFloor != widget.config.fareFloor &&
        !_fareController.selection.isValid) {
      _fareController.text = widget.config.fareFloor.toStringAsFixed(2);
    }
    if (oldWidget.config.acceptRateFloor != widget.config.acceptRateFloor &&
        !_rateController.selection.isValid) {
      _rateController.text = widget.config.acceptRateFloor.toStringAsFixed(2);
    }
    if (oldWidget.config.counterOfferRateFloor != widget.config.counterOfferRateFloor &&
        !_counterOfferRateController.selection.isValid) {
      _counterOfferRateController.text = widget.config.counterOfferRateFloor.toStringAsFixed(2);
    }
  }

  static const _debounceDelay = Duration(milliseconds: 400);
  Timer? _fareDebounce;
  Timer? _rateDebounce;
  Timer? _counterOfferRateDebounce;

  @override
  void dispose() {
    // Flush any pending edit rather than silently drop it — see the
    // matching comment in ThresholdRuleTile.dispose.
    if (_fareDebounce?.isActive ?? false) {
      _fareDebounce!.cancel();
      _commitFareNow(_fareController.text);
    }
    if (_rateDebounce?.isActive ?? false) {
      _rateDebounce!.cancel();
      _commitRateNow(_rateController.text);
    }
    if (_counterOfferRateDebounce?.isActive ?? false) {
      _counterOfferRateDebounce!.cancel();
      _commitCounterOfferRateNow(_counterOfferRateController.text);
    }
    _fareController.dispose();
    _rateController.dispose();
    _counterOfferRateController.dispose();
    super.dispose();
  }

  // Debounced for the same reason as ThresholdRuleTile._commit — every
  // keystroke used to flow straight through to a full settings rebuild plus
  // a SQLite write of the entire settings object.
  void _commitFare(String raw) {
    _fareDebounce?.cancel();
    _fareDebounce = Timer(_debounceDelay, () => _commitFareNow(raw));
  }

  void _commitRate(String raw) {
    _rateDebounce?.cancel();
    _rateDebounce = Timer(_debounceDelay, () => _commitRateNow(raw));
  }

  void _commitCounterOfferRate(String raw) {
    _counterOfferRateDebounce?.cancel();
    _counterOfferRateDebounce = Timer(_debounceDelay, () => _commitCounterOfferRateNow(raw));
  }

  void _commitFareNow(String raw) {
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) return;
    widget.onChanged(widget.config.copyWith(fareFloor: parsed));
  }

  void _commitRateNow(String raw) {
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) return;
    widget.onChanged(widget.config.copyWith(acceptRateFloor: parsed));
  }

  void _commitCounterOfferRateNow(String raw) {
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) return;
    widget.onChanged(widget.config.copyWith(counterOfferRateFloor: parsed));
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              RuleIcon(icon: Icons.workspace_premium_outlined, active: config.enabled, color: _color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'High-value job override',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    const ScrollableSubtitle(
                      'Accept immediately above both floors, counter-offer in the band below — ignores your '
                      'other rules (except the blocklist).',
                    ),
                  ],
                ),
              ),
              if (config.enabled) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '£${config.fareFloor.toStringAsFixed(0)}+ · £${config.acceptRateFloor.toStringAsFixed(2)}/mi '
                    '· ctr £${config.counterOfferRateFloor.toStringAsFixed(2)}+',
                    style: const TextStyle(color: _color, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Switch(
                value: config.enabled,
                onChanged: (enabled) => widget.onChanged(config.copyWith(enabled: enabled)),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: config.enabled
                ? Padding(
                    padding: const EdgeInsets.only(top: 10, left: 52),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _fareController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
                                ],
                                decoration: const InputDecoration(
                                  isDense: true,
                                  prefixText: '£',
                                  labelText: 'Fare ≥',
                                ),
                                onChanged: _commitFare,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _rateController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
                                ],
                                decoration: const InputDecoration(
                                  isDense: true,
                                  prefixText: '£',
                                  suffixText: '/mi',
                                  labelText: 'Accept ≥',
                                ),
                                onChanged: _commitRate,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _counterOfferRateController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
                                ],
                                decoration: const InputDecoration(
                                  isDense: true,
                                  prefixText: '£',
                                  suffixText: '/mi',
                                  labelText: 'Counter-offer ≥',
                                ),
                                onChanged: _commitCounterOfferRate,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(child: SizedBox.shrink()),
                          ],
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
