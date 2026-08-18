import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_logger.dart';
import '../../domain/repositories/job_repository.dart';
import 'providers.dart';

class StatisticsState {
  const StatisticsState({
    this.range = StatsRange.today,
    this.statistics = JobStatistics.empty,
    this.isLoading = false,
  });

  final StatsRange range;
  final JobStatistics statistics;
  final bool isLoading;

  StatisticsState copyWith({StatsRange? range, JobStatistics? statistics, bool? isLoading}) {
    return StatisticsState(
      range: range ?? this.range,
      statistics: statistics ?? this.statistics,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Backs the Statistics dashboard (spec section 22).
class StatisticsController extends StateNotifier<StatisticsState> {
  StatisticsController(this._repository) : super(const StatisticsState()) {
    refresh();
  }

  final JobRepository _repository;
  static const _tag = 'StatisticsController';

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    final result = await _repository.getStatistics(range: state.range);
    result.when(
      ok: (stats) => state = state.copyWith(statistics: stats, isLoading: false),
      err: (f) {
        AppLogger.instance.error(_tag, 'Failed to load statistics: $f');
        state = state.copyWith(isLoading: false);
      },
    );
  }

  Future<void> setRange(StatsRange range) async {
    state = state.copyWith(range: range);
    await refresh();
  }
}

final statisticsControllerProvider =
    StateNotifierProvider<StatisticsController, StatisticsState>((ref) {
  return StatisticsController(ref.watch(jobRepositoryProvider));
});
