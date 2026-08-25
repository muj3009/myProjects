import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../widgets/section_card.dart';

/// Donut chart + legend showing how detected jobs were decided — accepted,
/// rejected, counter-offered, or still pending/other. Reuses the exact same
/// four colors [DecisionBadge] uses for each outcome elsewhere in the app
/// (Job History, Simulation), so a color always means the same decision
/// everywhere the driver sees it, not just on this screen.
class DecisionBreakdownChart extends StatefulWidget {
  const DecisionBreakdownChart({
    super.key,
    required this.accepted,
    required this.rejected,
    required this.counterOffered,
    required this.other,
  });

  final int accepted;
  final int rejected;
  final int counterOffered;
  final int other;

  @override
  State<DecisionBreakdownChart> createState() => _DecisionBreakdownChartState();
}

class _DecisionBreakdownChartState extends State<DecisionBreakdownChart> {
  int? _touchedIndex;

  int get _total =>
      widget.accepted + widget.rejected + widget.counterOffered + widget.other;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = [
      (label: 'Accepted', value: widget.accepted, color: StatusColors.accepted),
      (label: 'Rejected', value: widget.rejected, color: StatusColors.rejected),
      (
        label: 'Counter-offered',
        value: widget.counterOffered,
        color: StatusColors.counterOffered
      ),
      (
        label: 'Other',
        value: widget.other,
        color: StatusColors.pendingOrUnknown
      ),
    ].where((e) => e.value > 0).toList();

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Decision breakdown', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          if (_total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text('No jobs in this range yet',
                    style: theme.textTheme.bodyMedium),
              ),
            )
          else
            Row(
              children: [
                SizedBox(
                  height: 120,
                  width: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sections: [
                            for (var i = 0; i < entries.length; i++)
                              PieChartSectionData(
                                value: entries[i].value.toDouble(),
                                color: entries[i].color,
                                radius: i == _touchedIndex ? 22 : 19,
                                showTitle: false,
                              ),
                          ],
                          sectionsSpace: 2,
                          centerSpaceRadius: 34,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, response) {
                              setState(() {
                                _touchedIndex = response
                                    ?.touchedSection?.touchedSectionIndex;
                              });
                            },
                          ),
                        ),
                      ),
                      // The center label doubles as a selective direct label:
                      // total by default, or the tapped slice's own count —
                      // never a number crammed onto every slice at once.
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_touchedIndex != null ? entries[_touchedIndex!].value : _total}',
                            style: theme.textTheme.headlineMedium,
                          ),
                          Text(
                            _touchedIndex != null
                                ? entries[_touchedIndex!].label
                                : 'Total',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entry in entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: entry.color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(entry.label,
                                      style: theme.textTheme.bodyMedium)),
                              Text(
                                '${entry.value}',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
