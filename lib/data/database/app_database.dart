import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Single on-device SQLite database (spec section 41). All persistence is
/// local-first per spec section 27 — nothing here is synced off-device.
///
/// Schema is intentionally simple (two tables) and additive: new nullable
/// columns can be appended in a future migration without breaking existing
/// rows, per "Design the schema so new fields can be added later."
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const int schemaVersion = 2;
  static const String jobsTable = 'jobs';
  static const String settingsTable = 'settings';

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final opened = await _open();
    _db = opened;
    return opened;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'jobfilter.db');
    return openDatabase(
      dbPath,
      version: schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $jobsTable (
            id TEXT PRIMARY KEY,
            platform TEXT NOT NULL,
            fare REAL,
            trip_distance_miles REAL,
            pickup_distance_miles REAL,
            estimated_duration_minutes INTEGER,
            pickup_address TEXT,
            destination_address TEXT,
            destination_postcode TEXT,
            detected_at TEXT NOT NULL,
            decision TEXT NOT NULL,
            pounds_per_mile REAL,
            estimated_hourly_rate REAL,
            rejection_reason TEXT,
            raw_detected_text TEXT,
            fingerprint TEXT,
            is_simulated INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX idx_jobs_detected_at ON $jobsTable (detected_at)');
        await db.execute('CREATE INDEX idx_jobs_decision ON $jobsTable (decision)');
        await db.execute('CREATE INDEX idx_jobs_platform ON $jobsTable (platform)');

        await db.execute('''
          CREATE TABLE $settingsTable (
            id INTEGER PRIMARY KEY CHECK (id = 0),
            app_name TEXT NOT NULL,
            automation_enabled INTEGER NOT NULL,
            platform_selection TEXT NOT NULL,
            distance_unit TEXT NOT NULL,
            distance_calculation_mode TEXT NOT NULL,
            currency_code TEXT NOT NULL,
            rules_json TEXT NOT NULL,
            platform_overrides_json TEXT NOT NULL
          )
        ''');
      },
      // Additive only, per this class's own schema doc comment: existing
      // installs (schemaVersion 1, before the destination-postcode
      // blocklist rule existed) get this nullable column added in place —
      // old rows simply read back with destination_postcode = null, which
      // PostcodeBlocklistRule already treats as "not blocked" rather than
      // guessing.
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE $jobsTable ADD COLUMN destination_postcode TEXT');
        }
      },
    );
  }

  /// Test-only hook to point at an isolated in-memory/temp database.
  Future<void> resetForTesting(Database db) async {
    _db = db;
  }
}
