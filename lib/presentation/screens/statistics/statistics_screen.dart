import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/state/statistics_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/repositories/job_repository.dart';
import '../../widgets/hero_header.dart';
import '../../widgets/hero_pill.dart';
import '../../widgets/section_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat_grid.dart';
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            HeroHeader(child: _StatsHeroBody(stats: stats)),
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  children: [
                    SegmentedButton<StatsRange>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: StatsRange.today, label: Text('Today')),
                        ButtonSegment(value: StatsRange.last7Days, label: Text('7d')),
                        ButtonSegment(value: StatsRange.last30Days, label: Text('30d')),
                        ButtonSegment(value: StatsRange.allTime, label: Text('All')),
                      ],
                      selected: {state.range},
                      onSelectionChanged: (s) => controller.setRange(s.first),
                    ),
                    const SizedBox(height: 4),
                    if (state.isLoading)
                      const Center(child: CircularProgressIndicator()),
                    DecisionBreakdownChart(
                      accepted: stats.jobsAccepted,
                      rejected: stats.jobsRejected,
                      counterOffered: stats.jobsCounterOffered,
                      other: stats.jobsPending,
                    ),
                    if (stats.dailyBreakdown.length > 1) ...[
                      const SizedBox(height: 4),
                      JobsTrendChart(days: stats.dailyBreakdown),
                    ],
                    const SizedBox(height: 6),
                    const SectionHeader('AVERAGES'),
                    SectionCard(
                      padding: const EdgeInsets.all(6),
                      child: StatGrid(
                        tiles: [
                          StatTile(
                            label: 'Avg fare',
                            value: '£${stats.averageFare.toStringAsFixed(2)}',
                            icon: Icons.receipt_long_outlined,
                          ),
                          StatTile(
                            label: 'Avg £/mi',
                            value: '£${stats.averagePoundsPerMile.toStringAsFixed(2)}',
                            icon: Icons.speed,
                          ),
                          StatTile(
                            label: 'Avg trip',
                            value: '${stats.averageTripDistanceMiles.toStringAsFixed(1)}mi',
                            icon: Icons.route_outlined,
                          ),
                          StatTile(
                            label: 'Accept %',
                            value: '${(stats.acceptanceRate * 100).toStringAsFixed(0)}%',
                            icon: Icons.thumb_up_outlined,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const SectionHeader('MONEY'),
                    SectionCard(
                      padding: const EdgeInsets.all(6),
                      child: StatGrid(
                        tiles: [
                          StatTile(
                            label: 'Potential',
                            value: '£${stats.totalPotentialFare.toStringAsFixed(2)}',
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                          StatTile(
                            label: 'Accepted',
                            value: '£${stats.acceptedFare.toStringAsFixed(2)}',
                            color: StatusColors.accepted,
                            icon: Icons.check_circle_outline,
                          ),
                          StatTile(
                            label: 'Rejected',
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
            ),
          ],
        ),
      ),
    );
  }
}

/// The hero's content: screen title plus the headline figure — what the
/// driver actually earned (accepted fare) in the selected range, not the
/// total of every job seen, since that's the number that answers "how did I
/// do?" at a glance. Acceptance rate rides alongside as the secondary
/// figure, since a driver judging their own filter rules cares about both
/// together, not just one.
class _StatsHeroBody extends StatelessWidget {
  const _StatsHeroBody({required this.stats});

  final JobStatistics stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Statistics',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: -0.3)),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Accepted fare',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 1),
                  Text(
                    '£${stats.acceptedFare.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: StatusColors.accepted,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        letterSpacing: -0.5),
                  ),
                ],
              ),
            ),
            HeroPill(
                label:
                    '${(stats.acceptanceRate * 100).toStringAsFixed(0)}% accepted'),
          ],
        ),
      ],
    );
  }
}
