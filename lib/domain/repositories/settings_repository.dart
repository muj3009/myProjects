import '../../core/utils/result.dart';
import '../entities/driver_settings.dart';

/// Local persistence contract for [DriverSettings] (spec section 41).
abstract interface class SettingsRepository {
  Future<Result<DriverSettings>> load();

  Future<Result<void>> save(DriverSettings settings);
}
