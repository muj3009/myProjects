import '../../core/errors/failures.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/result.dart';
import '../../domain/entities/taxi_job.dart';
import '../../domain/enums/job_decision.dart';
import '../../domain/repositories/job_repository.dart';
import '../database/app_database.dart';
import '../models/taxi_job_mapper.dart';

/// [JobRepository] backed by the local SQLite database. All reads/writes are
/// on-device only (spec section 27) — nothing here makes a network call.
class SqfliteJobRepository implements JobRepository {
  SqfliteJobRepository({AppDatabase? database}) : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;
  static const _tag = 'JobRepository';

  @override
  Future<Result<void>> save(TaxiJob job) async {
    try {
      final db = await _database.database;
      await db.insert(AppDatabase.jobsTable, TaxiJobMapper.toRow(job));
      return const Result.ok(null);
    } catch (e) {
      AppLogger.instance.error(_tag, 'Failed to save job ${job.id}: $e');
      return Result.err(DatabaseFailure('Failed to save job: $e'));
    }
  }

  @override
  Future<Result<List<TaxiJob>>> getHistory({JobHistoryFilter filter = const JobHistoryFilter()}) async {
    try {
      final db = await _database.database;
      final where = <String>[];
      final args = <Object?>[];

      if (filter.decision != null) {
        where.add('decision = ?');
        args.add(filter.decision!.name);
      }
      if (filter.platform != null) {
        where.add('platform = ?');
        args.add(filter.platform!.name);
      }
      if (filter.since != null) {
        where.add('detected_at >= ?');
        args.add(filter.since!.toIso8601String());
      }

      final rows = await db.query(
        AppDatabase.jobsTable,
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: where.isEmpty ? null : args,
        orderBy: 'detected_at DESC',
      );

      return Result.ok(rows.map(TaxiJobMapper.fromRow).toList());
    } catch (e) {
      AppLogger.instance.error(_tag, 'Failed to load history: $e');
      return Result.err(DatabaseFailure('Failed to load job history: $e'));
    }
  }

  @override
  Future<Result<JobStatistics>> getStatistics({StatsRange range = StatsRange.today}) async {
    try {
      final since = _rangeStart(range);
      final historyResult = await getHistory(
        filter: JobHistoryFilter(since: since),
      );
      return historyResult.when(
        ok: (jobs) => Result.ok(_computeStatistics(jobs, since)),
        err: (f) => Result.err(f),
      );
    } catch (e) {
      AppLogger.instance.error(_tag, 'Failed to compute statistics: $e');
      return Result.err(DatabaseFailure('Failed to compute statistics: $e'));
    }
  }

  @override
  Future<Result<void>> clearHistory() async {
    try {
      final db = await _database.database;
      await db.delete(AppDatabase.jobsTable);
      return const Result.ok(null);
    } catch (e) {
      AppLogger.instance.error(_tag, 'Failed to clear history: $e');
      return Result.err(DatabaseFailure('Failed to clear job history: $e'));
    }
  }

  DateTime? _rangeStart(StatsRange range) {
    final now = DateTime.now();
    return switch (range) {
      StatsRange.today => DateTime(now.year, now.month, now.day),
      StatsRange.last7Days => now.subtract(const Duration(days: 7)),
      StatsRange.last30Days => now.subtract(const Duration(days: 30)),
      StatsRange.allTime => null,
    };
  }

  JobStatistics _computeStatistics(List<TaxiJob> jobs, DateTime? since) {
    if (jobs.isEmpty) return JobStatistics.empty;

    final accepted = jobs.where((j) => j.decision == JobDecision.accepted).toList();
    final rejected = jobs.where((j) => j.decision == JobDecision.rejected).toList();
    final counterOffered = jobs.where((j) => j.decision == JobDecision.counterOffered).toList();
    final pending = jobs.where(
      (j) => j.decision != JobDecision.accepted &&
          j.decision != JobDecision.rejected &&
          j.decision != JobDecision.counterOffered,
    ).toList();
    final withFare = jobs.where((j) => j.fare != null).toList();
    final withRate = jobs.where((j) => j.poundsPerMile != null).toList();
    final withDistance = jobs.where((j) => j.tripDistanceMiles != null).toList();

    double avg(List<double> values) =>
        values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

    return JobStatistics(
      jobsDetected: jobs.length,
      jobsAccepted: accepted.length,
      jobsRejected: rejected.length,
      jobsCounterOffered: counterOffered.length,
      jobsPending: pending.length,
      averageFare: avg(withFare.map((j) => j.fare!).toList()),
      averagePoundsPerMile: avg(withRate.map((j) => j.poundsPerMile!).toList()),
      averageTripDistanceMiles: avg(withDistance.map((j) => j.tripDistanceMiles!).toList()),
      totalPotentialFare: withFare.fold(0.0, (sum, j) => sum + j.fare!),
      acceptedFare: accepted.where((j) => j.fare != null).fold(0.0, (sum, j) => sum + j.fare!),
      rejectedFare: rejected.where((j) => j.fare != null).fold(0.0, (sum, j) => sum + j.fare!),
      dailyBreakdown: _computeDailyBreakdown(jobs, since),
    );
  }

  /// Builds one [DailyJobCount] per calendar day from [since] (or the
  /// earliest job in an "all time" range with no [since]) through today,
  /// including days with zero jobs — see [JobStatistics.dailyBreakdown] for
  /// why gaps are kept rather than skipped. Capped to the most recent 30
  /// days even for "all time" so the trend chart never has to lay out an
  /// unbounded number of days on a phone-width screen.
  List<DailyJobCount> _computeDailyBreakdown(List<TaxiJob> jobs, DateTime? since) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var start = since != null
        ? DateTime(since.year, since.month, since.day)
        : jobs.map((j) => DateTime(j.detectedAt.year, j.detectedAt.month, j.detectedAt.day)).reduce(
              (a, b) => a.isBefore(b) ? a : b,
            );
    final earliestAllowed = today.subtract(const Duration(days: 29));
    if (start.isBefore(earliestAllowed)) start = earliestAllowed;

    final byDay = <DateTime, List<TaxiJob>>{};
    for (final job in jobs) {
      final day = DateTime(job.detectedAt.year, job.detectedAt.month, job.detectedAt.day);
      byDay.putIfAbsent(day, () => []).add(job);
    }

    final result = <DailyJobCount>[];
    for (var day = start; !day.isAfter(today); day = day.add(const Duration(days: 1))) {
      final dayJobs = byDay[day] ?? const <TaxiJob>[];
      result.add(
        DailyJobCount(
          day: day,
          accepted: dayJobs.where((j) => j.decision == JobDecision.accepted).length,
          rejected: dayJobs.where((j) => j.decision == JobDecision.rejected).length,
          counterOffered: dayJobs.where((j) => j.decision == JobDecision.counterOffered).length,
          other: dayJobs
              .where(
                (j) => j.decision != JobDecision.accepted &&
                    j.decision != JobDecision.rejected &&
                    j.decision != JobDecision.counterOffered,
              )
              .length,
        ),
      );
    }
    return result;
  }
}
