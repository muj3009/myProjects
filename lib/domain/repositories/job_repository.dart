import '../../core/utils/result.dart';
import '../entities/taxi_job.dart';
import '../enums/job_decision.dart';
import '../enums/platform_type.dart';

/// Filter used by the Job History screen (spec section 21).
class JobHistoryFilter {
  const JobHistoryFilter({this.decision, this.platform, this.since});

  final JobDecision? decision;
  final PlatformType? platform;
  final DateTime? since;
}

/// Time window used by the Statistics screen (spec section 22).
enum StatsRange { today, last7Days, last30Days, allTime }

class JobStatistics {
  const JobStatistics({
    required this.jobsDetected,
    required this.jobsAccepted,
    required this.jobsRejected,
    required this.jobsCounterOffered,
    required this.jobsPending,
    required this.averageFare,
    required this.averagePoundsPerMile,
    required this.averageTripDistanceMiles,
    required this.totalPotentialFare,
    required this.acceptedFare,
    required this.rejectedFare,
    required this.dailyBreakdown,
  });

  final int jobsDetected;
  final int jobsAccepted;
  final int jobsRejected;
  final int jobsCounterOffered;
  final int jobsPending;
  final double averageFare;
  final double averagePoundsPerMile;
  final double averageTripDistanceMiles;
  final double totalPotentialFare;
  final double acceptedFare;
  final double rejectedFare;

  /// One entry per calendar day in the selected range, oldest first — powers
  /// the Statistics screen's jobs-over-time trend chart. Empty days are
  /// still present (with zero counts) so the chart's x-axis stays evenly
  /// spaced rather than skipping gaps.
  final List<DailyJobCount> dailyBreakdown;

  double get acceptanceRate => jobsDetected == 0 ? 0 : jobsAccepted / jobsDetected;

  static const empty = JobStatistics(
    jobsDetected: 0,
    jobsAccepted: 0,
    jobsRejected: 0,
    jobsCounterOffered: 0,
    jobsPending: 0,
    averageFare: 0,
    averagePoundsPerMile: 0,
    averageTripDistanceMiles: 0,
    totalPotentialFare: 0,
    acceptedFare: 0,
    rejectedFare: 0,
    dailyBreakdown: [],
  );
}

/// One day's job counts, by decision — see [JobStatistics.dailyBreakdown].
class DailyJobCount {
  const DailyJobCount({
    required this.day,
    required this.accepted,
    required this.rejected,
    required this.counterOffered,
    required this.other,
  });

  /// Midnight, local time, for this day.
  final DateTime day;
  final int accepted;
  final int rejected;
  final int counterOffered;

  /// Pending/ignored/error — grouped since none are a driver-facing outcome
  /// worth its own series on a trend chart.
  final int other;

  int get total => accepted + rejected + counterOffered + other;
}

/// Local, on-device persistence contract for jobs (spec sections 21/22/41).
/// The data layer's SqfliteJobRepository is the only implementation today;
/// this interface exists so the application layer never depends on sqflite
/// directly, and so a future implementation (e.g. an in-memory test double)
/// is a drop-in replacement.
abstract interface class JobRepository {
  Future<Result<void>> save(TaxiJob job);

  Future<Result<List<TaxiJob>>> getHistory({JobHistoryFilter filter = const JobHistoryFilter()});

  Future<Result<JobStatistics>> getStatistics({StatsRange range = StatsRange.today});

  Future<Result<void>> clearHistory();
}
