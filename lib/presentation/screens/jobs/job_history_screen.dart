import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/state/job_history_controller.dart';
import '../../../domain/entities/taxi_job.dart';
import '../../../domain/enums/job_decision.dart';
import '../../../domain/enums/platform_type.dart';
import '../../../domain/repositories/job_repository.dart';
import '../../widgets/decision_badge.dart';
import '../../widgets/hero_header.dart';
import '../../widgets/hero_pill.dart';
import '../../widgets/section_card.dart';
import '../../widgets/tinted_icon_circle.dart';

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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            HeroHeader(
              child: _JobsHeroBody(
                jobs: state.jobs,
                filterLabel: _labelFor(_active),
                isAllFilter: _active == _QuickFilter.all,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [
                    for (final filter in _QuickFilter.values) ...[
                      ChoiceChip(
                        avatar: TintedIconCircle(
                          icon: _iconFor(filter),
                          color: _colorFor(filter),
                          diameter: 18,
                          iconSize: 10,
                        ),
                        showCheckmark: false,
                        label: Text(_labelFor(filter)),
                        selected: _active == filter,
                        selectedColor: _colorFor(filter).withValues(alpha: 0.18),
                        onSelected: (_) => _applyFilter(filter),
                      ),
                      const SizedBox(width: 6),
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
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          itemCount: state.jobs.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _JobHistoryTile(job: state.jobs[i]),
                          ),
                        ),
            ),
          ],
        ),
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

  // A vivid, distinct hue per filter (amber/blue/purple/green/red/orange) —
  // matching the driver-requested reference palette — rather than the app's
  // own more muted StatusColors. Accepted/Rejected still land on green/red
  // respectively so the basic accept-good/reject-bad convention isn't lost.
  Color _colorFor(_QuickFilter filter) => switch (filter) {
        _QuickFilter.all => const Color(0xFF4C6EF5),
        _QuickFilter.accepted => const Color(0xFF2FA968),
        _QuickFilter.rejected => const Color(0xFFE5484D),
        _QuickFilter.errors => const Color(0xFFA855F7),
        _QuickFilter.uber => const Color(0xFFD4A72C),
        _QuickFilter.bolt => const Color(0xFFF2994A),
      };

  IconData _iconFor(_QuickFilter filter) => switch (filter) {
        _QuickFilter.all => Icons.apps,
        _QuickFilter.accepted => Icons.check_circle,
        _QuickFilter.rejected => Icons.cancel,
        _QuickFilter.errors => Icons.error_outline,
        _QuickFilter.uber => Icons.directions_car_filled_outlined,
        _QuickFilter.bolt => Icons.electric_car_outlined,
      };
}

/// The hero's content: screen title plus "how's my day going" at a glance —
/// the same job-to-be-done the Rules screen's hero solves ("is this
/// actually what I think it is"), applied to job history instead of rule
/// configuration. [jobs] is whatever the active filter currently shows, so
/// the status line always describes what's actually on screen (a narrowed
/// filter — "Rejected: 3 jobs" — rather than repeating the unfiltered total
/// or, worse, claiming there's nothing when a filter just has zero matches).
class _JobsHeroBody extends StatelessWidget {
  const _JobsHeroBody({required this.jobs, required this.filterLabel, required this.isAllFilter});

  final List<TaxiJob> jobs;
  final String filterLabel;
  final bool isAllFilter;

  @override
  Widget build(BuildContext context) {
    final accepted = jobs.where((j) => j.decision == JobDecision.accepted).toList();
    final rejected = jobs.where((j) => j.decision == JobDecision.rejected).length;
    final earned = accepted.fold<double>(0, (sum, j) => sum + (j.fare ?? 0));
    final count = jobs.length;
    final statusLine = isAllFilter
        ? '$count job${count == 1 ? '' : 's'} recorded'
        : '$filterLabel: $count job${count == 1 ? '' : 's'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Jobs',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -0.3)),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.local_taxi_outlined, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              statusLine,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ],
        ),
        // The accepted/rejected/earned breakdown only makes sense against
        // the unfiltered, non-empty list — breaking an already-"Accepted"-
        // filtered list down into "accepted vs rejected" would be a
        // tautology, and an empty list already gets its own full
        // explanation from [_EmptyState] directly below, so repeating it
        // here too would just be noise stacked on noise.
        if (isAllFilter && jobs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              HeroPill(label: '${accepted.length} accepted'),
              HeroPill(label: '$rejected rejected'),
              if (earned > 0) HeroPill(label: '£${earned.toStringAsFixed(2)} earned'),
            ],
          ),
        ],
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 44, color: onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Text(
              'No jobs yet',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: onSurfaceVariant),
            ),
            const SizedBox(height: 4),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        platform.displayName.toUpperCase(),
        style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 10,
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
                    const SizedBox(width: 6),
                    Text(timeLabel,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 4),
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
                  const SizedBox(height: 6),
                  Divider(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.5)),
                  const SizedBox(height: 6),
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
          const SizedBox(width: 6),
          DecisionBadge(decision: job.decision),
        ],
      ),
    );
  }
}
