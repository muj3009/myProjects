import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../domain/repositories/job_repository.dart';
import '../../../widgets/section_card.dart';

/// Stacked bar chart of jobs per day — one bar per day, segmented by
/// decision (same colors as [DecisionBreakdownChart], so identity carries
/// across both charts on this screen). Only rendered when there's more than
/// one day in range (see [JobStatistics.dailyBreakdown]); a single-day
/// range like "Today" has nothing to trend and the donut above already
/// covers it.
class JobsTrendChart extends StatefulWidget {
  const JobsTrendChart({super.key, required this.days});

  final List<DailyJobCount> days;

  @override
  State<JobsTrendChart> createState() => _JobsTrendChartState();
}

class _JobsTrendChartState extends State<JobsTrendChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxTotal =
        widget.days.map((d) => d.total).fold(0, (a, b) => a > b ? a : b);
    // A flat all-zero range would otherwise divide the chart's y-scale by
    // zero — 1 keeps the axis sane and just shows empty bars.
    final maxY = (maxTotal == 0 ? 1 : maxTotal).toDouble();

    // Showing a label under every single bar overlaps badly past ~10 days —
    // thin the labels out so at most ~7 are ever shown, evenly spaced.
    final labelStride =
        (widget.days.length / 7).ceil().clamp(1, widget.days.length);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Jobs over time', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          SizedBox(
            height: 140,
            child: BarChart(
              BarChartData(
                maxY: maxY * 1.2,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: (maxY / 3).clamp(1, double.infinity),
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: theme.dividerColor, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= widget.days.length)
                          return const SizedBox.shrink();
                        if (index % labelStride != 0)
                          return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            DateFormat('d MMM').format(widget.days[index].day),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchCallback: (event, response) {
                    setState(() {
                      _touchedIndex = response?.spot?.touchedBarGroupIndex;
                    });
                  },
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final day = widget.days[groupIndex];
                      return BarTooltipItem(
                        '${DateFormat('EEE d MMM').format(day.day)}\n'
                        'Accepted: ${day.accepted}  Rejected: ${day.rejected}\n'
                        'Counter-offered: ${day.counterOffered}  Other: ${day.other}',
                        theme.textTheme.bodyMedium!
                            .copyWith(color: Colors.white, fontSize: 12),
                      );
                    },
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < widget.days.length; i++)
                    _buildGroup(i, widget.days[i]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _LegendDot(color: StatusColors.accepted, label: 'Accepted'),
              _LegendDot(color: StatusColors.rejected, label: 'Rejected'),
              _LegendDot(
                  color: StatusColors.counterOffered, label: 'Counter-offered'),
              _LegendDot(color: StatusColors.pendingOrUnknown, label: 'Other'),
            ],
          ),
        ],
      ),
    );
  }

  BarChartGroupData _buildGroup(int index, DailyJobCount day) {
    final isTouched = index == _touchedIndex;
    // Stacked segments in a fixed, consistent order (accepted at the
    // baseline, then rejected, counter-offered, other) with a hairline
    // surface gap between each so adjacent same-bar segments never visually
    // fuse into one block.
    var y = 0.0;
    final segments = <({int count, Color color})>[
      (count: day.accepted, color: StatusColors.accepted),
      (count: day.rejected, color: StatusColors.rejected),
      (count: day.counterOffered, color: StatusColors.counterOffered),
      (count: day.other, color: StatusColors.pendingOrUnknown),
    ];
    final stackItems = <BarChartRodStackItem>[];
    for (final segment in segments) {
      if (segment.count == 0) continue;
      final from = y;
      final to = y + segment.count;
      stackItems.add(BarChartRodStackItem(from + 0.04, to, segment.color));
      y = to;
    }

    return BarChartGroupData(
      x: index,
      barRods: [
        BarChartRodData(
          toY: day.total.toDouble(),
          rodStackItems: stackItems,
          width: isTouched ? 16 : 12,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12)),
      ],
    );
  }
}
