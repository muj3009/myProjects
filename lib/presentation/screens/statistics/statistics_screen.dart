import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/state/statistics_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/repositories/job_repository.dart';
import '../../widgets/section_card.dart';
import '../../widgets/stat_tile.dart';
import 'widgets/decision_breakdown_chart.dart';
import 'widgets/jobs_trend_chart.dart';

/// Statistics dashboard (spec section 22). All figures are computed locally
/// from the on-device job history — nothing here is sent off-device.
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(statisticsControllerProvider);
    final controller = ref.read(statisticsControllerProvider.notifier);
    final stats = state.statistics;

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<StatsRange>(
              segments: const [
                ButtonSegment(value: StatsRange.today, label: Text('Today')),
                ButtonSegment(
                    value: StatsRange.last7Days, label: Text('7 days')),
                ButtonSegment(
                    value: StatsRange.last30Days, label: Text('30 days')),
                ButtonSegment(
                    value: StatsRange.allTime, label: Text('All time')),
              ],
              selected: {state.range},
              onSelectionChanged: (s) => controller.setRange(s.first),
            ),
            const SizedBox(height: 16),
            if (state.isLoading)
              const Center(child: CircularProgressIndicator()),
            _HeroCard(stats: stats),
            const SizedBox(height: 16),
            DecisionBreakdownChart(
              accepted: stats.jobsAccepted,
              rejected: stats.jobsRejected,
              counterOffered: stats.jobsCounterOffered,
              other: stats.jobsPending,
            ),
            if (stats.dailyBreakdown.length > 1) ...[
              const SizedBox(height: 16),
              JobsTrendChart(days: stats.dailyBreakdown),
            ],
            const SizedBox(height: 28),
            _SectionHeader(label: 'AVERAGES'),
            const SizedBox(height: 8),
            SectionCard(
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.4,
                children: [
                  StatTile(
                    label: 'Average fare',
                    value: '£${stats.averageFare.toStringAsFixed(2)}',
                    icon: Icons.receipt_long_outlined,
                  ),
                  StatTile(
                    label: 'Average £/mile',
                    value: '£${stats.averagePoundsPerMile.toStringAsFixed(2)}',
                    icon: Icons.speed,
                  ),
                  StatTile(
                    label: 'Average trip distance',
                    value:
                        '${stats.averageTripDistanceMiles.toStringAsFixed(1)} mi',
                    icon: Icons.route_outlined,
                  ),
                  StatTile(
                    label: 'Acceptance rate',
                    value:
                        '${(stats.acceptanceRate * 100).toStringAsFixed(0)}%',
                    icon: Icons.thumb_up_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            _SectionHeader(label: 'MONEY'),
            const SizedBox(height: 8),
            SectionCard(
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.4,
                children: [
                  StatTile(
                    label: 'Total potential fare',
                    value: '£${stats.totalPotentialFare.toStringAsFixed(2)}',
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  StatTile(
                    label: 'Accepted fare',
                    value: '£${stats.acceptedFare.toStringAsFixed(2)}',
                    color: StatusColors.accepted,
                    icon: Icons.check_circle_outline,
                  ),
                  StatTile(
                    label: 'Rejected fare',
                    value: '£${stats.rejectedFare.toStringAsFixed(2)}',
                    color: StatusColors.rejected,
                    icon: Icons.cancel_outlined,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

/// Headline figure at the top of the screen — what the driver actually
/// earned (accepted fare) in the selected range, not the total of every job
/// seen, since that's the number that answers "how did I do?" at a glance.
/// Acceptance rate rides alongside as the secondary figure, since a driver
/// judging their own filter rules cares about both together, not just one.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.stats});

  final JobStatistics stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Accepted fare',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  '£${stats.acceptedFare.toStringAsFixed(2)}',
                  style: theme.textTheme.headlineLarge
                      ?.copyWith(color: StatusColors.accepted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(stats.acceptanceRate * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                Text(
                  'accepted',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
