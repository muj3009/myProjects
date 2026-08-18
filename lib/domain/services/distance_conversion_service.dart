import '../../core/constants/app_constants.dart';
import '../enums/distance_unit.dart';

/// All distances are normalized to and stored internally as miles (spec
/// section 43). This service is the single place that conversion happens so
/// parsers, rules, and the UI never duplicate the conversion factor.
class DistanceConversionService {
  const DistanceConversionService._();

  static double kilometresToMiles(double km) => km * AppConstants.kmToMiles;

  static double milesToKilometres(double miles) => miles / AppConstants.kmToMiles;

  /// Converts a stored (miles) value to the driver's preferred display unit.
  static double toDisplayUnit(double miles, DistanceUnit unit) {
    return switch (unit) {
      DistanceUnit.miles => miles,
      DistanceUnit.kilometres => milesToKilometres(miles),
    };
  }

  static String unitSuffix(DistanceUnit unit) => switch (unit) {
        DistanceUnit.miles => 'mi',
        DistanceUnit.kilometres => 'km',
      };

  static String formatDistance(double miles, DistanceUnit unit) {
    final value = toDisplayUnit(miles, unit);
    return '${value.toStringAsFixed(1)} ${unitSuffix(unit)}';
  }
}
