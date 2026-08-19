import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/state/job_history_controller.dart';
import '../../../domain/entities/taxi_job.dart';
import '../../../domain/enums/job_decision.dart';
import '../../../domain/enums/platform_type.dart';
import '../../../domain/repositories/job_repository.dart';
import '../../widgets/decision_badge.dart';
import '../../widgets/section_card.dart';
import '../../widgets/summary_card.dart';

enum _QuickFilter { all, accepted, rejected, errors, uber, bolt }

/// Job History (spec section 21) with the All/Accepted/Rejected/Errors/
/// Uber/Bolt filter set.
class JobHistoryScreen extends ConsumerStatefulWidget {
  const JobHistoryScreen({super.key});

  @override
  ConsumerState<JobHistoryScreen> createState() => _JobHistoryScreenState();
}

class _JobHistoryScreenState extends ConsumerState<JobHistoryScreen> {
  _QuickFilter _active = _QuickFilter.all;

  void _applyFilter(_QuickFilter filter) {
    setState(() => _active = filter);
    final controller = ref.read(jobHistoryControllerProvider.notifier);
    final jobFilter = switch (filter) {
      _QuickFilter.all => const JobHistoryFilter(),
      _QuickFilter.accepted =>
        const JobHistoryFilter(decision: JobDecision.accepted),
      _QuickFilter.rejected =>
        const JobHistoryFilter(decision: JobDecision.rejected),
      _QuickFilter.errors =>
        const JobHistoryFilter(decision: JobDecision.error),
      _QuickFilter.uber => const JobHistoryFilter(platform: PlatformType.uber),
      _QuickFilter.bolt => const JobHistoryFilter(platform: PlatformType.bolt),
    };
    controller.applyFilter(jobFilter);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(jobHistoryControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Jobs')),
      body: Column(
        children: [
          // Only meaningful against the unfiltered, non-empty list — a
          // summary of a list already narrowed to "Rejected" would just
          // repeat what the list itself already shows, and an empty history
          // already gets its own full explanation from [_EmptyState] below,
          // so a second "no jobs yet" card right above it would be noise.
          if (_active == _QuickFilter.all && state.jobs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _JobsSummaryCard(jobs: state.jobs),
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final filter in _QuickFilter.values) ...[
                    ChoiceChip(
                      label: Text(_labelFor(filter)),
                      selected: _active == filter,
                      onSelected: (_) => _applyFilter(filter),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : state.jobs.isEmpty
                    ? const _EmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: state.jobs.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _JobHistoryTile(job: state.jobs[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _labelFor(_QuickFilter filter) => switch (filter) {
        _QuickFilter.all => 'All',
        _QuickFilter.accepted => 'Accepted',
        _QuickFilter.rejected => 'Rejected',
        _QuickFilter.errors => 'Errors',
        _QuickFilter.uber => 'Uber',
        _QuickFilter.bolt => 'Bolt',
      };
}

/// "How's my day going" at a glance — the same job-to-be-done the Rules
/// screen's summary card solves ("is this actually what I think it is"),
/// applied to job history instead of rule configuration. Only ever rendered
/// with a non-empty [jobs] — [_EmptyState] already covers the empty case.
class _JobsSummaryCard extends StatelessWidget {
  const _JobsSummaryCard({required this.jobs});

  final List<TaxiJob> jobs;

  @override
  Widget build(BuildContext context) {
    final accepted = jobs.where((j) => j.decision == JobDecision.accepted).toList();
    final rejected = jobs.where((j) => j.decision == JobDecision.rejected).length;
    final earned = accepted.fold<double>(0, (sum, j) => sum + (j.fare ?? 0));

    return SummaryCard(
      icon: Icons.local_taxi_outlined,
      headline: '${jobs.length} job${jobs.length == 1 ? '' : 's'} recorded',
      chips: [
        '${accepted.length} accepted',
        '$rejected rejected',
        if (earned > 0) '£${earned.toStringAsFixed(2)} earned',
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 56, color: onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'No jobs yet',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              'Jobs JobFilter sees while automation is running will show up here.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.platform});

  final PlatformType platform;

  @override
  Widget build(BuildContext context) {
    final isUber = platform == PlatformType.uber;
    final color = isUber ? Colors.black : const Color(0xFF34D186);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        platform.displayName.toUpperCase(),
        style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 0.4),
      ),
    );
  }
}

class _JobHistoryTile extends StatelessWidget {
  const _JobHistoryTile({required this.job});

  final TaxiJob job;

  @override
  Widget build(BuildContext context) {
    final timeLabel = DateFormat('EEE HH:mm').format(job.detectedAt);
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _PlatformBadge(platform: job.platform),
                    const SizedBox(width: 8),
                    Text(timeLabel,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  job.fare != null
                      ? '£${job.fare!.toStringAsFixed(2)}'
                      : 'Fare unknown',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (job.tripDistanceMiles != null)
                  Text(
                    '${job.tripDistanceMiles!.toStringAsFixed(1)} miles'
                    '${job.poundsPerMile != null ? ' · £${job.poundsPerMile!.toStringAsFixed(2)}/mile' : ''}',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: onSurfaceVariant),
                  ),
                if (job.decisionReason != null) ...[
                  const SizedBox(height: 8),
                  Divider(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.5)),
                  const SizedBox(height: 8),
                  Text(
                    'Reason',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    job.decisionReason!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          DecisionBadge(decision: job.decision),
        ],
      ),
    );
  }
}
