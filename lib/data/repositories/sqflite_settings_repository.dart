import 'package:sqflite/sqflite.dart';

import '../../core/errors/failures.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/result.dart';
import '../../domain/entities/driver_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../database/app_database.dart';
import '../models/driver_settings_mapper.dart';

/// [SettingsRepository] backed by a single-row SQLite table. A missing row
/// (fresh install) yields the built-in [DriverSettings] defaults rather than
/// an error, so the app is usable with zero configuration.
class SqfliteSettingsRepository implements SettingsRepository {
  SqfliteSettingsRepository({AppDatabase? database}) : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;
  static const _tag = 'SettingsRepository';

  @override
  Future<Result<DriverSettings>> load() async {
    try {
      final db = await _database.database;
      final rows = await db.query(
        AppDatabase.settingsTable,
        where: 'id = ?',
        whereArgs: [DriverSettingsMapper.singletonRowId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return const Result.ok(DriverSettings());
      }
      return Result.ok(DriverSettingsMapper.fromRow(rows.first));
    } catch (e) {
      AppLogger.instance.error(_tag, 'Failed to load settings: $e');
      return Result.err(DatabaseFailure('Failed to load settings: $e'));
    }
  }

  @override
  Future<Result<void>> save(DriverSettings settings) async {
    try {
      final db = await _database.database;
      await db.insert(
        AppDatabase.settingsTable,
        DriverSettingsMapper.toRow(settings),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return const Result.ok(null);
    } catch (e) {
      AppLogger.instance.error(_tag, 'Failed to save settings: $e');
      return Result.err(DatabaseFailure('Failed to save settings: $e'));
    }
  }
}
