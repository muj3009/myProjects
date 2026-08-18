import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_logger.dart';
import '../../domain/entities/taxi_job.dart';
import '../../domain/repositories/job_repository.dart';
import '../controllers/automation_controller.dart';
import '../controllers/automation_state.dart';
import 'providers.dart';

class JobHistoryState {
  const JobHistoryState({
    this.jobs = const [],
    this.filter = const JobHistoryFilter(),
    this.isLoading = false,
  });

  final List<TaxiJob> jobs;
  final JobHistoryFilter filter;
  final bool isLoading;

  JobHistoryState copyWith({List<TaxiJob>? jobs, JobHistoryFilter? filter, bool? isLoading}) {
    return JobHistoryState(
      jobs: jobs ?? this.jobs,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Backs the Job History screen (spec section 21), including its
/// All/Accepted/Rejected/Errors/Uber/Bolt filters.
class JobHistoryController extends StateNotifier<JobHistoryState> {
  JobHistoryController(this._repository, Ref ref) : super(const JobHistoryState()) {
    refresh();
    // Keep the list live: a job the automation loop just saved should
    // appear here immediately rather than requiring the driver to close
    // and reopen the app to see it.
    ref.listen<AutomationState>(automationControllerProvider, (previous, next) {
      if (next.lastJob != null && next.lastJob != previous?.lastJob) {
        refresh();
      }
    });
  }

  final JobRepository _repository;
  static const _tag = 'JobHistoryController';

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    final result = await _repository.getHistory(filter: state.filter);
    result.when(
      ok: (jobs) => state = state.copyWith(jobs: jobs, isLoading: false),
      err: (f) {
        AppLogger.instance.error(_tag, 'Failed to load history: $f');
        state = state.copyWith(isLoading: false);
      },
    );
  }

  Future<void> applyFilter(JobHistoryFilter filter) async {
    state = state.copyWith(filter: filter);
    await refresh();
  }

  Future<void> clearHistory() async {
    await _repository.clearHistory();
    await refresh();
  }
}

final jobHistoryControllerProvider =
    StateNotifierProvider<JobHistoryController, JobHistoryState>((ref) {
  return JobHistoryController(ref.watch(jobRepositoryProvider), ref);
});
